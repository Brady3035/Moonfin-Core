#!/usr/bin/env bash
# Probe a Silo server (and optionally Emby) and save the responses Moonfin's
# Silo support is written against.
#
#   scripts/silo_probe.sh              sample responses into build/silo-probe/<time>/
#   scripts/silo_probe.sh --contract   also re-pin the OpenAPI snapshot in
#                                      packages/server_silo/test/fixtures/
#   scripts/silo_probe.sh --public     only the endpoints that need no sign-in
#
# Silo settings (environment):
#   SILO_URL           required, e.g. https://silo.example.com (no /api/v2)
#   SILO_USERNAME      sign in with this account; the password is prompted for
#                      (or SILO_PASSWORD), and the session is signed out at the end
#   SILO_TOKEN         or reuse an existing access token instead (left signed in)
#   SILO_PROFILE_ID    profile to act as (default: the account's primary profile)
#   SILO_PROFILE_PIN   PIN for that profile, prompted for when it has one
#   SILO_MOVIE         movie content id        (default movie-imdb-tt0295701)
#   SILO_MOVIE_MULTI   movie with two or more versions (skipped when unset)
#   SILO_SERIES        series content id       (default series-tvdb-192061)
#   SILO_EPISODE       episode with markers/trickplay (default episode-tvdb-192061-1-1)
#
# Emby settings (optional; the same titles, for the target shape):
#   EMBY_URL EMBY_TOKEN EMBY_USER_ID
#   EMBY_MOVIE EMBY_MOVIE_MULTI EMBY_SERIES EMBY_EPISODE   Emby item ids
#
# Output: build/silo-probe/<time>/raw/ holds the responses as received (they
# contain signed URLs and file paths, keep them local); .../scrubbed/ holds
# copies safe to commit: tokens, URL signatures, emails and IPs replaced, file
# paths cut to the file name, profile names and the username replaced, and the
# server hosts swapped for silo.example / emby.example. build/ is gitignored.
#
# Needs bash 3.2+ (macOS default), curl and python3.
set -euo pipefail

MODE_CONTRACT=0
MODE_PUBLIC=0
for arg in "$@"; do
  case "$arg" in
    --contract) MODE_CONTRACT=1 ;;
    --public) MODE_PUBLIC=1 ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

: "${SILO_URL:?set SILO_URL, e.g. SILO_URL=https://silo.example.com}"
SILO_URL="${SILO_URL%/}"
SILO_URL="${SILO_URL%/api/v2}"
MOVIE="${SILO_MOVIE:-movie-imdb-tt0295701}"
MOVIE_MULTI="${SILO_MOVIE_MULTI:-}"
SERIES="${SILO_SERIES:-series-tvdb-192061}"
EPISODE="${SILO_EPISODE:-episode-tvdb-192061-1-1}"

for tool in curl python3; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$REPO/build/silo-probe/$STAMP"
mkdir -p "$OUT/raw/silo" "$OUT/raw/emby" "$OUT/scrubbed/silo" "$OUT/scrubbed/emby"
SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"
FAILED=0

HELPER="$(mktemp "${TMPDIR:-/tmp}/silo_probe.XXXXXX")"
cat > "$HELPER" <<'PY'
import hashlib, json, os, re, sys
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

def load(path):
    with open(path, 'rb') as f:
        return json.loads(f.read().decode('utf-8'))

def get(obj, dotted):
    for part in dotted.split('.'):
        if obj is None:
            return None
        if isinstance(obj, list):
            obj = obj[int(part)] if part.isdigit() and int(part) < len(obj) else None
        else:
            obj = obj.get(part)
    return obj

SECRET_KEYS = {'access_token', 'refresh_token', 'profile_token', 'device_code', 'password',
               'accesstoken', 'token', 'secret', 'api_key', 'apikey', 'ticket'}
SIGNED_PARAMS = {'sig', 'st', 'exp', 'token', 'api_key', 'apikey', 'signature', 'expires',
                 'key-pair-id', 'policy', 'x-amz-signature', 'x-amz-credential',
                 'x-amz-security-token', 'x-amz-date'}
IP_KEYS = {'ip', 'ip_address', 'remote_ip', 'remote_address', 'last_ip', 'remoteendpoint',
           'client_ip'}
NAME_FILES = ('profiles', 'account_me', 'auth_login')

def scrub_url(s, hosts):
    if '?' in s and ('/' in s or s.startswith('http')):
        parts = urlsplit(s)
        query = [(k, 'SCRUBBED' if k.lower() in SIGNED_PARAMS else v)
                 for k, v in parse_qsl(parts.query, keep_blank_values=True)]
        s = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query, safe='/:'), parts.fragment))
    for real, fake in hosts:
        if real:
            s = s.replace(real, fake)
    return s

def basename(v):
    if isinstance(v, str) and ('/' in v or '\\' in v):
        return re.split(r'[\\/]', v.rstrip('/\\'))[-1]
    return v

def scrub(node, hosts, names, key=''):
    k = key.lower()
    if isinstance(node, dict):
        return {kk: scrub(vv, hosts, names, kk) for kk, vv in node.items()}
    if isinstance(node, list):
        if k.endswith('_paths') or k == 'paths':
            return [basename(x) for x in node]
        return [scrub(x, hosts, names, key) for x in node]
    if isinstance(node, str):
        if k in SECRET_KEYS and node:
            return 'SCRUBBED'
        if k in IP_KEYS and node:
            return '203.0.113.1'
        if k == 'email' and node:
            return 'user@example.invalid'
        if (k == 'path' or k.endswith('_path')) and not node.startswith('/api/'):
            return basename(node)
        if names is not None and k in ('name', 'username', 'display_name') and node:
            return names.setdefault(node, ('user' if k == 'username' else 'Profile %d' % (len(names) + 1)))
        return scrub_url(node, hosts)
    return node

def main():
    cmd = sys.argv[1]
    if cmd == 'get':
        value = get(load(sys.argv[2]), sys.argv[3])
        print('' if value is None else (json.dumps(value) if isinstance(value, (dict, list)) else value))
    elif cmd == 'first':
        # first <file> <list-path> <field> [<flag-field>]: field of the first item (with flag true)
        items = get(load(sys.argv[2]), sys.argv[3]) or []
        flag = sys.argv[5] if len(sys.argv) > 5 else None
        for item in items:
            if not flag or item.get(flag):
                print(item.get(sys.argv[4]) or '')
                return
        print('')
    elif cmd == 'profile':
        # profile <profiles.json> [<wanted id>]: "<id> <has_pin>" of the wanted or primary profile
        items = load(sys.argv[2]).get('items') or []
        wanted = sys.argv[3] if len(sys.argv) > 3 else ''
        pick = next((p for p in items if p.get('id') == wanted), None) if wanted else None
        pick = pick or next((p for p in items if p.get('is_primary')), None) or (items[0] if items else None)
        print('%s %s' % (pick['id'], 'pin' if pick.get('has_pin') else 'nopin') if pick else '')
    elif cmd == 'json':
        # json <key> <value> ...: a JSON object from pairs read from the environment names given
        print(json.dumps({sys.argv[i]: os.environ.get(sys.argv[i + 1], '') for i in range(2, len(sys.argv), 2)}))
    elif cmd == 'sha256':
        with open(sys.argv[2], 'rb') as f:
            print(hashlib.sha256(f.read()).hexdigest())
    elif cmd == 'scrub':
        src, dst, silo_host, emby_host = sys.argv[2:6]
        hosts = [(silo_host, 'silo.example'), (emby_host, 'emby.example')]
        try:
            data = load(src)
        except Exception:
            return  # not JSON (an error page); leave it out of the scrubbed set
        base = os.path.basename(src)
        names = {} if base.startswith(NAME_FILES) else None
        with open(dst, 'w') as f:
            json.dump(scrub(data, hosts, names), f, indent=1, ensure_ascii=False, sort_keys=False)
            f.write('\n')

main()
PY

HOST_SILO="$(python3 -c 'import sys,urllib.parse as u;print(u.urlsplit(sys.argv[1]).netloc)' "$SILO_URL")"
HOST_EMBY=""
if [ -n "${EMBY_URL:-}" ]; then
  EMBY_URL="${EMBY_URL%/}"
  HOST_EMBY="$(python3 -c 'import sys,urllib.parse as u;print(u.urlsplit(sys.argv[1]).netloc)' "$EMBY_URL")"
fi
helper() { python3 "$HELPER" "$@"; }

DEVICE_ID="moonfin-probe-$(hostname | python3 -c 'import sys,hashlib;print(hashlib.sha256(sys.stdin.read().encode()).hexdigest()[:12])')"
ACCESS_TOKEN="${SILO_TOKEN:-}"
SIGNED_IN=0
PROFILE_ID=""
PROFILE_TOKEN=""

cleanup() {
  if [ "$SIGNED_IN" = 1 ] && [ -n "$ACCESS_TOKEN" ]; then
    code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $ACCESS_TOKEN" "$SILO_URL/api/v2/auth/logout" || true)
    echo "signed out of Silo ($code)"
  fi
  rm -f "$HELPER"
}
trap cleanup EXIT

record() { # record <name> <http code> <what>
  printf '%-30s %s  %s\n' "$1" "$2" "$3" | tee -a "$SUMMARY"
  case "$2" in 2*) ;; *) FAILED=$((FAILED + 1)) ;; esac
}

# silo <name> <path> [METHOD] [json body]
silo() {
  local name="$1" path="$2" method="${3:-GET}" body="${4:-}"
  local args=(-sS -m 45 -X "$method" -o "$OUT/raw/silo/$name.json" -w '%{http_code}'
    -H "Accept: application/json" -H "X-Silo-Client: moonfin-probe"
    -H "X-Silo-Device-Id: $DEVICE_ID" -H "X-Silo-Device-Name: Moonfin probe"
    -H "X-Silo-Device-Platform: script")
  if [ -n "$ACCESS_TOKEN" ]; then args+=(-H "Authorization: Bearer $ACCESS_TOKEN"); fi
  if [ -n "$PROFILE_ID" ]; then args+=(-H "X-Profile-Id: $PROFILE_ID"); fi
  if [ -n "$PROFILE_TOKEN" ]; then args+=(-H "X-Profile-Token: $PROFILE_TOKEN"); fi
  local code
  if [ -n "$body" ]; then
    # The body goes in on stdin so passwords and PINs never show up in `ps`.
    args+=(-H "Content-Type: application/json" --data-binary @-)
    code=$(printf '%s' "$body" | curl "${args[@]}" "$SILO_URL/api/v2$path" || echo 000)
  else
    code=$(curl "${args[@]}" "$SILO_URL/api/v2$path" || echo 000)
  fi
  record "$name" "$code" "$method $path"
}

# emby <name> <path>
emby() {
  local code
  code=$(curl -sS -m 45 -o "$OUT/raw/emby/$1.json" -w '%{http_code}' \
    -H "Accept: application/json" -H "X-Emby-Token: ${EMBY_TOKEN:-}" "$EMBY_URL$2" || echo 000)
  record "emby/$1" "$code" "GET $2"
}

echo "== Silo public ($SILO_URL)"
silo system_info /system/info
silo system_identity /system/identity
silo system_setup /system/setup
silo theme_branding /theme/branding

BUILD="$(helper get "$OUT/raw/silo/system_info.json" server_version)"
DIGEST="$(helper get "$OUT/raw/silo/system_info.json" contract_digest)"
API_MAJOR="$(helper get "$OUT/raw/silo/system_info.json" api_major)"
echo "   server_version=$BUILD api_major=$API_MAJOR"
echo "   contract_digest=$DIGEST"

if [ "$MODE_CONTRACT" = 1 ]; then
  echo "== Contract"
  silo openapi /openapi.json
  SPEC="$OUT/raw/silo/openapi.json"
  GOT="$(helper sha256 "$SPEC")"
  if [ "$GOT" != "$DIGEST" ]; then
    echo "   digest mismatch: file $GOT, server $DIGEST; snapshot not written" >&2
    FAILED=$((FAILED + 1))
  else
    FIX="$REPO/packages/server_silo/test/fixtures"
    SHORT="${BUILD%%+*}"
    mkdir -p "$FIX"
    for old in "$FIX"/openapi-*.json.gz; do
      if [ -e "$old" ] && [ "$old" != "$FIX/openapi-$SHORT.json.gz" ]; then rm -f "$old"; echo "   removed $(basename "$old")"; fi
    done
    gzip -9 -n -c "$SPEC" > "$FIX/openapi-$SHORT.json.gz"
    echo "   wrote packages/server_silo/test/fixtures/openapi-$SHORT.json.gz (digest verified)"
    echo "   update the table in packages/server_silo/test/fixtures/README.md: build $BUILD, digest $DIGEST, date $(date +%Y-%m-%d)"
  fi
fi

if [ "$MODE_PUBLIC" = 0 ]; then
  if [ -z "$ACCESS_TOKEN" ]; then
    if [ -z "${SILO_USERNAME:-}" ]; then
      echo "set SILO_USERNAME (or SILO_TOKEN) to sample signed-in endpoints, or pass --public" >&2
      exit 2
    fi
    if [ -z "${SILO_PASSWORD:-}" ]; then
      printf 'Silo password for %s: ' "$SILO_USERNAME" >&2
      IFS= read -rs SILO_PASSWORD; echo >&2
    fi
    export SILO_USERNAME SILO_PASSWORD
    echo "== Silo sign-in"
    silo auth_login /auth/login POST "$(helper json username SILO_USERNAME password SILO_PASSWORD)"
    unset SILO_PASSWORD
    ACCESS_TOKEN="$(helper get "$OUT/raw/silo/auth_login.json" access_token)"
    [ -n "$ACCESS_TOKEN" ] || { echo "sign-in failed, see $OUT/raw/silo/auth_login.json" >&2; exit 1; }
    SIGNED_IN=1
  fi

  silo account_me /account/me
  silo profiles /profiles
  read -r PROFILE_ID PIN_STATE <<EOF
$(helper profile "$OUT/raw/silo/profiles.json" "${SILO_PROFILE_ID:-}")
EOF
  [ -n "$PROFILE_ID" ] || { echo "no profile found" >&2; exit 1; }
  echo "   acting as profile $PROFILE_ID ($PIN_STATE)"
  if [ "$PIN_STATE" = pin ]; then
    if [ -z "${SILO_PROFILE_PIN:-}" ]; then
      printf 'PIN for profile %s: ' "$PROFILE_ID" >&2
      IFS= read -rs SILO_PROFILE_PIN; echo >&2
    fi
    export SILO_PROFILE_PIN
    silo profile_verify_pin "/profiles/$PROFILE_ID/verify-pin" POST "$(helper json pin SILO_PROFILE_PIN)"
    unset SILO_PROFILE_PIN
    PROFILE_TOKEN="$(helper get "$OUT/raw/silo/profile_verify_pin.json" profile_token)"
  fi

  echo "== Silo capabilities"
  silo playback_capabilities /playback/capabilities
  silo images_capabilities /images/capabilities
  silo search_capabilities /catalog/search/capabilities
  silo home_capabilities /home/capabilities
  silo events_capabilities /events/capabilities
  silo downloads_capabilities /capabilities/downloads
  silo ratings_capabilities /capabilities/ratings
  silo trailers_capabilities /capabilities/trailers
  silo themes_capabilities /catalog/themes/capabilities
  silo collections_capabilities /collections/capabilities
  silo device_login_capability /auth/device/capability
  silo diagnostics_capabilities /diagnostics/capabilities

  echo "== Silo browsing"
  silo user_libraries /user/libraries
  LIBRARY="$(helper first "$OUT/raw/silo/user_libraries.json" items id)"
  silo home_layout /home/layout
  silo home_sections /home/sections
  SECTION="$(helper first "$OUT/raw/silo/home_sections.json" items id)"
  if [ -n "$SECTION" ]; then silo home_section_items "/home/sections/$SECTION/items"; fi
  if [ -n "$LIBRARY" ]; then
    silo catalog_library_page1 "/catalog?library_id=$LIBRARY&limit=5"
    silo catalog_filters "/catalog/filters?library_id=$LIBRARY"
    silo catalog_letters /catalog/letters POST "{\"library_id\":\"$LIBRARY\"}"
  fi
  silo catalog_search "/catalog?q=the&limit=5"
  silo progress_in_progress "/progress?status=in_progress&limit=5"
  silo favorites "/favorites?limit=5"
  silo collections /collections

  echo "== Silo titles"
  silo catalog_item_movie "/catalog/items/$MOVIE"
  silo catalog_versions_movie "/catalog/items/$MOVIE/versions"
  silo watch_movie "/watch/$MOVIE"
  silo markers_movie "/markers/items/$MOVIE"
  silo similar_movie "/recommendations/similar/$MOVIE?limit=5"
  PERSON="$(helper first "$OUT/raw/silo/catalog_item_movie.json" cast person_id)"
  if [ -n "$PERSON" ]; then silo person "/catalog/people/$PERSON"; fi
  if [ -n "$MOVIE_MULTI" ]; then
    silo catalog_item_movie_multi "/catalog/items/$MOVIE_MULTI"
    silo catalog_versions_movie_multi "/catalog/items/$MOVIE_MULTI/versions"
  else
    echo "   (set SILO_MOVIE_MULTI to sample a movie with several versions)"
  fi
  silo catalog_item_series "/catalog/items/$SERIES"
  silo series_seasons "/catalog/series/$SERIES/seasons?include_artwork=true"
  SEASON="$(helper first "$OUT/raw/silo/series_seasons.json" items content_id)"
  if [ -n "$SEASON" ]; then silo season_episodes "/catalog/items/$SEASON/episodes"; fi
  silo catalog_item_episode "/catalog/items/$EPISODE"
  silo watch_episode "/watch/$EPISODE"
  silo markers_episode "/markers/items/$EPISODE"
  TRICK_FILE="$(helper first "$OUT/raw/silo/watch_episode.json" versions file_id trickplay_available)"
  if [ -n "$TRICK_FILE" ]; then
    silo watch_trickplay_episode "/watch/$EPISODE/trickplay?file_id=$TRICK_FILE"
  else
    echo "   (no version of $EPISODE has trickplay yet)"
  fi
fi

if [ -n "${EMBY_URL:-}" ]; then
  echo "== Emby ($EMBY_URL)"
  emby system_info_public /System/Info/Public
  if [ -n "${EMBY_TOKEN:-}" ] && [ -n "${EMBY_USER_ID:-}" ]; then
    U="$EMBY_USER_ID"
    F="Fields=Overview,Genres,People,Studios,ProviderIds,MediaSources,MediaStreams,Chapters,Path,Taglines,RemoteTrailers,ProductionLocations,PrimaryImageAspectRatio,DateCreated"
    emby user_views "/Users/$U/Views"
    if [ -n "${EMBY_MOVIE:-}" ]; then
      emby item_movie "/Users/$U/Items/$EMBY_MOVIE"
      emby playback_info_movie "/Items/$EMBY_MOVIE/PlaybackInfo?UserId=$U"
    fi
    if [ -n "${EMBY_MOVIE_MULTI:-}" ]; then
      emby item_movie_multi "/Users/$U/Items/$EMBY_MOVIE_MULTI"
      emby playback_info_movie_multi "/Items/$EMBY_MOVIE_MULTI/PlaybackInfo?UserId=$U"
    fi
    if [ -n "${EMBY_SERIES:-}" ]; then
      emby item_series "/Users/$U/Items/$EMBY_SERIES"
      emby series_seasons "/Shows/$EMBY_SERIES/Seasons?UserId=$U&$F"
      ESEASON="$(helper first "$OUT/raw/emby/series_seasons.json" Items Id)"
      if [ -n "$ESEASON" ]; then emby season_episodes "/Shows/$EMBY_SERIES/Episodes?UserId=$U&SeasonId=$ESEASON&$F"; fi
    fi
    if [ -n "${EMBY_EPISODE:-}" ]; then emby item_episode "/Users/$U/Items/$EMBY_EPISODE"; fi
  else
    echo "   (set EMBY_TOKEN and EMBY_USER_ID for the signed-in Emby samples)"
  fi
fi

echo "== Scrubbing"
for side in silo emby; do
  for f in "$OUT/raw/$side"/*.json; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in openapi.json) continue ;; esac
    helper scrub "$f" "$OUT/scrubbed/$side/$(basename "$f")" "$HOST_SILO" "$HOST_EMBY"
  done
done
echo "   raw:      $OUT/raw (keep local)"
echo "   scrubbed: $OUT/scrubbed (review, then copy what you need into packages/server_silo/test/fixtures/)"
echo "   summary:  $SUMMARY"
if [ "$FAILED" -gt 0 ]; then
  echo "$FAILED request(s) did not return 2xx; see the summary" >&2
  exit 1
fi

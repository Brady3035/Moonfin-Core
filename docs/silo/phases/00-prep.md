# Phase 0: Preparation

[← Roadmap](../ROADMAP.md)

Pin the Silo contract we build against and set up the tooling. Nothing in the app changes.

**Phase done when:** The OpenAPI snapshot and fixtures match the server you run, and the probe script refreshes them.

---

<a id="step-0-1"></a>
## 0.1 Add the Silo support docs

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `9c03b8d` | — |

**Goal.** Commit this roadmap, the phase files, the decisions log and the Oct 8 design reference so every later commit can fill in its own section.

**Where in Moonfin**

- `docs/silo/**`

### How it works

Docs only. `docs/silo/README.md` explains the approach and workflow, `ROADMAP.md` lists every step, `phases/` holds one file per phase with a section per step, `DECISIONS.md` logs design choices, and `reference/design-2026-10-08.md` keeps the first-pass design notes (mapping tables, playback protocol, live-server findings). The phase files and roadmap were generated from one structured step list so every step has the same layout; from here on they are edited by hand as steps are built.

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Open `docs/silo/README.md` on GitHub and check the links between the files work.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | GitHub | — | Pass | Committed by Brady after review |

---

<a id="step-0-2"></a>
## 0.2 Pin the Silo v2 contract for build 4b2e921c

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `81085c4` | 0.1 |

**Goal.** Replace the `4e371f4c` OpenAPI snapshot with the one from the server you run, and record the version, `api_major` and `contract_digest`.

**Silo v2 endpoints**

- `GET /api/v2/system/info`
- `GET /api/v2/openapi.json`

**Where in Moonfin**

- `packages/server_silo/test/fixtures/openapi-4b2e921c.json.gz`
- `packages/server_silo/test/fixtures/README.md`

**Earlier work to port:** stash `Add_silo` fixtures README (rewritten for the new build; the old `4e371f4c` snapshot is not carried over)

### How it works

The Silo contract Moonfin builds against is now the exact OpenAPI document served by the test server, not the `4e371f4c` copy from the first pass.

- `packages/server_silo/test/fixtures/openapi-4b2e921c.json.gz` is `GET /api/v2/openapi.json` from build `4b2e921c+dirty` (`api_major` 2), gzipped with `gzip -9 -n` so the archive is byte-stable.
- Silo's `contract_digest` is the SHA-256 of that document (the server also sends it as the `ETag`). The uncompressed snapshot hashes to `12ea11dd…960a`, the same value `/system/info` reports, so the file provably matches the server.
- `packages/server_silo/test/fixtures/README.md` records the build, digest, date and size, and explains how to verify and refresh it. The `server_silo` package itself doesn't exist yet on this branch (step 1.4, the package skeleton); the fixtures folder is created first so the contract is pinned before any code is written against it.
- The server id from `/system/identity` is unchanged (`7b72fbd5…`), so servers saved during the first pass stay valid.

**What changed since `4e371f4c`** (822 → 849 viewer-facing operations, 1,122 → 1,170 schemas, nothing removed). Compared over the 424 schemas reachable from endpoints in the plan:

| Change | Effect on the plan |
|---|---|
| Movie and series detail now carry `thumb_url`, `banner_url`, `clearart_url`, `disc_url` and `backdrop_urls` (gated by `images/capabilities.extended_item_artwork`) | Silo **does** have Thumb and Banner art now. Steps 5.4 and 6.1 updated: use them when present, fall back to the backdrop otherwise; `backdrop_urls` fills `BackdropImageTags` with more than one entry. |
| `*_is_episode_still` flags on posters/backdrops | Lets the mapper avoid using an episode still as a series poster (5.4). |
| `POST /catalog/letters` + `CatalogSearchCapabilities.letter_index` | Native alphabet jump, already planned as step 6.11; use `runs`, not `letters`, to compute positions. |
| `GET /home/capabilities`, `HomeLayout` | Step 8.7 checks it before rendering server-curated sections. |
| Profile tokens are now also invalidated when the profile's PIN changes | Steps 18.4/3.4: a rejected `X-Profile-Token` re-prompts for the PIN instead of signing out. |
| Device-login codes may be 6 digits for a Jellyfin Quick Connect request; new `jellyfin_quick_connect` capability and `approve-handoff` | Step 14.1/14.2: don't assume the 8-digit `4821-7730` format. |
| `MarkerOccurrence` gains `thumbnail_url` | Optional preview image on the skip button (11.1). |
| Personal collections drop `allowed_profile_ids`, add `contains`, `sync_cadence`, `poster_is_collage` | Step 9.5: `contains_item` can show "already in collection". |
| New `POST /downloads/{id}/prepare`, `DownloadCapability.prepare_again` | Step 15.3. |

### Testing

**Automated tests**

- None (no code yet). The digest check below is the test.

**Manual test plan**

- In the repo: `gunzip -c packages/server_silo/test/fixtures/openapi-4b2e921c.json.gz | shasum -a 256`
- `curl -s https://silo.snowystreams.com/api/v2/system/info` → `contract_digest` is the same value, and it matches the table in the fixtures README.
- `git status` shows only the two new files under `packages/server_silo/test/fixtures/` (plus these docs).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Claude (workspace on your Mac) | 4b2e921c+dirty | Pass | Digest of the snapshot = served `contract_digest` = `ETag` |
| 2026-10-13 | macOS | 4b2e921c+dirty | Pass | Brady verified the digest and committed |

---

<a id="step-0-3"></a>
## 0.3 Probe script for refreshing fixtures

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `e845ac2` | 0.2 |

**Goal.** A script that signs in, lists profiles and saves scrubbed responses for each endpoint the plan uses, so fixtures can be refreshed after every Silo upgrade.

**Where in Moonfin**

- `scripts/silo_probe.sh`

**Earlier work to port:** silo-1 `scripts/silo_probe.sh` (extended: password sign-in with sign-out, profile PIN, contract re-pinning, Emby target fetches, automatic scrubbing)

### How it works

`scripts/silo_probe.sh` is a developer tool, not part of the app. It collects the real server responses that the Silo mappers and tests are written against, and re-pins the API contract after a Silo upgrade. It needs only bash 3.2 (macOS's default), curl and python3.

**What it does, in order**

1. Reads the four public endpoints (`/system/info`, `/system/identity`, `/system/setup`, `/theme/branding`) and prints the build, `api_major` and `contract_digest`.
2. With `--contract`: downloads `/openapi.json`, checks its SHA-256 equals `contract_digest`, and only then writes `packages/server_silo/test/fixtures/openapi-<build>.json.gz` (`gzip -9 -n`, so unchanged content gives an identical file) and removes the previous build's snapshot. It prints the values for the fixtures README table.
3. Signs in (unless `--public`): `SILO_USERNAME` with the password prompted for (never put on the command line; the request body goes to curl on stdin so it never appears in `ps`), or an existing `SILO_TOKEN`. A session it opened is signed out on exit, even after an error (`trap … EXIT`).
4. Picks a profile (`SILO_PROFILE_ID`, else the primary one) and, if it has a PIN, checks it via `verify-pin` and sends `X-Profile-Token` from then on, which is the same header flow the app will use.
5. Samples the endpoints the roadmap uses: capabilities (playback, images, search, home, events, downloads, ratings, trailers, themes, collections, device login, diagnostics), libraries, home layout/sections, a library page, filters, letters, search, progress, favorites, collections, then a movie (detail, versions, `/watch`, markers, similar, one cast member), an optional multi-version movie, a series → first season → its episodes, and an episode's `/watch`, markers and trickplay (the `file_id` is taken from the first version with `trickplay_available`).
6. Optionally fetches the same titles from Emby (`EMBY_URL`, `EMBY_TOKEN`, `EMBY_USER_ID` and item ids): views, items, `PlaybackInfo`, seasons and episodes. These are the target shape the mappers must produce.
7. Writes everything to `build/silo-probe/<time>/raw/` (gitignored, keep local) and a scrubbed copy to `.../scrubbed/`, plus `summary.txt` with each request's status. It exits 1 if any request didn't return 2xx.

**Scrubbing rules** (an embedded Python helper, so the shell stays bash 3.2-safe):

| What | Becomes |
|---|---|
| Values under `access_token`, `refresh_token`, `profile_token`, `device_code`, `password`, `token`, `secret`, `api_key`, `ticket` | `SCRUBBED` |
| URL query values `sig`, `st`, `exp`, `token`, `api_key`, S3/CloudFront signature params | `SCRUBBED` (the path is kept, because image tags are derived from it) |
| `email` | `user@example.invalid` |
| IP fields (`ip`, `remote_ip`, `last_ip`, …) | `203.0.113.1` (documentation range) |
| `path`, `*_path`, `*_paths` (except `/api/...` paths) | file or folder name only |
| Profile `name` and account `username` in `profiles`, `account_me`, `auth_login` | `Profile 1`, `Profile 2`…, `user` (household members' names stay private) |
| The Silo and Emby hostnames anywhere in a string | `silo.example` / `emby.example` |

Cast and crew names, titles and external artwork URLs (TMDB, TVDB) are kept: they are public and the mapper tests need them. A response that isn't JSON (an error page) is left out of the scrubbed set.

### Testing

**Automated tests**

- `bash -n` and ShellCheck: clean.
- Scrubber run on a hand-made response containing every rule above: all secrets, signatures, emails, IPs, paths and profile names replaced; cast names and TMDB URLs kept; a non-JSON body skipped.

**Manual test plan**

- `scripts/silo_probe.sh --help` prints the usage.
- `SILO_URL=https://silo.snowystreams.com scripts/silo_probe.sh --public --contract`: four public endpoints 200, digest verified, and `git status` shows **no change** to `openapi-4b2e921c.json.gz` (same content gives the same file).
- `SILO_URL=https://silo.snowystreams.com SILO_USERNAME=<you> scripts/silo_probe.sh`: prompts for the password (not echoed), lists every endpoint with its status, prints "signed out of Silo (204)" at the end. Check the session is gone in Silo web (account → sessions).
- Try it with a PIN profile: `SILO_PROFILE_ID=<id>`; it asks for the PIN.
- Open a few files in `build/silo-probe/<time>/scrubbed/silo/`: no tokens, `sig=`/`st=` values, your hostname, email, full file paths or family names.
- Run it with macOS's own bash to prove 3.2 compatibility: `/bin/bash scripts/silo_probe.sh --public`.
- Optional: add `EMBY_URL`, `EMBY_TOKEN`, `EMBY_USER_ID` and `EMBY_MOVIE` and check the Emby files appear.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Claude (workspace on your Mac, bash 5) | 4b2e921c+dirty | Pass | `--public --contract`: all 200, re-pinned file byte-identical to the committed one; no-credentials run stops with a clear message; bad token stops at profiles with "no profile found"; scrubbed files contain no hostname. Signed-in run not done (needs your password). |
| 2026-10-13 | macOS (`/bin/bash` 3.2) | 4b2e921c+dirty | Pass with 2 findings | Signed-in run: 35 of 40 requests 200, signed out at the end; scrubbed files clean on real data. **Finding 1:** `--contract` rewrote the snapshot with different bytes (same content): BSD gzip on macOS compresses differently from GNU gzip. **Finding 2:** the Young Justice defaults 404: Silo now ids that show by IMDb (`episode-imdb-…`), not TVDB. Both fixed in step 0.4. |

---

<a id="step-0-4"></a>
## 0.4 Capture Silo and Emby fixture pairs

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `1ee2d09` | 0.3 |

**Goal.** Save the same titles from both servers (a movie, a two-version movie, a series → season → episode, an episode with markers and trickplay, a PIN profile, the library list). The Emby side is the target shape the mappers must produce.

**Silo v2 endpoints**

- `/catalog/items/{id}`
- `/catalog/items/{id}/versions`
- `/catalog/series/{id}/seasons`
- `/catalog/items/{id}/episodes`
- `/watch/{id}`
- `/watch/{id}/trickplay`
- `/markers/items/{id}`
- `/profiles`
- `/user/libraries`
- `/home/layout`

**Where in Moonfin**

- `packages/server_silo/test/fixtures/silo/*.json`
- `packages/server_silo/test/fixtures/emby/*.json`

**Earlier work to port:** stash `Add_silo` fixtures (re-capture against 4b2e921c)

### How it works

**What was captured.** 44 Silo and 11 Emby responses, written to `packages/server_silo/test/fixtures/silo/` and `.../emby/` (file names are the probe script's, so a refresh is a copy over the top). Four titles were sampled on both servers; the fixtures README lists them with both ids. Long lists were trimmed (home section items, season episodes, filter studios/countries/languages) while the total counts were left intact, giving about 540 KB in all.

**Privacy check on the real output** (before copying): no hostname, no unscrubbed `sig`/`st`/`exp`/`token`/`api_key` values, no token or password values, no email except `user@example.invalid`, no absolute file paths, no IPs, profile name "Profile 1", username "user". Emby library names (Movies, TV shows, Audio books) and cast names are kept.

**Facts the mapper steps will need** (checked across the pairs):

- The Salt Path has 2 versions on Silo (`4602` 1080p, `4603` 2160p) but 3 media sources on Emby (one named "4kversion"). Version-count golden tests must compare per file, not by count.
- xXx has no `thumb_url`/`banner_url` on Silo, so the backdrop fallback in 5.4 is exercised by real data.
- Silo episodes carry no `year`; Emby gives `ProductionYear` 2010. The mapper derives it from `air_date`.
- Emby still numbers streams audio 0, video 1, subtitles 2–3 for xXx, and Silo's `/watch` audio tracks still carry no container index, which confirms the three-way track map in 5.8.
- Home has six sections (continue watching, hidden gems, trending, seasonal, recently added ×2) with their items embedded, and **no `next_up` section** even with a TV library.
- Season ids follow the provider too: `season-imdb-tt1641384-1`.

**Script changes made while capturing** (found testing 0.3 on the Mac):

- **Stable snapshot on every OS.** `--contract` now keeps the existing `openapi-<build>.json.gz` when its uncompressed content already matches `contract_digest`, and writes new snapshots with Python's `gzip.compress(…, mtime=0)` instead of the `gzip` command. macOS's BSD gzip and Linux's GNU gzip produce different bytes for the same input, which showed up as a spurious change in `git status`.
- **Silo ids are derived from the Emby item, not hard-coded.** Silo builds content ids from whichever provider it matched (`movie-imdb-tt0295701`, `episode-imdb-<series imdb>-<season>-<episode>`), and the TV library switched from TVDB to IMDb ids between Oct 7 and Oct 13, so the old defaults 404'd. When `SILO_MOVIE`/`SILO_MOVIE_MULTI`/`SILO_SERIES`/`SILO_EPISODE` are unset, the script reads the Emby item's `ProviderIds`, builds the candidates in order IMDb → TMDB → TVDB and uses the first one Silo's catalog answers. That also guarantees the Silo and Emby samples are the same title.
- **Less Emby setup.** `EMBY_SERIES` defaults to the episode's `SeriesId`; `EMBY_USER_ID` defaults to `EMBY_USERNAME`'s id or the first admin (the user list is used for that and not saved). An episode `PlaybackInfo` and the multi-version movie's `/watch` are now sampled too.
- **Home section items.** `/home/sections` lists sections under `sections`, not `items`, so the per-section request was skipped; fixed. (The sections embed their items, so no fixture was lost.)

**Finding for the app design:** Silo content ids are not permanent; they change when a library is rematched to a different provider. Anything Moonfin persists by Silo id (offline downloads, cached rows, deep links) has to cope with an id disappearing. Silo exposes `/api/v2/libraries/stale-ids` for this; it is noted for phases 6 and 15.

### Testing

**Automated tests**

- None (data only). The fixtures are used by the mapper tests from step 5.1 on.

**Manual test plan**

- The Salt Path two-version sample is included (missing from the Oct 7 capture).
- Skim a few files in `packages/server_silo/test/fixtures/silo/` and `emby/` for anything private I missed (names of household members, your hostname, paths).
- `git status` shows only `packages/server_silo/test/fixtures/**`, `scripts/silo_probe.sh` and `docs/silo/**`.
- Optional: re-run the capture command once more and check the `home_section_items` line now appears in the summary.
- Compare with Emby: `/Items/{id}`, `/Shows/{id}/Seasons`, `/Shows/{id}/Episodes`, `/Items/{id}/PlaybackInfo` for the same titles.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | macOS (Brady's run) + Claude review | Silo 4b2e921c+dirty, Emby 4.10.1.0 | Pass | 59 requests, all 200; all four titles resolved on Silo from the Emby ids; privacy check clean. Gaps: no PIN profile, no trickplay item. |
| | | | | |

---

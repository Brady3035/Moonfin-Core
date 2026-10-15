# Server fixtures for Silo support

Reference data that the `server_silo` and `playback_silo` code and tests are
written against. See `docs/silo/` for the plan these belong to.

## Pinned Silo contract

| | |
|---|---|
| File | `openapi-4b2e921c.json.gz` (gzipped `GET /api/v2/openapi.json`, OpenAPI 3.1) |
| Server build | `4b2e921c+dirty` (from `GET /api/v2/system/info` → `server_version`) |
| `api_major` | `2` |
| `contract_digest` | `12ea11dd8223e9426ab5376aad1116c150a674b432989b3cb4e5dbc9458b960a` |
| Captured | 2026-10-13 from the maintainer's test server |
| Size | 697 paths, 1,170 component schemas |

`contract_digest` is the SHA-256 of the uncompressed OpenAPI document (also
served as its `ETag`), so this check proves the file matches the server:

```sh
gunzip -c openapi-4b2e921c.json.gz | shasum -a 256
curl -s https://<silo-host>/api/v2/system/info   # compare contract_digest
```

`server_version` is a git short hash, not a semantic version (`+dirty` means
the server was built from a tree with local changes). Never parse it; Moonfin
checks `api_major` and logs the digest.

## Refreshing after a Silo upgrade

```sh
SILO_URL=https://<silo-host> scripts/silo_probe.sh --public --contract
```

This downloads the document, checks it against the server's `contract_digest`,
writes `openapi-<build>.json.gz` here with `gzip -9 -n` (so unchanged content
gives an identical file), removes the previous snapshot and prints the values
for the table above. Run it without `--public` (with `SILO_USERNAME`) to sample
the signed-in endpoints too; see `scripts/silo_probe.sh --help`.

## Samples

Captured 2026-10-13 with `scripts/silo_probe.sh` from the test servers (Silo
`4b2e921c+dirty`, Emby `4.10.1.0`), then trimmed. File names are the probe
script's, so a refresh is a copy over the top.

Each title was sampled on both servers; the Silo ids were worked out from the
Emby items' provider ids, so every pair is the same title:

| Title | Silo content id | Emby item id | Why it's here |
|---|---|---|---|
| xXx (2002) | `movie-imdb-tt0295701` | `633614` | Plain movie: detail, versions, `/watch`, markers (none), similar, one cast member. No thumb/banner art. |
| The Salt Path (2025) | `movie-imdb-tt27766440` | `691242` | Two versions on Silo (1080p x264, 2160p HEVC); Emby lists three sources. |
| Young Justice | `series-imdb-tt1641384` | `648654` | Series → seasons → season 1 episodes. |
| Young Justice S01E01 | `episode-imdb-tt1641384-1-1` | `659237` | Episode with an intro marker. No trickplay yet. |

`silo/` also holds the public system endpoints, sign-in, account and profile
(one profile, no PIN), every capability document the roadmap reads, user
libraries, home layout and sections, a library page, filters, letters, search,
progress, favorites and collections (empty). `emby/` holds the views, items,
`PlaybackInfo`, seasons and episodes for the same titles: the shape the mappers
must produce.

**Trimmed** to keep the files small (counts such as `total_count` and
`TotalRecordCount` still give the original size):
`silo/home_sections.json` items per section → 3; `silo/season_episodes.json`
and `emby/season_episodes.json` → first 3 episodes; `silo/catalog_filters.json`
studios → 20, countries and original languages → 10.

**Scrubbed** by the probe script (see its header): tokens, URL signatures, email,
IPs, file paths cut to the file name, profile names and the username replaced,
hosts replaced with `silo.example` / `emby.example`.

**Not captured yet:** a PIN-locked profile (needed by step 3.6). Re-run the
script with `SILO_PROFILE_ID` when that step starts.

`silo/watch_trickplay_episode.json` was built by hand from the
`WatchTrickplay` schema at step 5.11, when no file had seek previews, and
replaced by a real capture of Young Justice S01E01 on 2026-10-15 (Silo
`bd9d59ea`): 300 × 168 thumbnails, 10 × 8 per sheet, 136 in two sheets, sheet
URLs under `/api/v2/artwork/trickplay/`.

`silo/catalog_search.json` was recaptured on 2026-10-15 (Silo `bd9d59ea`):
the 2026-10-13 capture searched for "the", a stop word for Silo's PostgreSQL
search, and held no items. It is now the first 5 of 118 results of a
`type=video_with_episodes` search for "justice" (`SILO_SEARCH`, the probe's
default): one film and four episodes named "Justice". The expected lists in
`silo_items_api_search_test.dart` follow this file.

`silo/people_search.json` is the people search the probe makes for the first
word of the sampled cast member's name ("Vin", `media_scope=video_with_episodes`,
5 people), captured 2026-10-15 (Silo `bd9d59ea`). It shows Silo's ranking:
word-start matches by name, so Vincents come before Vin Diesel.

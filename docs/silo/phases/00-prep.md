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
| ◐ Ready for testing | — | 0.1 |

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
- `packages/server_silo/test/fixtures/README.md` records the build, digest, date and size, and explains how to verify and refresh it. The `server_silo` package itself doesn't exist yet on this branch (step 1.4); the fixtures folder is created first so the contract is pinned before any code is written against it.
- The server id from `/system/identity` is unchanged (`7b72fbd5…`), so servers saved during the first pass stay valid.

**What changed since `4e371f4c`** (822 → 849 viewer-facing operations, 1,122 → 1,170 schemas, nothing removed). Compared over the 424 schemas reachable from endpoints in the plan:

| Change | Effect on the plan |
|---|---|
| Movie and series detail now carry `thumb_url`, `banner_url`, `clearart_url`, `disc_url` and `backdrop_urls` (gated by `images/capabilities.extended_item_artwork`) | Silo **does** have Thumb and Banner art now. Steps 5.4 and 6.1 updated: use them when present, fall back to the backdrop otherwise; `backdrop_urls` fills `BackdropImageTags` with more than one entry. |
| `*_is_episode_still` flags on posters/backdrops | Lets the mapper avoid using an episode still as a series poster (5.4). |
| `POST /catalog/letters` + `CatalogSearchCapabilities.letter_index` | Native alphabet jump, already planned as step 6.11; use `runs`, not `letters`, to compute positions. |
| `GET /home/capabilities`, `HomeLayout` | Step 8.7 checks it before rendering server-curated sections. |
| Profile tokens are now also invalidated when the profile's PIN changes | Steps 3.6/3.9: a rejected `X-Profile-Token` re-prompts for the PIN instead of signing out. |
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
| | | | | |

---

<a id="step-0-3"></a>
## 0.3 Probe script for refreshing fixtures

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** A script that signs in, lists profiles and saves scrubbed responses for each endpoint the plan uses, so fixtures can be refreshed after every Silo upgrade.

**Where in Moonfin**

- `scripts/silo_probe.sh`

**Earlier work to port:** silo-1 `scripts/silo_probe.sh`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Run it on the Mac against your server. Tokens, `sig`/`st` query values and file paths come out scrubbed.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-0-4"></a>
## 0.4 Capture Silo and Emby fixture pairs

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

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

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- The Salt Path two-version sample is included (missing from the Oct 7 capture).
- Compare with Emby: `/Items/{id}`, `/Shows/{id}/Seasons`, `/Shows/{id}/Episodes`, `/Items/{id}/PlaybackInfo` for the same titles.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

# Phase 15: Downloads and offline

[← Roadmap](../ROADMAP.md)

Read Silo's downloads design before step 15.3; it is a full server-managed download system.

**Phase done when:** Download a movie and an episode, play them offline, and the progress syncs back.

---

<a id="step-15-1"></a>
## 15.1 Download permission and capability

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Goal.** Show download actions only when the account may download.

**Silo v2 endpoints**

- `GET /capabilities/downloads`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_downloads_api.dart` (new): `SiloDownloadsApi` (the capability, read at most once a minute), `SiloDownloadCapability`, `SiloDownloadQualityOption`; `SiloMediaServerClient.downloadsApi`
- `packages/server_silo/lib/src/api/silo_users_api.dart`: `getCurrentUser` folds the capability into the policy's `EnableContentDownloading`

**Also in this commit: the phase 14 bookkeeping.** 14.2's fix hash `8cc18adc0` and Brady's macOS Pass row after the fix; 14.2 ticked in the roadmap. 15.7 moved to the roadmap's new [Later](../ROADMAP.md#later) list (Brady, 2026-10-18), with offline trickplay (left out of 15.6).

### How it works

Moonfin offers a download only when `userCanDownload()` says so: a platform that keeps downloads, the TV setting, and the signed-in user's `canDownload`, which comes from the server's user policy (`EnableContentDownloading`). On Silo that flag was the account's `download_allowed` (2.6). The account flag isn't the whole answer: Silo's guide says to hide download actions unless the downloads capability says they are `enabled` and `allowed`. A server can switch downloads off as a whole, and a demo server refuses them to every non-admin while their accounts still say `download_allowed: true`. An empty `quality_presets` list means the same ("downloads unavailable for this account").

So `SiloUsersApi.getCurrentUser` now reads `GET /capabilities/downloads` next to the account and the profiles (it needs `X-Profile-Id`, which the client sends), and switches `EnableContentDownloading` off when the capability doesn't permit downloads: not `available`, not `enabled`, not `allowed`, or no quality. It only ever switches the flag off; an account that may not download stays so. A capability that can't be read (an older server, a network blip) leaves the account's flag and is logged.

`getCurrentUser` runs at sign-in, when a stored login is restored, and when Silo says the login's access changed (13.4), and the app stores `canDownload` from it each time, so every download button follows a change made on the server at the next of these. The capability is read afresh at each of them; `SiloDownloadsApi.capability()` otherwise keeps an answer for a minute (concurrent callers share one read), for the quality choice in 15.3.

No app code changes: every download entry point already asks `userCanDownload()`.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_downloads_api_test.dart` (new, 13 tests): the captured capability (`silo/downloads_capabilities.json`) fits the contract and reads back, sent as the profile and the device; quality options keep their bitrate and height; switched off, refused for this login, not configured and no quality are not permitted; read once a minute, concurrent reads share one, invalidation reads again; a failed read isn't kept. The user's permission: on when both say so; off when the server has downloads off; never on when the account may not; an unreadable capability keeps the account flag; each `getCurrentUser` asks again.
- `packages/server_silo/test/silo_users_api_test.dart`: the profile check now lists the capability read too. `server_silo` 633/633; `test/auth` 138/138 (their fake Silo has no capability route, so the account flag stands).

**Manual test plan**

On the Mac, signed in to Silo:

- a. A film's detail page offers Download (as before, since your account may download and the server allows it). The network log shows `GET …/api/v2/capabilities/downloads` at sign-in or start, next to `GET …/account/me`.
- b. In Silo's admin, switch downloads off for the server (or turn off your account's download permission), then restart Moonfin: no Download action on the detail page, the season page or the context menu. Switch it back on and restart: it's back.
- c. Regression on Emby: Download still shows for an account that may download.
- d. Full suite (`flutter test` at the repo root).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | downloads API 13/13, `server_silo` 633/633, `test/auth` 138/138; analyzer: no issues in the changed files |
| | | | | |

---

<a id="step-15-2"></a>
## 15.2 Original-file downloads

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Download the original file through Silo's download registry (managed downloads). *Changed from signed direct-download links (Brady, 2026-10-18): Silo's guide says apps use managed downloads for every quality and keeps direct links for browsers.*

**Silo v2 endpoints**

- `GET /downloads` (the device's entries)
- `POST /downloads` (register a download)
- `GET /downloads/{id}/file`
- `PATCH /downloads/{id}` (completed)
- `DELETE /downloads/{id}`
- `POST /direct-download/links`, `GET /direct-download` (the web build only)

**Where in Moonfin**

- `packages/server_core/lib/src/api/server_downloads_api.dart` (new): `ServerDownloadsApi`, `ServerDownloadsProvider`, `ServerDownloadRequest`, `ServerDownloadTicket`, `ServerDownloadRefused`
- `packages/server_silo/lib/src/api/silo_downloads_api.dart`: `SiloDownloadsApi` implements it (`prepareDownload`, `browserDownloadUrl`, `downloadFinished`, `downloadsRemoved`, `existingEntry`), `SiloDownloadEntry`; `SiloMediaServerClient` is a `ServerDownloadsProvider`
- `lib/data/services/download_service.dart`: asks the server for the file when its client provides `ServerDownloadsApi`; tells it when a file is finished or deleted

### How it works

**Silo's model.** Silo keeps a registry of the files each device holds (`docs/downloads-api.md`, "managed device entries"). A request carrying `X-Silo-Device-Id`, which Moonfin's Silo client sends on every request, registers an entry for that device and profile. The entry names the file, and its `GET /downloads/{id}/file` serves the bytes (with ranges, so a transfer can resume). The device reports when it has the whole file, and deletes the entry when it deletes its copy. The registry is what Silo's manifest (15.4), subtitles (15.6) and offline progress (15.5) build on, and what lets an admin see or revoke a device's downloads.

**The seam.** Moonfin's download service (upstream code) builds Jellyfin and Emby URLs (`/Items/{id}/Download`, `/Videos/{id}/stream`) and sends a `MediaBrowser` token. A new optional `server_core` interface, `ServerDownloadsApi`, lets a server hand over the file instead. Silo's client provides it (`ServerDownloadsProvider`). The service unwraps the app's connectivity wrapper to find it, and then:

1. **before the transfer**, after the storage checks, asks `prepareDownload` (the item, its series for an episode, the version, the quality). The answer is a ticket: the file's URL, the headers it needs, its size;
2. fetches the ticket's URL with the ticket's headers, through the same engines as any download (native background engine or the in-process one). The Jellyfin fallback URLs are skipped;
3. **when the file is complete**, calls `downloadFinished` (best effort);
4. **when downloads are deleted** (a movie, an episode, or a season or series with each of its downloaded episodes), and when a running download is cancelled, calls `downloadsRemoved` with their item ids (best effort: the local files go anyway).

A refusal (`ServerDownloadRefused`) becomes the download's error, with the server's words. Jellyfin and Emby clients don't provide the interface; their downloads are unchanged.

**Silo's side (`SiloDownloadsApi`).**

- **Registering.** `POST /downloads` with `content_id` (the movie, or an episode's series), `episode_id` (an episode), `media_file_id` (the version; Silo's file ids are Moonfin's media source ids) and `quality: original`. No `caps` are sent, so Silo hands over the source file as it is, as Moonfin's Jellyfin original downloads do. With a device header Silo also needs `expected_revision`: `0` when the device has no entry for the item, or the existing entry's revision with its id (`expected_download_id`), which reuses, revives or replaces it. So the device's entries are read first (`GET /downloads`, 100 at a time, at most 10 pages, newest first) and matched by item: this is the reconciliation Silo's guide asks for before creating. Creation is `non_retryable` and is sent once.
- **The answer.** A servable entry gives the ticket: `ready`, or `downloading` or `completed` (the state a device reports on a ready file; registering an item this device downloaded before can hand back its earlier entry). The ticket is `…/api/v2/downloads/{id}/file` with the client's headers (bearer token, `X-Profile-Id`, `X-Silo-Device-Id`) and `Accept: application/octet-stream`. Refusals: downloads off for this profile (from 15.1's capability, checked first, nothing sent); `skipped` with `no_file` or `quality_unavailable`; `403`/`404`/`422` with Silo's text (a refused policy, an original above the account's download quality ceiling). An entry Silo is still preparing (it does that for converted files, 15.3) isn't handed out yet. Other failures (network, `5xx`, a `409` from a stale revision) reach the service as errors; the person retries.
- **Finished.** `PATCH /downloads/{id}` with `status: completed`, the time, and the entry's revision.
- **Deleted.** The device's entries are read and those for the deleted items get `DELETE /downloads/{id}`; one already gone (`404`) is fine.
- **Web.** A browser download carries no headers, so the web build asks for a short-lived link instead (`POST /direct-download/links` with the file id): the link holds its own credential for five minutes. Original files only; it is what Silo's guide says browsers use.

**Known limits.**

- The transfer's headers are fixed when it starts, and Silo checks the token when a request arrives, so a long transfer runs on. But a transfer that resumes after the access token expired (an hour; for example the native engine retrying after a dropped network) is refused with `401` and fails; Retry starts it again with a fresh token.
- A download that finishes while Moonfin isn't running (the native engine in the background, finished on the next start) isn't reported completed to Silo; its entry stays `ready`. Nothing depends on it in Moonfin.
- Artwork and subtitles of a Silo download still go through the Jellyfin paths and mostly fail (best effort, the download itself is fine): 15.4 and 15.6.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_downloads_api_test.dart` (15 new, 28/28): the fixture (`silo/download_created.json`, hand-built) and every request body fit the contract (`DownloadCreated`, `DownloadCreateBody`, `DownloadStatusBody`, `DirectDownloadLinkBody`); a new download is registered after reading the device's entries, as the profile and device, and its ticket has the file URL, headers, revision and size; an episode is its series' content with the episode named; an existing entry is named with its revision and id; the entry scan follows the cursor; downloads switched off, no file, and a refused policy are refused with their reasons; a preparing file isn't handed out; an earlier, completed entry is served again; a server error is sent once; finished reports `completed`; deleted items delete their entries (`404` fine), others are kept; a browser gets a link for the original, and none without a file id or for a converted download.
- `test/offline/server_download_test.dart` (new, 5 tests): the download service fetches the server's file with its headers (no `X-Emby-Token`) and reports it finished; an episode names its series; a refusal is the download's error and nothing is fetched; deleting tells the server; deleting a season names each downloaded episode.

**Manual test plan**

On the Mac, signed in to Silo (the network log is in Moonfin's logs):

- a. Download a film at Original from its detail page. The log shows `GET …/api/v2/downloads?limit=100`, `POST …/api/v2/downloads` (`202`), then `GET …/api/v2/downloads/<id>/file`, and when it's done `PATCH …/api/v2/downloads/<id>` (`200`). The download completes; its size matches the file on the server.
- b. Turn the network off (or stop Silo) and play the downloaded film from Downloads: it plays from the file.
- c. Download an episode, then a whole season ("Download all"): each episode registers and completes.
- d. Delete the film from Downloads: `DELETE …/api/v2/downloads/<id>` (`204`). Download it again: it registers as new (`expected_revision` 0). Delete the season: one `DELETE` per episode.
- e. Start a download and cancel it while it runs: the entry is deleted on Silo too.
- f. In Silo's web admin, if it lists device downloads: Moonfin's entries appear as this device's, completed.
- g. Regression on Emby: an Original download still completes, from `/Items/<id>/Download`.
- h. Full suite (`flutter test` at the repo root).
- i. Deferred to 17.5 with the web build (12.3): on Moonfin for the web, Download opens the browser's download of the original through a `…/direct-download?dl=…` link.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | downloads API 28/28, server download 5/5, `server_silo` 648/648, `server_core` 100/100, `test/offline` + `test/data/services` 614/614; analyzer: no new issues in the changed files |
| 2026-10-18 | Web | — | Deferred | check i in 17.5 |
| | | | | |

---

<a id="step-15-3"></a>
## 15.3 Transcoded downloads

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Server download jobs: create, prepare, manifest, file, subtitles, artwork, status.

**Silo v2 endpoints**

- `POST /downloads`
- `POST /downloads/{id}/prepare`
- `GET /downloads/{id}/manifest`
- `GET /downloads/{id}/file`

**Where in Moonfin**

- `download_service.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-15-4"></a>
## 15.4 Offline metadata and artwork

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Store the translated item and the image bytes; offline images must not depend on the registry.

**Where in Moonfin**

- `lib/data/offline/*`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-15-5"></a>
## 15.5 Offline progress sync

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Replay queued progress through bulk progress sync.

**Silo v2 endpoints**

- `POST /sync/progress`

**Where in Moonfin**

- `lib/data/services/offline_playback_tracker.dart`
- `sync_service.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-15-6"></a>
## 15.6 Offline subtitles and trickplay

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Download sheets and sidecars (signed URLs expire).

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-15-7"></a>
## 15.7 Auto-download via subscriptions *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ⏸ Later (Brady, 2026-10-18) | — | previous step |

Not part of this phase: Brady moved it to the roadmap's [Later](../ROADMAP.md#later) list (2026-10-18). Moonfin's own auto-download keeps working on Silo through the ordinary downloads of 15.2 and 15.3.

**Goal.** Map Moonfin's auto-download to Silo download subscriptions.

**Silo v2 endpoints**

- `/downloads/subscriptions`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

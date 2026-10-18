# Phase 15: Downloads and offline

[← Roadmap](../ROADMAP.md)

Read Silo's downloads design before step 15.3; it is a full server-managed download system.

**Phase done when:** Download a movie and an episode, play them offline, and the progress syncs back.

---

<a id="step-15-1"></a>
## 15.1 Download permission and capability

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

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
| ☐ Not started | — | previous step |

**Goal.** Signed direct-download links.

**Silo v2 endpoints**

- `POST /direct-download/links`
- `GET /direct-download`

**Where in Moonfin**

- `lib/data/services/download_service.dart`

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

# Phase 15: Downloads and offline

[← Roadmap](../ROADMAP.md)

Read Silo's downloads design before step 15.3; it is a full server-managed download system.

**Phase done when:** Download a movie and an episode, play them offline, and the progress syncs back.

---

<a id="step-15-1"></a>
## 15.1 Download permission and capability

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Show download actions only when the account may download.

**Silo v2 endpoints**

- `GET /capabilities/downloads`

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
| ☐ Not started | — | previous step |

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

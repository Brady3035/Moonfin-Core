# Phase 12: Other platforms and casting

[← Roadmap](../ROADMAP.md)

One backend or cast target per commit; each declares its own honest codec evidence and sends auth correctly.

**Phase done when:** Plays on every platform you own (Android TV, Fire TV, iOS, Apple TV, web) and casts.

---

<a id="step-12-1"></a>
## 12.1 Android / Android TV / Fire TV (Media3)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** MediaCodecList evidence; headers via the data source factory.

**Where in Moonfin**

- `lib/playback/media3_player_backend.dart`

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

<a id="step-12-2"></a>
## 12.2 Apple: iOS, tvOS, macOS native (AVPlayer/Aether)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Where in Moonfin**

- `lib/playback/appletv_backend.dart`
- `lib/playback/aether_backend.dart`
- `lib/ui/screens/playback/appletv_player_host_screen.dart`

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

<a id="step-12-3"></a>
## 12.3 Web

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `isTypeSupported` evidence; query token because `<video>` can't send headers.

**Where in Moonfin**

- `lib/playback/html_video_backend_web.dart`

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

<a id="step-12-4"></a>
## 12.4 Chromecast

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Receiver-specific capabilities; token query on the stream URL.

**Where in Moonfin**

- `lib/data/services/cast/google_cast_provider.dart`

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

<a id="step-12-5"></a>
## 12.5 AirPlay

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Where in Moonfin**

- `lib/data/services/cast/airplay_provider.dart`

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

<a id="step-12-6"></a>
## 12.6 DLNA

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Where in Moonfin**

- `lib/data/services/cast/dlna_provider.dart`

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

<a id="step-12-7"></a>
## 12.7 Trickplay and image headers in the player screens

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Replace the hand-built `MediaBrowser Token=` headers with `serverAuthHeaders()` (or none for signed URLs).

**Where in Moonfin**

- `lib/ui/screens/playback/video_player_screen.dart`
- `appletv_player_host_screen.dart`

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

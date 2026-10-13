# Phase 10: Playback (first backend: media_kit on macOS)

[← Roadmap](../ROADMAP.md)

Silo picks the route on the server from the client's codec evidence (`POST /playback/start` → one plan). Start with one backend, then the others in phase 12.

**Phase done when:** On the Mac: play, pause, seek anywhere, resume, stop, and see the right position in Silo afterwards. Same files compared on Emby.

---

<a id="step-10-1"></a>
## 10.1 `playback_core`: timeline offset

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Optional `timelineOffset` on `StreamResolutionResult` applied to progress, the seek bar and trickplay. Zero for Jellyfin and Emby.

**Where in Moonfin**

- `packages/playback_core/lib/src/stream_resolution_result.dart`
- `playback_manager.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Jellyfin and Emby playback unchanged.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-10-2"></a>
## 10.2 `playback_core`: optional replan

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Optional `replan()` on `MediaStreamResolver` and a `PlaybackManager` hook; other servers keep re-resolving.

**Where in Moonfin**

- `packages/playback_core/lib/src/media_stream_resolver.dart`
- `playback_manager.dart`

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

<a id="step-10-3"></a>
## 10.3 Codec capabilities translator

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Moonfin's DeviceProfile → Silo client codec capabilities with honest evidence tiers, validated against Silo's start-request schema.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_capabilities_translator.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- one DeviceProfile sample per backend → expected JSON; schema validation

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-10-4"></a>
## 10.4 Playback context

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** App version, device, form factor, display HDR and audio outputs, deliverable routes.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_playback_context.dart`

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

<a id="step-10-5"></a>
## 10.5 Installation id

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Read and cache it from playback capabilities; refetch on `409 installation_changed`.

**Silo v2 endpoints**

- `GET /playback/capabilities`

**Where in Moonfin**

- `silo_media_stream_resolver.dart`

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

<a id="step-10-6"></a>
## 10.6 Start playback

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `POST /playback/start` → `StreamResolutionResult`; retry an interrupted request with the identical body.

**Silo v2 endpoints**

- `POST /playback/start`

**Where in Moonfin**

- `silo_media_stream_resolver.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: Play the same file on Emby and note direct play vs transcode on each.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-10-7"></a>
## 10.7 Stream authorisation

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Headers on every request (HLS segments and sidecars included); `token=` query only on `/api/v2/stream` URLs where headers can't be sent. Signed artwork never gets a token.

**Where in Moonfin**

- `silo_media_stream_resolver.dart`
- `lib/util/server_url.dart`

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

<a id="step-10-8"></a>
## 10.8 Unplayable media message

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `adaptation_unavailable` → typed error showing Silo's message in the player.

**Where in Moonfin**

- `silo_media_stream_resolver.dart`
- `player error UI`

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

<a id="step-10-9"></a>
## 10.9 Progress reporting

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Sequenced progress samples; ignore `stale_sample`, bump on `409`, stop on `404`.

**Silo v2 endpoints**

- `POST /playback/{sid}/progress`

**Where in Moonfin**

- `silo_play_session_service.dart`

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

<a id="step-10-10"></a>
## 10.10 Stop

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `DELETE /playback/{sid}` with a stable `stop_id` and the final position, with retries.

**Silo v2 endpoints**

- `DELETE /playback/{sid}`

**Where in Moonfin**

- `silo_play_session_service.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Stop halfway; Silo web shows the resume point.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-10-11"></a>
## 10.11 Resume vs start over

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Send `start_position` whenever Moonfin passes one; omit it only when Moonfin has no opinion.

**Where in Moonfin**

- `silo_media_stream_resolver.dart`

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

<a id="step-10-12"></a>
## 10.12 Seek outside the produced window

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** When `can_seek_anywhere` is false, replan on a far seek (needed for progressive remux).

**Silo v2 endpoints**

- `POST /playback/{sid}/replan`

**Where in Moonfin**

- `silo_media_stream_resolver.dart`

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

<a id="step-10-13"></a>
## 10.13 Switch audio track

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Via replan using the track map from 5.8.

**Where in Moonfin**

- `silo_media_stream_resolver.dart`

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

<a id="step-10-14"></a>
## 10.14 Subtitles: embedded and sidecar

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Subtitle inventory → external subtitles, ASS font bundles; off = -1.

**Where in Moonfin**

- `silo_media_stream_resolver.dart`

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

<a id="step-10-15"></a>
## 10.15 Change quality / bitrate

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Via replan.

**Where in Moonfin**

- `silo_media_stream_resolver.dart`

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

<a id="step-10-16"></a>
## 10.16 Pick a version

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Explicit version choice sets `allow_alternate_versions: false`.

**Where in Moonfin**

- `silo_media_stream_resolver.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- The Salt Path: play each version.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

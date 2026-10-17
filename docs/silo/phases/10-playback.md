# Phase 10: Playback (first backend: media_kit on macOS)

[← Roadmap](../ROADMAP.md)

Silo picks the route on the server from the client's codec evidence (`POST /playback/start` → one plan). Start with one backend, then the others in phase 12.

**Phase done when:** On the Mac: play, pause, seek anywhere, resume, stop, and see the right position in Silo afterwards. Same files compared on Emby.

---

<a id="step-10-1"></a>
## 10.1 `playback_core`: timeline offset

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Optional `timelineOffset` on `StreamResolutionResult` applied to progress, the seek bar and trickplay. Zero for Jellyfin and Emby.

**Where in Moonfin**

- `packages/playback_core/lib/src/stream_resolution_result.dart`
- `packages/playback_core/lib/src/playback_manager.dart`

### How it works

A server can hand the player a stream that doesn't start at the start of the file. Silo does this for its remuxes (protocol v3 §5): a progressive or HLS copy remux starts at the keyframe before the resume point, and the player counts from that cut. Its plan says so with `timeline.timeline_offset_seconds`, what to add to the player's position to get the source position. Jellyfin and Emby transcodes keep the source timeline, so for them this is always zero.

`StreamResolutionResult.timelineOffset` (a `Duration`, default zero) carries it. `PlaybackManager` keeps everything it hands out on the media's timeline and converts only at the edge to the backend:

- **From the player:** the position stream, `currentPlaybackPosition`, the position a re-resolve or a stop starts from, and the player's duration have the offset added (`_mediaPosition`). So `state.position` (the seek bar, chapters, trickplay, skip-intro, the progress reports and the stop report) and `state.duration` are media time.
- **To the player:** the start position given to `play`, the resume seek after open (`_seekWhilePausedAndMaybeResume`), `seekTo` and the seek that restores the position after track selection have it taken off (`_playerPosition`); a target before the stream's start goes to the stream's start.
- `notifyExternalSeek` (tvOS's native transport, which moves the player itself) gets a player position and turns it into a media one.
- The end-of-file check in `_onTrackCompleted` compares the player's duration on the media timeline with the media position.

The offset comes from the stream being played (`_currentResolution`, or the last one while a re-resolve tears it down). With an offset of zero every conversion is the identity, so nothing changes for Jellyfin, Emby or offline files. Silo sets it from 10.6 on.

### Testing

**Automated tests**

- `test/playback/playback_manager_timeline_offset_test.dart` (new, 5 tests): with a stream cut at 10 minutes, a resume at 10:50 starts the player at 0:50; a player position of 1:00 reads as 11:00 (`state.position` and `currentPlaybackPosition`) and a 110-minute player duration as 120; a seek to 15:00 goes to the player as 5:00, one before the cut as 0:00; the stop is reported at 11:00. With no offset, positions and seeks pass through unchanged.
- `test/playback/` (the manager and backend tests): still pass.

**Manual test plan**

- Emby: play a film from the start and resume another part way through; the seek bar, seeking, skip-intro and the resume point Emby shows afterwards are as before (no Silo stream sets an offset until 10.6).
- Jellyfin, if you have one to hand: the same.
- Silo: covered by 10.6 and 10.12 (a resumed remux shows the right time on the seek bar).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | timeline offset 5/5; `test/playback/` 841/841; analyzer: no new issues (upstream infos only). Full app suite left to Brady |
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
- `silo_extras_mapper.dart`: set `siloLocalTrailersPlayable` to true once an extra plays (added at 6.17), so local trailers come back to the trailer button and the extras' trailer count; check a title's local trailer plays from the trailer button.

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

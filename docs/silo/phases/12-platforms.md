# Phase 12: Other platforms and casting

[← Roadmap](../ROADMAP.md)

One backend or cast target per commit; each declares its own honest codec evidence and sends auth correctly.

**Phase done when:** Plays on every platform you own (Android TV, Fire TV, iOS, Apple TV, web) and casts.

---

<a id="step-12-1"></a>
## 12.1 Android / Android TV / Fire TV (Media3)

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Honest evidence and traits for Android's players, the display's HDR, and the stream's headers through the data source factory.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_capabilities_translator.dart`: `SiloPlayerTraits.media3`, `.mpvAndroid`; two new traits, `drawsAssStyling` and `loadsFontAttachments`
- `lib/playback/silo_playback_environment.dart`: Android's traits from the engine setting; the display's HDR (`siloDisplayHdr`)
- (`lib/playback/media3_player_backend.dart`, `Media3VideoView.kt`: unchanged; see below)

**Also in this commit: the phase 11 bookkeeping.** The seven phase 11 hashes with Brady's macOS rows (2026-10-17): 11.1–11.3, 11.6 and 11.7 pass and are ticked in the roadmap; 11.4 is open (a season finale on an unwatched show closes the player; deferred by Brady to the end of the project); 11.5 is untested (no theme file yet). The 5.13 fix found testing 11.7 (`36f999a42`, random titles from the whole library) gets its hash and Brady's Pass row.

### How it works

Android has two engines, picked in Moonfin's settings: **Media3** (ExoPlayer, the default) and **libmpv** (media_kit). Each builds its own device profile (`DeviceProfileBuilder`), which the translator reads (10.3). What a start adds beyond the profile are the player's traits (`SiloPlayerTraits`), and until now Android claimed none:

- **Media3** (`SiloPlayerTraits.media3`): it picks any audio track of an original file (Moonfin hands it the track's ordinal, `audioTrackOrdinal`), so the start claims `client_selected_audio_track_v1`. It also draws the subtitles it extracts from the file (SubRip, SSA, WebVTT, PGS, VobSub), so `embedded_subtitles_v1` and `native_embedded` are claimed, with **`ass_styling` and `font_attachments` false**: ExoPlayer draws ASS without its styling and loads no attached fonts. The two new traits say so, here and for sidecars. Silo then hands over a simplified rendering where it has to, which the start allows (`subtitle_fidelity_preference: compatible`). HDR: Media3 sends HDR and Dolby Vision to the display as they are and maps nothing to an SDR screen, so no `client_managed_dynamic_range_v1`.
- **libmpv on Android** (`SiloPlayerTraits.mpvAndroid`): any audio track and embedded subtitles with styling and fonts, as on the desktop, but no dynamic-range claim: on Android it decodes through MediaCodec onto the surface and doesn't tone-map.
- **Which one** is read from the engine setting at every start, as the playback module picks the backend.
- **The display's HDR.** Android TV asks its display what it shows (`DisplayHdrProbe`, which keeps listening for a TV or AVR that wakes up later). When it has answered, the environment sends it (`siloDisplayHdr`): `HDR10`, `HDR10_PLUS`, `HLG` and `DOLBY_VISION` become Silo's `hdr10`, `hdr10_plus`, `hlg` and Dolby Vision profiles 5, 7 and 8 (a display names no profile; Silo intersects with the decoder's), with `hdr_evidence: exact` (10.4). A proven SDR panel sends all off. A display that never answered stays unknown, as on every other platform.
- **Headers.** Media3 already sends a stream's headers on every request: the native view sets them on its `DefaultHttpDataSource.Factory` (`setDefaultRequestProperties`), which serves the playlist, the segments and the sidecars. Nothing changed there. Silo's `token=` on `/api/v2/stream/` URLs (10.7) covers anything loaded outside it.
- **Evidence stays `declared`.** The goal named MediaCodecList evidence (`exact`: per-codec profiles, levels, bit depths and bounds). Moonfin's codec probe has most of it, but under `exact` Silo matches the file's profile names against the decoder's strictly, and a naming mismatch would turn direct plays into transcodes. That can't be checked without an Android device, so this step keeps `declared` (flat codec lists, as on the Mac) and leaves `exact` for a follow-up once Brady can test on Android.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_capabilities_translator_test.dart` (1 new): Media3's start claims the selected audio track and embedded subtitles, with no ASS styling or font attachments for embedded tracks or sidecars, and fits the contract. `playback_silo` 85/85.
- `test/playback/silo_playback_environment_test.dart` (4 tests, 2 new): Android plays through Media3 by default and libmpv's Android traits when picked; the display's formats as Silo's details, none when it was never read.

**Manual test plan**

Brady has no Android device to test on (2026-10-17), so these go to the deferred platform checks in 17.5.

- a. Android TV, Media3: play xXx, Young Justice 1x01 and an HDR film; each starts, seeks and resumes like on Emby. Playback info shows Silo's play method.
- b. Android TV with an HDR TV: an HDR10 or Dolby Vision original direct plays (no tone-mapping transcode).
- c. An MKV with PGS subtitles: picking them on an original file shows them without a transcode.
- d. Switch the engine to libmpv in settings and repeat a.
- e. Fire TV: a.
- f. Android phone: a; casting is 12.4.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | translator 1 new (`playback_silo` 85/85); environment 4/4; analyzer: no issues in the changed files |
| 2026-10-17 | Android | — | Deferred | no device; checks a–f in 17.5 |
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

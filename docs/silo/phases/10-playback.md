# Phase 10: Playback (first backend: media_kit on macOS)

[← Roadmap](../ROADMAP.md)

Silo picks the route on the server from the client's codec evidence (`POST /playback/start` → one plan). Start with one backend, then the others in phase 12.

**Phase done when:** On the Mac: play, pause, seek anywhere, resume, stop, and see the right position in Silo afterwards. Same files compared on Emby.

---

<a id="step-10-1"></a>
## 10.1 `playback_core`: timeline offset

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

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
| ☑ Done | — | previous step |

**Goal.** Optional `replan()` on `MediaStreamResolver` and a `PlaybackManager` hook; other servers keep re-resolving.

**Where in Moonfin**

- `packages/playback_core/lib/src/stream_replanner.dart` (new)
- `packages/playback_core/lib/src/playback_manager.dart`
- `lib/playback/local_first_media_stream_resolver.dart`

### How it works

Moonfin changes a track, the quality or a failing stream by **re-resolving**: `_reResolveNow` stops the player, reports the session stopped (and, for a transcode, kills the server's job), then resolves the item again at the current position. On Jellyfin and Emby that is the only way, since a new `PlaybackInfo` is a new session. Silo can move a live session to a new plan instead (`POST /playback/{sid}/replan`, protocol v3 §6): the session, its progress sequence and its transcode slot carry on, and the server keeps the viewer's choices. Stopping and starting again would lose all that, and a remux far seek (10.12) can't be done any other way.

A new optional interface in `playback_core`, **`StreamReplanner`** (`stream_replanner.dart`), lets a resolver offer that:

- `canReplan(current)`: whether the stream's session can still be moved.
- `replan(item, current, ReplanRequest)`: the new stream, in the same session. `ReplanRequest` carries the same choices a resolve takes (device profile, bitrate ceiling, audio and subtitle index, version, the direct-play flags), the media position to start at, and a `ReplanReason`: `trackChange`, `qualityChange`, `seek` (used from 10.12) or `failure`.

`PlaybackManager` asks for it wherever it would re-resolve the item it is playing:

- `_reResolveNow` (track changes, `changeBitrate`, the error recoveries): when the resolver can replan the current stream it still stops the player, but reports **no stop**, kills no transcode, and marks the retired progress generation `replanned` so a progress report still in flight can't report a stop late. It then plays the item with `replanFrom` set. The reason is `qualityChange` for `changeBitrate`, `failure` for an error recovery, else `trackChange`.
- The re-resolves inside `_playCurrentItem` (a track the selectors want on a transcode, the client's own transcode reason, the startup retry when the stream never got ready) replan from the stream just resolved, the last two as a `failure`.
- `_playCurrentItem`'s `resolve` replans from `replanFrom` (then from each stream a replan returns, should it resolve again); everything after it (track matching, opening the player, progress) is unchanged.
- **A refused replan** (the server ended the session, say) is logged, the old stream is reported stopped as any re-resolve would, and the item resolves afresh.

A local file never replans (`isLocalMedia`). `LocalFirstMediaStreamResolver`, which wraps every server's resolver in the app, implements the interface by asking the server resolver it wraps; Jellyfin's and Emby's don't implement it, so `canReplan` is false for them and they re-resolve exactly as before. Silo's resolver implements it from 10.12 on.

### Testing

**Automated tests**

- `test/playback/playback_manager_replan_test.dart` (new, 5 tests): with a resolver that replans, an audio change replans from the playing stream at its position (reason `trackChange`, the new index) and reports no stop and kills no transcode; a second change (subtitles) replans from the stream the first returned; `changeBitrate(8)` is a `qualityChange` with an 8 Mbit/s ceiling; a refused replan reports the old stream stopped and resolves a new session; a resolver that says it can't replan is stopped and resolved as before.
- `test/playback/` (the existing re-resolve, track carry-over and live tests): still pass.

**Manual test plan**

- Emby: on a film that transcodes (or with a bitrate cap), switch the audio track, turn subtitles on and off and change the quality from the player menu; each switch restarts at the same position as before, and Emby's dashboard shows the old session ending and a new one starting, as before.
- Emby: direct play a film and switch audio: it switches in place as before.
- Silo: covered by 10.12–10.15.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | replan 5/5; `test/playback/` 846/846; analyzer: no new issues. Full app suite left to Brady |
| | | | | |

---

<a id="step-10-3"></a>
## 10.3 Codec capabilities translator

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Goal.** Moonfin's DeviceProfile → Silo client codec capabilities with honest evidence tiers, validated against Silo's start-request schema.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_capabilities_translator.dart` (new)
- `packages/playback_silo/test/silo_contract.dart` (new): checks a body against the pinned contract
- `packages/playback_silo/test/fixtures/device_profile_mpv.json` (new): the libmpv backend's profile

### How it works

Silo plans the route on the server (protocol v3 §1): the client says what it can play, not what it wants. A playback start carries `client_capabilities` (codec lists, HDR, a resolution ceiling, and how the client knows: the *evidence tier*), and per delivery class (`original_http`, `progressive`, `hls`) the containers, codecs, channel ceiling and subtitle handling it accepts. Every Moonfin backend already says all of that in the Jellyfin `DeviceProfile` it builds (`DeviceProfileBuilder`), so `siloCapabilitiesFromDeviceProfile(profile, traits:)` reads it rather than describing each backend twice. It answers `SiloClientCapabilities`: `clientCapabilities`, `deliveries` and the `clientFeatures` they rely on. Pure functions, no I/O.

- **Evidence tier: `declared`** for video and audio. A profile is a statement, not a probe of the device's decoders; Silo then matches the flat codec lists only (§3). `video_decode[]` is left out rather than made up: on the strict tiers an entry with no bounds would claim every variant of a codec. A backend that enumerates its decoders (Media3, phase 12) can claim `exact` later. Passthrough needs `exact`, so none is claimed; the player still bitstreams locally what it receives.
- **Codecs and containers** come from the video direct-play profiles. A codec the codec profiles rule out (Moonfin writes that as a `VideoProfile` that must equal `none`; MPEG-4 Part 2 on mpv) is dropped. `mkv` and `matroska` both go in, since Silo names Matroska files `mkv`.
- **HDR** (`hdr_details`, and `hdr` when any of it is on) comes from the HEVC and AV1 range types the codec profiles don't rule out: HDR10, HLG, HDR10+, and Dolby Vision profile 5 (`DOVI`), 7 (`DOVI_WITH_EL`), 8 (`DOVI_WITH_HDR10`), 10 (AV1). This describes the decoder; the display is 10.4's.
- **`max_resolution`**: the widest unconditional `Width` limit, as Silo's class (480p up to 854 wide … 4320p); none leaves it out.
- **Deliveries.** `original_http`: the direct-play containers and codecs. `progressive`: the same codecs in Silo's remux containers (MP4, Matroska). `hls`: the decodable codecs among H.264, HEVC (in fMP4) and the HLS transcoding profiles' video codecs (Silo's HLS is a copy remux as often as a transcode, so not only the transcode targets; AV1 only where a profile names it, as AVFoundation's HLS may not take it) and those profiles' audio codecs; a profile without HLS transcoding has `supported_on_device: false` and a `failure_reason`. A channel limit below 6 on the audio codec profiles becomes `max_channels` on each class; a player that downmixes on its own (mpv, 8 channels) has none. `auth_header_refresh` is false: a stream's URL and headers are fixed once opened (10.7).
- **Subtitles.** A file played whole draws its embedded tracks itself, so `original_http` attests native selection (`native_embedded`: Matroska, WebM, MP4/MOV; SRT, ASS/SSA, WebVTT, mov_text, PGS, DVD and DVB bitmaps; picked by the probed stream index, which is Moonfin's `Index`) and the client feature `embedded_subtitles_v1`. Without it Silo would extract an embedded PGS track or burn it in. Remuxes and HLS carry subtitles as sidecars Moonfin loads as external tracks: text and ASS yes, bitmap sidecars and font bundles no (Moonfin loads neither), so a bitmap there is burnt in, as on Emby.
- **`SiloPlayerTraits`** says what the profile can't (the defaults claim none of it): whether the player maps an original's HDR/Dolby Vision to the screen itself (`client_managed_dynamic_range_v1` on `original_http`, only when it decodes HDR at all), picks any audio track of the file (`client_selected_audio_track_v1`), plays progressive and HLS, and draws embedded subtitles. `SiloPlayerTraits.aether` is AetherEngine (Moonfin's main player on macOS and iOS) and `SiloPlayerTraits.mpv` the libmpv backend (Windows, Linux): both have all of them. 10.4 supplies the traits from the app.

`client_features` is `playback_plan_v3` and `embedded_subtitles_v1`. Not claimed: `header_authenticated_media_v1` (signed stream URLs are kept, 10.7), `subrip_sidecar_v1` (sidecars stay WebVTT), `plan_invalidated_v1` (needs the control socket, phase 13), `software_video_decode_v1` (only means something on the strict tiers).

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_capabilities_translator_test.dart` (new, 13 tests), on the libmpv backend's real profile (captured from `DeviceProfileBuilder.build` with that backend's settings) and a hand-made narrow one:
  - mpv: `declared` evidence, its eight video codecs (MPEG-4 Part 2 left out), its audio codecs and containers, no `video_decode` or passthrough; HDR10, HLG, HDR10+ and Dolby Vision 5 and 8; `4320p`; all three classes, no channel ceiling; HLS takes H.264 and HEVC; the original carries both claims and native embedded subtitles (PGS by stream index); remuxes and HLS use sidecars without bitmaps or fonts.
  - narrow device, default traits: AV1 ruled out by its profile is left out; no HDR, `1080p`, `max_channels` 2 on every class; no claims and no `embedded_subtitles_v1`; without an HLS profile `hls` is unsupported with a reason.
  - a player without embedded subtitle rendering sends no `embedded_subtitles_v1` and no native attestations.
  - every body passes `silo_contract.dart` against `ClientCodecCapabilitiesV3` and `DeliveryCapabilityV3` from the pinned contract (`bd9d59ea`): required fields, types, enums, bounds, and no field the contract doesn't have (Silo refuses unknown fields with 422). One test checks the validator refuses a missing and an unknown field.
- `playback_silo`: 16/16.

**Manual test plan**

- Nothing to see yet: the translator is used by the playback start (10.6). Its effect is checked there (direct play of an HEVC/DTS Matroska file, an HDR10 file direct playing on an SDR Mac).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | translator 13/13; `playback_silo` 16/16; analyzer: no issues |
| | | | | |

---

<a id="step-10-4"></a>
## 10.4 Playback context

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** App version, device, form factor, display HDR and audio outputs, deliverable routes.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_playback_context.dart` (new)
- `packages/playback_silo/lib/src/silo_plugin.dart`, `silo_media_stream_resolver.dart` (take the environment)
- `lib/playback/silo_playback_environment.dart` (new), `lib/di/modules/playback_module.dart`

### How it works

Next to its codec evidence (10.3), a Silo start describes where it is playing: `client_playback_context` (protocol v3 §3–4) with the app version, the device, its form factor, the output (display HDR) and the delivery classes.

- **`SiloPlaybackEnvironment`** (`playback_silo`) is what the app knows and the package can't: form factor (`tv`, `phone`, `tablet`, `desktop`, `web`; Silo uses it for its device quirks), platform, OS version, manufacturer, model, app build, the display's native HDR formats when the platform could ask, and the player's `SiloPlayerTraits` (10.3).
- **`siloPlaybackContext(environment:, appVersion:, capabilities:)`** shapes it: `protocol_version` 3, `form_factor`, `app_version` (the client's `DeviceInfo.appVersion`), `app_build`, `device`, `output`, and `deliveries` from the translator. Values are trimmed and cut to Silo's bounds (32 for the platform, 64 for versions, 128 for the rest); an empty one is left out rather than sent blank.
- **Output.** `output.hdr_details` is what can be shown *natively*: the decoder's formats the display also has. When the display couldn't be asked it is all off and `display.hdr_evidence` is `unknown`, which Silo reads as "claim no native HDR output" (and, with `display` present, it doesn't fall back to the decoder's formats either). A display that answered is sent as `exact`, its own formats as `hdr_types`; `hdr_details` never claims more than they do, which Silo would refuse. `output_context_id` is left out: Moonfin has no stable id for the output route, and Silo compares it for equality, so a made-up one would invalidate plans at random.
- **The app** (`siloPlaybackEnvironment()`, `lib/playback/silo_playback_environment.dart`) builds it from `PlatformDetection`: form factor, platform, OS version, model (where the platform reports one), `Apple` as manufacturer on Apple platforms, and the main player's traits: **AetherEngine on macOS and iOS** (Moonfin's main player there; media_kit only plays trailers and theme music on the Mac) and libmpv on Windows and Linux, both `SiloPlayerTraits.aether`/`.mpv` (they pick any audio track, map an original's HDR to the screen themselves, draw embedded subtitles). The other backends (Media3, tvOS, web) send the defaults, which claim nothing beyond their profile, until phase 12. The display's HDR is left unknown: only Android TV can ask its display (`DisplayHdrProbe`). For an original file that costs nothing, since both players map HDR themselves; a remux of an HDR file is then tone-mapped by Silo (noted for phase 12).
- `SiloPlugin(client, environment:)` takes the environment as a function, asked at every start, and hands it to the resolver; `playback_module.dart` passes `siloPlaybackEnvironment`. The other places that build a Silo resolver (cast, the media bar) get the defaults. The resolver uses it from 10.6.

The roadmap called this phase "media_kit on macOS"; on the Mac it is in fact AetherEngine, and the translator, traits and test plans follow that.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_playback_context_test.dart` (new, 3 tests): a Mac whose display can't be asked (device fields, all-off `hdr_details`, `hdr_evidence: unknown`, the translator's deliveries); a display that answered (HDR10, HLG, Dolby Vision 5/7/8) gives `exact` with its formats and `hdr_details` limited to what the decoder also has (no profile 7, no HDR10+); blank values left out, over-long ones cut, a blank app version sent as `unknown`. Each context passes the contract check for `ClientPlaybackContextV3`.
- `test/playback/silo_playback_environment_test.dart` (new, 3 tests): macOS is a desktop with Apple as manufacturer and AetherEngine's traits, display HDR unknown; Windows and Linux use libmpv's; Android (Media3, phase 12) claims nothing beyond its profile.
- `playback_silo` 19/19.

**Manual test plan**

- Nothing to see yet; 10.6 sends the context. Its log line (`→ POST …/playback/start`) appears from then on.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | context 3/3; environment 3/3; `playback_silo` 19/19; analyzer: no issues |
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

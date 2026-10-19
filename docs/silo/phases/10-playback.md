# Phase 10: Playback (first backend: media_kit on macOS)

[← Roadmap](../ROADMAP.md)

Silo picks the route on the server from the client's codec evidence (`POST /playback/start` → one plan). Start with one backend, then the others in phase 12.

**Phase done when:** On the Mac: play, pause, seek anywhere, resume, stop, and see the right position in Silo afterwards. Same files compared on Emby.

---

<a id="step-10-1"></a>
## 10.1 `playback_core`: timeline offset

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `ba627bc9a` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-2"></a>
## 10.2 `playback_core`: optional replan

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `2e40f3dda` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-3"></a>
## 10.3 Codec capabilities translator

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `ea3e51070` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-4"></a>
## 10.4 Playback context

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `ba741e376` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-5"></a>
## 10.5 Installation id

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `a4525ae51` | previous step |

**Goal.** Read and cache it from playback capabilities; refetch on `409 installation_changed`.

**Silo v2 endpoints**

- `GET /playback/capabilities`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_playback_api.dart` (`capabilities`, `SiloPlaybackCapabilities`, `isInstallationChanged`)
- `packages/server_silo/lib/src/silo_media_server_client.dart` (`playbackApi` is a `SiloPlaybackApi`)

### How it works

Every playback mutation (start, progress, stop, replan, route events) carries the server's `installation_id`, the persisted UUID of that Silo installation, read from `GET /api/v2/playback/capabilities` (Playback API, "Capabilities"). A different value answers `409 installation_changed`: the server was reset or replaced, and the client reads the capabilities again and starts a new attempt.

`SiloPlaybackApi.capabilities()` reads them and answers `SiloPlaybackCapabilities`: `installationId`, `revision`, `state`, `allowed`, `protocolVersions`, `features` and `deliveries`, with `playable` (state `available`, allowed, protocol 3 offered, an installation id) and `has(feature)`. The answer is kept for a minute (`capabilitiesLifetime`, as Silo's web player does) on the client's clock, and reads made while one is in flight share it. `capabilities(refresh: true)` reads now and `forgetCapabilities()` drops the kept one. `SiloPlaybackApi.isInstallationChanged(error)` recognises the `409` by its problem code, so the resolver (10.6) and the session service (10.9, 10.10) react to it the same way.

`SiloPlaybackApi` now takes the client's Dio and clock, and `SiloMediaServerClient.playbackApi` is typed `SiloPlaybackApi`, so `playback_silo` can reach the wire calls this phase adds (the protocol itself lives there, not in `server_silo`). The request carries the usual Silo headers, `X-Profile-Id` included (the contract requires it here).

This server's capabilities (`silo/playback_capabilities.json`, captured at `bd9d59ea`) list protocol 3, all four deliveries and the features the later steps rely on: `sequenced_progress_v1` (10.9), `fixed_media_file_v1` (10.16), `seek_reanchor_v1` (10.12), `embedded_subtitles_v1` (10.3).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_playback_api_test.dart` (4 more): the fixture's installation id, features and deliveries, playable; kept 59 s, read again after 61 s, shared while being read, read now on `refresh` and after `forgetCapabilities`, with `X-Profile-Id`; a `not_configured` server is not playable; a `409 installation_changed` is recognised, another error isn't.
- `server_silo` 538/538; analyzer: no issues.

**Manual test plan**

- Nothing to see yet; the first start (10.6) reads the capabilities (`→ GET …/playback/capabilities` in the network log, once a minute at most).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | capabilities 4/4; `server_silo` 538/538; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-6"></a>
## 10.6 Start playback

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `039e2e2f5`, fix `ec9a9c830` | previous step |

**Goal.** `POST /playback/start` → `StreamResolutionResult`; retry an interrupted request with the identical body.

**Silo v2 endpoints**

- `POST /playback/start`

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart`
- `packages/playback_silo/lib/src/silo_plan_mapper.dart` (new): plan → `StreamResolutionResult`
- `packages/playback_silo/lib/src/silo_playback_sessions.dart` (new): the sessions a client has open
- `packages/server_silo/lib/src/api/silo_playback_api.dart` (`startPlayback`, `isRetryableStartError`)
- `silo_extras_mapper.dart`: `siloLocalTrailersPlayable` is now true (added at 6.17), so local trailers come back to the trailer button and the extras' trailer count.
- `packages/playback_silo/pubspec.yaml`: depends on `server_silo` and `dio`
- `lib/playback/silo_plugin_for.dart` (new at the fix): the app's `SiloPlugin`, built from the Silo client inside the app's wrapper

### How it works

`SiloMediaStreamResolver.resolve` replaces the placeholder that refused every Silo item. It asks Silo for one plan and turns it into the `StreamResolutionResult` Moonfin's player opens.

**Which file.** The version Moonfin names (`mediaSourceId`), else the item's default (its first `MediaSource`, 5.8). When that source has no track map (a season list's episode carries only light `files`, a deep link carries no sources), the item is read again (`getItem`, which embeds full versions). A local extra has no catalog page of its own; it plays the `file_id` it carries (`_silo.file_id`, 6.17).

**The request** (`PlaybackStartBody`, validated against the pinned contract in the tests):

- `protocol_version` 3, `client_features`, `client_capabilities` and `client_playback_context` from the backend's device profile and the app's environment (10.3, 10.4);
- `file_id`, `profile_id` (the profile the client acts as), `installation_id` (10.5), a fresh `playback_attempt_id` (a random UUID v4);
- `quality_preference: auto` (Silo picks within any ceiling), `bandwidth_cap_kbps` from Moonfin's bitrate ceiling when there is one, `subtitle_fidelity_preference: compatible` (Moonfin draws ASS but can't fetch a sidecar's fonts), `metered: false`;
- `start_position` in seconds when Moonfin passes a start (10.11 makes it explicit always), `audio_track_index` (Silo's audio ordinal, from Moonfin's index through the track map) when Moonfin picked one; without it Silo uses the series' or profile's preference.

**Sending it.** `POST /api/v2/playback/start` answers `201` for every decision. An interrupted request (no answer, a timeout, `408`, `429`, `5xx`) is resent with the identical body, backing off 1, 2, 4, 8 s, within 60 s; each request may take 45 s (Silo can start a worker before it answers), as Silo's web player does. Silo is idempotent on the attempt id and body, so a resend after a lost answer replays the same session instead of opening a second. Any other `4xx` is final. A `409 installation_changed` reads the capabilities again and starts a new attempt once.

**A refusal** (`outcome: adaptation_unavailable`) throws with Silo's own `terminal.message`; 10.8 makes it a typed error.

**The plan → Moonfin** (`siloPlanToResolution`):

- `streamUrl` from `stream.url`: an absolute URL (a proxy node) as it is, a path under the server's base URL; `/stream/…` or `/playback/transcode/…` without `/api/v2` is mapped there as the web player does. The query (`st`, `seek`) is kept byte for byte.
- `playMethod` from `delivery`: `original_http` → direct play, `server_remux_progressive`/`server_remux_hls` → direct stream (a remux), `server_transcode_hls` → transcode.
- `mediaSourceId` is `effective_media_file_id` (Silo can fall back to another version), `playSessionId` the session, `container` from `stream.container`, `timelineOffset` from `timeline.timeline_offset_seconds` (10.1; a remux cut at 9:53.4 for a resume at 10:00 plays from there).
- `mediaStreams` are the effective file's streams in Moonfin's numbering (reading that version when Silo fell back to one Moonfin hasn't loaded); `selectedAudioStreamIndex` is Silo's chosen audio track (`selected_tracks.audio.index`) back as Moonfin's index.
- `sourceBitrate` from `source.bitrate_kbps`; `videoRangeType` from the file's video stream, else the recipe; `transcodingReasons` from `decision_reason` and the degradation warnings, mapped to Jellyfin's reason names where one fits (`audio_adaptation` → `AudioCodecNotSupported`, `container_normalization` → `ContainerNotSupported`, the quality reasons → `ContainerBitrateExceedsLimit`…), none for the original.
- `requestHeaders` are `stream.headers` (Silo sends none today); the account's credentials are added in 10.7, **so streams play from 10.7 on**.

**The session** is kept (`SiloPlaybackSessions`, one per client, shared with the session service through the client): its id, attempt id, installation id, item, plan, start body and the mapped source, for progress, stop and replans (10.9–10.16).

Local extras play now, so `siloLocalTrailersPlayable` is true: a title's local trailers count again (`LocalTrailerCount`) and come first on its trailer button, as on Jellyfin.

**Fix at 10.6: nothing played in the app** (commit `silo(10.6): Fix playback with the app's wrapped client`, found by Brady). The app hands every server's client around wrapped in `ConnectivityAwareMediaServerClient` (offline browsing), and the playback module, the media bar's trailers and the three cast providers built `SiloPlugin` from that wrapper. The resolver calls Silo's playback API on the Silo client itself, so every start threw `Bad state: ConnectivityAwareMediaServerClient is not a Silo client` before any request; the session service would have reported nothing for the same reason. The package's tests built the plugin from a bare Silo client, so they never saw it. All five sites now build it through `siloPluginFor(client)`, which takes the client inside the wrapper (`siloClientOf`, already used for Silo's tokens); the resolver and the session service then share that one client, and with it one session registry.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_start_test.dart` (new, 14 tests), against a fake Silo (`silo_test_server.dart`) and plan fixtures for this server's xXx file (`decision_remux.json`, `decision_original.json`, `decision_terminal.json`, which pass the contract's `PlaybackDecision` schema):
  - the request: passes `PlaybackStartBody`; file `4598`, profile `p1`, the capabilities' installation id, a UUID v4 attempt id, `start_position` 600 for 10:00, Moonfin's audio stream 1 as Silo's audio track 0, a 20 Mbit/s ceiling as 20000 kbps, `X-Profile-Id` and the bearer token; nothing it has no opinion on; an item without versions is read first; an extra plays its `file_id`.
  - the plan: a progressive remux gives an absolute URL with its `seek` and `st`, a direct stream of file `4598` in session `5d1b…`, a 9:53.4 offset, the file's streams with audio stream 1 selected, `AudioCodecNotSupported`; the original is a direct play with no offset or reasons; the session is kept.
  - failures: a dropped request and a `503` are resent with the identical body (waits 1 s, 2 s); a `422` isn't; `409 installation_changed` reads the capabilities again and sends a new attempt id; a terminal refusal throws Silo's message; a server without playback starts nothing.
- `silo_plugin_test.dart`: the placeholder's refusal test is gone.
- `server_silo/test/silo_extras_test.dart`: local trailers count and list.
- `playback_silo` 31/31; `server_silo` 538/538; analyzer: no issues.
- `test/playback/silo_plugin_for_test.dart` (new at the fix, 1 test): a Silo client wrapped as the app wraps it starts playback (capabilities, start) and its stop reaches Silo (`DELETE /playback/{session}`). Without the fix it fails with Brady's `Bad state`.

**Manual test plan**

Starting plays from 10.7 on (the media requests need the account's token); test these with the batch.

- Play The Salt Path, xXx and an episode of Young Justice from their detail pages: each starts. The network log shows `→ GET …/playback/capabilities` (at most once a minute) and `→ POST …/playback/start` answered `201`.
- **Compare with Emby** (same files): note direct play vs transcode on each (Moonfin's playback info, or Emby's dashboard); on Silo the playback info shows the play method from Silo's plan (direct play for the original, direct stream for a remux, transcode for HLS) and, for a remux, the reason (DTS → AAC on xXx with a stereo setup shows *Audio codec not supported*).
- Resume a film part way through: it starts at the resume point and the seek bar shows the film's time, not the remux's (10.1).
- A title with a local trailer (Silo's web app shows it under extras): Moonfin's trailer button plays the local trailer; the trailers count shows it.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | start 14/14; `playback_silo` 31/31; `server_silo` 538/538; analyzer: no issues |
| 2026-10-17 | macOS | — | Fail | Brady: nothing starts playing (test 2). `Bad state: ConnectivityAwareMediaServerClient is not a Silo client` from the resolver: the app's plugins got the wrapped client |
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | fix: the plugin takes the Silo client inside the wrapper at all five sites; `silo_plugin_for_test` 1/1 (fails without the fix), `connectivity_aware_profile_test` and `silo_token_storage_test` pass; `playback_silo` 83/83; analyzer: no new issues. Full app suite left to Brady |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: after the fix every title plays as on Emby; resume and start over work. The local trailer button still does nothing (open, to revisit later) |
| | | | | |

---

<a id="step-10-7"></a>
## 10.7 Stream authorisation

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `5defdf4ad`, fix `863174834`, second fix `b089477d2` | previous step |

**Goal.** Headers on every request (HLS segments and sidecars included); `token=` query only on `/api/v2/stream` URLs where headers can't be sent. Signed artwork never gets a token.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_plan_mapper.dart` (`SiloStreamAuth`, `siloAuthorizeUrl`, `siloIsServerUrl`)
- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart` (`_streamAuth`)
- (`lib/util/server_url.dart`, named in the plan, needed no change: the player takes the URL and headers from the resolution as they are.)

### How it works

Silo's media routes always need the account and the viewer (Playback API, "Delivery"): the plan's URLs carry a signed stream reference (`st`) that lets any replica rebuild the session, but not who is asking. A client sends its bearer token and profile as headers, or, where a media element can't send headers, the token as `token=`.

`siloPlanToResolution` takes the credentials (`SiloStreamAuth`: access token, profile id, PIN proof) and, for a stream on the server's own origin:

- `requestHeaders` are `Authorization: Bearer …`, `X-Profile-Id` (and `X-Profile-Token` for a PIN-unlocked profile), with `stream.headers` on top. Moonfin's backends send a stream's headers on every request they make for it, HLS playlists and segments included: AetherEngine and Media3 (12.1) take them at open, and the media_kit backend (libmpv: Windows, Linux, Android's second engine) hands them to mpv with the file since the fix below.
- **`token=`** is added only to Silo's `/api/v2/stream/` routes (`siloAuthorizeUrl`): the original file, a progressive remux, and (from 10.14) subtitle sidecars and font bundles. Those are the URLs fetched by something that may not send the player's headers (a subtitle loader, a cast receiver). HLS (`/api/v2/playback/transcode/…`) goes by headers only: Silo copies a playlist's query onto every segment URI, so a token there would ride on each segment for no gain. The rest of the query (`st`, `seek`, a sidecar's identity pins) stays byte for byte, and a URL that already has a `token` keeps it.
- **A URL on another origin** (a proxy node, absolute in the plan) gets neither: the account's credentials never leave the server it signed in to. Moonfin doesn't opt into `authorized_media_origins_v1` (10.3), so Silo signs such URLs itself. **Artwork** never gets a token: its URLs are signed and cached by path (6.2).

**How long it works.** The player can't change a stream's headers or URL once it has opened it. So before the stream is described the resolver refreshes an access token that is past half its life (`_streamAuth`): the stream then works for at least half a token lifetime, 30 minutes on this server (tokens last an hour). The start itself went through the session interceptor, which refreshes only in the last fifth of the life. A failed refresh keeps the current token.

**Fix (2026-10-18): HLS on libmpv.** On Windows a transcode (a lower quality picked during direct play) stayed black and buffered without end; the Mac played it. Silo's replan answered `200` with an HLS plan, then nothing: `MediaKitPlayerBackend.play` opened `Media(url)` without `payload['headers']` (only the Aether, Media3 and Apple TV backends read them), so mpv fetched the HLS playlist without credentials. Direct play worked because `/api/v2/stream/` URLs carry `token=`.

- *First fix* (`863174834`): libmpv's traits said it sends no headers, so the token went into every media URL, as on the web. It didn't work: the playlist was authorised, the segments weren't. Silo's synthetic HLS playlist (`GenerateFullManifest`, `internal/playback/transcode.go`) copies the playlist's query onto each segment through an HLS variable once that saves space (`#EXT-X-DEFINE:NAME="q",…` and `segment/seg_00000.ts?{$q}`), and mpv's HLS reader (FFmpeg) doesn't expand variables, so the segments went out with no token. hls.js and AVFoundation expand them, which is why the web and the Mac are unaffected.
- *Second fix*: the media_kit backend opens `Media(url, httpHeaders: …)` with the resolution's headers (`MediaKitPlayerBackend.mediaForPayload`). media_kit sets them as mpv's `http-header-fields` when the file loads and clears them when it unloads, and FFmpeg's HLS reader sends them on every playlist and segment request, whatever the segment URL says. libmpv's traits go back to sending headers (no `token=` on HLS). `SiloPlayerTraits.aether` stays its own constant. This touches the shared backend: Jellyfin's resolver also hands it headers (its `Authorization`, server URLs only), which mpv now sends too; Emby's hands none. Worth raising upstream as a backend fix.

**Open (raise with Brady):** a stream that is still playing when its token expires: an HLS segment or a seek on a direct play fetched after that would be refused (`401`), since Silo checks the token on every media request. A film longer than the token's remaining life could stop there. Brady's test plan checks it below; if it fails, the fix is a follow-up step (replan to a fresh stream shortly before the token expires, which reopens it at the same position, or Silo accepting the `st` reference alone for a live session).

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_stream_auth_test.dart` (new, 6 tests): a remux on the server gets the bearer and profile headers and `token=` after its `seek` and `st`; HLS gets the headers and no token; a proxy node's URL gets neither; a token with 20 of its 60 minutes left is refreshed once before the stream is described and the new one is used; `siloAuthorizeUrl` adds the token only to `/api/v2/stream/` on the server's origin (not artwork, HLS or a proxy), keeps a token already there, encodes it.
- `silo_start_test.dart`: the remux URL now ends with the token.
- `playback_silo` 37/37; analyzer: no issues.
- Fix: `silo_quality_test.dart` (1 new): on libmpv a quality change's HLS goes by headers (no `token=`); `silo_capabilities_translator_test.dart` (1 new): libmpv and AetherEngine send headers, and AetherEngine claims what libmpv does; `test/playback/media_kit_player_backend_headers_test.dart` (new, 2 tests): the stream's headers go to mpv with the file, and a file without headers opens without any.

**Manual test plan**

- Play xXx (a remux on a stereo Mac: DTS → AAC) and The Salt Path (direct play): both play, seek and resume. The network log shows no `401` for `/api/v2/stream/…`.
- Force a transcode (set a 4 Mbit/s ceiling in Moonfin's playback settings) and play a film: HLS plays past the first minutes (every segment is authorised).
- **Fix (Windows):** play The Simpsons 29x02 (direct play), then pick a lower quality (2 Mbit/s): within a few seconds the transcode plays at the same position, and picking the original again goes back to direct play. Silo's log shows no `401` on `getPlaybackSegment`. Also play a Jellyfin title on Windows (direct and transcoded) to check the shared backend change. Linux and Android's libmpv engine are deferred (17.5, 10.7 f).
- **Token lifetime:** play something for more than 35 minutes (direct play, then once with the 4 Mbit/s ceiling for HLS), then seek. Note whether playback continues or fails with a `401` in the log: that decides the open item above.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | stream auth 6/6; `playback_silo` 37/37; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| 2026-10-18 | Windows | `bd9d59ea` | Fail | Brady: direct play works; after turning the quality down the picture goes black and buffers without end (Mac fine). The log: replan `200`, "transcode (ContainerBitrateExceedsLimit) — H264/EAC3 HLS @ 2000000bps", then `waitingForReady` until stopped. The media_kit backend opens the HLS URL without the stream's headers |
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | fix: libmpv gets the token in every media URL; `playback_silo` 92/92 (2 new), `test/playback/silo_playback_environment_test.dart` 5/5; analyzer: no issues |
| 2026-10-18 | Windows | `bd9d59ea` | Fail | Brady: after the first fix (`863174834`) still black. Silo's log: `getPlaybackSegment` → `401 authentication_required`, `auth_class: anonymous`. The playlist was authorised by its `token=`, the segments were not: Silo's synthetic playlist names segments as `segment/seg_00000.ts?{$q}` with `#EXT-X-DEFINE` (HLS variable substitution) once the copied query is long, and mpv's HLS reader (FFmpeg) doesn't expand it, so the segment URLs carry no credentials |
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | second fix: the media_kit backend hands the stream's headers to mpv, and libmpv goes by headers again; `playback_silo` 92/92, media_kit headers 2/2 (new), `silo_playback_environment_test` + passthrough 15/15; analyzer: no issues in the changed files |
| 2026-10-19 | Windows | `bd9d59ea` | Pass | Brady: after the second fix (`b089477d2`) lowering the quality during direct play transcodes and plays |
| | | | | |

---

<a id="step-10-8"></a>
## 10.8 Unplayable media message

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `1c5cfdc07` | previous step |

**Goal.** `adaptation_unavailable` → typed error showing Silo's message in the player.

**Where in Moonfin**

- `packages/playback_core/lib/src/playback_refused_exception.dart` (new), `playback_manager.dart`
- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart` (`siloRefusal`)
- `lib/ui/navigation/playback_launcher.dart` (the player error path)

### How it works

A start that Silo can't serve is not an HTTP error: it is a `201` decision with `outcome: adaptation_unavailable` and a `terminal` (`reason`, `message`, `retryable`; protocol v3 §7.3), for example `source_unreadable` (*"This file can't be read…"*), `source_metadata_incomplete` (not probed yet, retryable), `bitrate_policy_unavailable` (nothing fits the administrator's limit), `hdr_transcode_unsupported`. Silo writes `message` for the viewer.

- **A typed refusal in `playback_core`:** `PlaybackRefusedException` (`message`, `reason`, `retryable`; `toString()` is the message). It is what any resolver throws when the server decided not to play, as opposed to failing.
- **Silo** (`siloRefusal`) throws it with `terminal.message`, its reason and `retryable`; a terminal without words reads *"Silo can't play this item (reason)."*. Two more cases use it: capabilities that say playback isn't available on the server (*"Playback isn't available on this Silo server."*), and `426 client_upgrade_required`, which Silo answers a client whose protocol it no longer speaks (*"This Silo server needs a newer version of Moonfin to play."*). Other failures (a network error, a `5xx` after the retries) stay errors.
- **The player shows it.** `PlaybackManager` turns a refusal from `resolve` into a failed bringup whose `error` is the message; the video player already shows a failed bringup's error as a snackbar (`_showBringupFailureIfAny`), on the app's messenger, so it stays up when the player closes. That covers a start from a detail page and the next episode starting inside the player alike.
- **No crash.** The launcher (`launchPlayerWhilePreparing`) closes the player for a refusal, as for any start that didn't play, and answers `false` instead of rethrowing it, so it doesn't land in the uncaught-error handler and the crash report.

Moonfin doesn't report the terminal back (`route-events`, optional diagnostics): left for later.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_start_test.dart` (2 more; the terminal and unavailable-server tests now expect the typed refusal): `source_unreadable` throws `PlaybackRefusedException` with Silo's message, reason and not retryable; a server without playback refuses with its message before any start; a terminal without words names its reason (retryable kept); a `426` says a newer Moonfin is needed.
- `test/playback/playback_manager_refused_test.dart` (new, 1 test): a refused resolve fails the bringup with the server's words and opens nothing.
- `test/ui/navigation/playback_launcher_test.dart` (1 more): a refused start closes the player and answers `false` instead of throwing.
- `playback_silo` 39/39; analyzer: no new issues.

**Manual test plan**

- A file Silo can't read: on the server, copy a short text file to `Broken (2020)/Broken (2020).mkv` in a film library and scan (or use any file Silo's web app refuses to play). Play it in Moonfin: the player opens, closes, and a snackbar shows Silo's own message (the same words Silo's web app shows). Nothing in the crash report.
- A film that plays: unchanged.
- **Compare with Emby:** a file Emby can't play shows Moonfin's usual error there (no change).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | refusal: Silo 4/4, manager 1/1, launcher 12/12; `playback_silo` 39/39; analyzer: no new issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-9"></a>
## 10.9 Progress reporting

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `5e3d0c366` | previous step |

**Goal.** Sequenced progress samples; ignore `stale_sample`, bump on `409`, stop on `404`.

**Silo v2 endpoints**

- `POST /playback/{sid}/progress`

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_play_session_service.dart`
- `packages/playback_silo/lib/src/silo_playback_sessions.dart` (sequence, `ended`)
- `packages/server_silo/lib/src/api/silo_playback_api.dart` (`reportProgress`, `isSessionGone`, `isProgressConflict`)

### How it works

Silo keeps the resume point, the watch history and whether a session is still alive from progress samples (Playback API, "Progress and stop"; protocol §2.5). Each is `{installation_id, sequence, position, is_paused}` and Silo applies it with a compare-and-set on the sequence: a higher sequence wins even when the position goes backwards (a seek back), a lower one is `stale_sample`, the same one again `replayed`.

`SiloPlaySessionService.onPlaybackProgress` sends one per call of Moonfin's progress timer (every 5 s; Silo asks for at least one every 10 s, and ends a session that sends nothing for 45 s, or 30 minutes after a paused sample):

- **position** is the media position in seconds, to the millisecond. The manager reports positions on the media's timeline (10.1), so a remux cut at 9:53 reports 11:00 at eleven minutes, as Silo wants (`player + timeline_offset`).
- **is_paused** is the viewer's pause (the manager's `isPaused`, not a stalled stream).
- **sequence** is the session's next number (`SiloPlaybackSession.takeSequence`, from 1), so a sample is never sent twice under one number.
- The installation id is the one the session was started under.

Answers: `applied`, `replayed`, `stale_sample` need nothing. `409 progress_conflict` (Silo has another sample under that number) sends it once more under the next one. `404` (expired, stopped, or the server restarted), `410 playback_session_ended` (an administrator ended it) and `409 installation_changed` mark the session `ended`, and nothing more is sent for it. Any other failure (a network error, a `5xx`) reaches the manager, which already ignores a failed report; the next sample tries again with a higher number.

A report for a stream a replan has since replaced (10.12–10.16) sends nothing: the session's current stream reports for it. `onPlaybackStart` sends nothing (the start opened the session). The client logs only one progress answer a minute (`SiloMediaServerClient`, since 2.2).

Moonfin's own resume point for the item (`UserData`) still comes from Silo on the next read of the item; nothing local changes.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_progress_test.dart` (new, 8 tests): two samples carry the installation id, sequences 1 and 2, 660.25 s and 665 s, the pause, and pass `PlaybackProgressBody`; starting sends nothing; `stale_sample` and `replayed` are fine; a `progress_conflict` resends under sequence 2 and the next sample is 3; `404`, `410 playback_session_ended` and `409 installation_changed` end the session and stop the samples; a `503` reaches the caller and the next sample goes on (sequence 2); a stream replaced by a replan reports nothing.
- `playback_silo` 47/47; analyzer: no issues.

**Manual test plan**

- Play a film for a minute, then look at Silo's web app (Continue Watching, or the film's page) while Moonfin keeps playing: the resume point follows within a few seconds.
- Pause for over a minute, then play on: playback continues (a paused session stays alive; a remux that the server closed meanwhile is 10.12's).
- Seek back a few minutes: Silo's resume point goes back too.
- The network log shows a progress answer about once a minute (`← 200 POST …/progress`), not every 5 s.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | progress 8/8; `playback_silo` 47/47; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-10"></a>
## 10.10 Stop

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `53af116be` | previous step |

**Goal.** `DELETE /playback/{sid}` with a stable `stop_id` and the final position, with retries.

**Silo v2 endpoints**

- `DELETE /playback/{sid}`

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_play_session_service.dart` (`onPlaybackStop`, `stopTranscoding`)
- `packages/playback_silo/lib/src/silo_playback_sessions.dart` (`stopId`, `stopping`)
- `packages/server_silo/lib/src/api/silo_playback_api.dart` (`stopPlayback`)

### How it works

A stop tells Silo the session is over: it stores the final position as the resume point, writes the watch history, stops the remux or transcode and refuses the stream's URL from then on (Playback API, "Progress and stop"). Without it all of that waits until the session expires (45 s to 30 min).

`SiloPlaySessionService.onPlaybackStop` sends `DELETE /api/v2/playback/{session}` with `{installation_id, stop_id, sequence, position, is_paused}`:

- **`stop_id`** is a UUID minted once per session (`SiloPlaybackSession.stopId`) and sent on every retry. Silo's first stop wins; any later one, with any id, replays the stored receipt (`outcome: replayed`), so retrying is always safe.
- **The final sample** is the session's next sequence and the media position the manager reports (10.1), not paused. A session that never reported and is stopped at zero (one the manager dropped before it played, `_cleanupPreemptedSession`) sends **no** sample: a zero would overwrite the item's resume point. (`sequence` and `position` go together or not at all, as the contract asks.)
- **Retries:** no answer, `408`, `429` or `5xx` resend the identical body, backing off 1, 2, 4, 8 s, for up to 30 s (Silo's web player allows the same). `404` or `410` mean the session had already ended. After the stop, sent or not, the session is marked ended and forgotten, so a late progress report or a second stop sends nothing.
- **One stop per session.** On a re-resolve the manager asks for both the stop and the end of the transcode; `stopTranscoding` waits for the stop already on its way instead of sending a second (a transcode ends with its session on Silo), and a second `onPlaybackStop` shares the first.
- **A stream a replan replaced** stops nothing: its session goes on under the new stream (10.12–10.16), which is the one stopped when playback ends.

Audiobooks, which keep their own position (`progress_persistence: client` and `/sync/progress`), are phase 16.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_stop_test.dart` (new, 6 tests): after a sample, the stop is a `DELETE` with the installation id, a UUID stop id, sequence 2 and 600 s, passes `PlaybackStopBody`, and the session is forgotten (no more progress or stops); a dropped stop and a `503` are resent with the identical body (waits 1 s, 2 s); a `404` isn't retried; a stop, the transcode end and a second stop at once send one request; a session dropped before it played stops without a sample (and passes the contract); a stream replaced by a replan stops nothing.
- `playback_silo` 53/53; analyzer: no issues.

**Manual test plan**

- Stop halfway; Silo web shows the resume point (within a second of where you stopped).
- Watch a film to the end (or seek to the last minute and let it finish): Silo's web app shows it watched and it leaves Continue Watching.
- Stop a remux or transcode (xXx with a 4 Mbit/s ceiling): Silo's admin dashboard (Activity / sessions) shows the session gone at once, not after a minute.
- Start a film, and before it shows a frame press back: the film's resume point in Silo's web app is unchanged.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | stop 6/6; `playback_silo` 53/53; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-11"></a>
## 10.11 Resume vs start over

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `021e5e179` | previous step |

**Goal.** Send `start_position` whenever Moonfin passes one; omit it only when Moonfin has no opinion.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart` (`siloStartPosition`)

### How it works

Silo treats a missing `start_position` as a request (protocol v3 §2.2, "Omission is a request, not a default"): it starts at the profile's saved resume point. `0` means start over; any other value starts exactly there. The plan's timeline is cut at that position before planning, so it matters which one Silo gets.

Moonfin always has an opinion. Its resume prompt, the Resume and Play buttons and the resume setting pass a start position to `playItems`; no position means the start (Play from the beginning, the next episode, a trailer); a re-resolve passes the current position. The manager hands the resolver `startTimeTicks` only when the position is past zero, so "none" means "the start" here, never "you decide". If it were left out, *Play from beginning* on a film part way through would resume it on Silo.

So `start_position` is now sent on every start (`siloStartPosition`): the position in seconds, `0` for the start, clamped to the contract's 0 to 31,536,000. 10.6 sent it only for a resume.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_start_test.dart` (2 more; the "no opinion" test now expects `start_position: 0`): `siloStartPosition` gives 0 for none, zero or negative, 600 and 600.5 for their ticks, and the contract's ceiling for an absurd value; a resume at 30:00 and then a start from the beginning send 1800 and 0.
- `playback_silo` 55/55; analyzer: no issues.

**Manual test plan**

- A film part way through (Silo's web app shows its resume point): **Resume** starts there; **Play from the beginning** (or the resume prompt's *Start over*) starts at 0:00, on Silo as on Emby.
- After starting over and watching a minute, stop: Silo's resume point is now about a minute in.
- The next episode from the post-roll / Up Next starts where it does on Emby for the same episode (Moonfin decides, Silo follows).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | start position 2/2; `playback_silo` 55/55; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-12"></a>
## 10.12 Seek outside the produced window

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `805fe87b8` | previous step |

**Goal.** When `can_seek_anywhere` is false, replan on a far seek (needed for progressive remux).

**Silo v2 endpoints**

- `POST /playback/{sid}/replan`

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart` (`StreamReplanner`: `canReplan`, `replan`)
- `packages/playback_silo/lib/src/silo_plan_mapper.dart`, `silo_playback_sessions.dart`
- `packages/server_silo/lib/src/api/silo_playback_api.dart` (`replanPlayback`, `isRetryableReplanError`, `isEndedByServer`)
- `packages/playback_core/lib/src/stream_resolution_result.dart` (`seeksThroughServer`, `reopenAfterPause`), `playback_manager.dart` (seek and resume)

### How it works

A Silo remux is produced as it plays (protocol v3 §4–5). A progressive remux is one chunked response with no byte ranges; an HLS copy remux is FFmpeg's still-growing playlist. Both start at the keyframe before the asked position, so the plan says `can_seek_anywhere: false` and leaves the window's end open: the player has no bytes past what has been produced and nothing to seek in. Every seek goes back to Silo as a **`seek_reanchor` replan**, which answers a new plan for the same session starting there. Without it, a seek on a remux stalls or ends the stream (found in phase 0, §2.1 of the design notes).

**`playback_core`.** `StreamResolutionResult` gains two flags, false/null for Jellyfin and Emby:

- `seeksThroughServer`: the player can't seek this stream itself. `PlaybackManager.seekTo` then shows the target on the seek bar at once and replans at it (`_seekThroughServer`, reason `seek`, through 10.2's path: no stop, same session) instead of seeking the player. A scrub doesn't queue one replan per step: seeks made while one is being served only move its target, and the latest target is served next.
- `reopenAfterPause`: how long the server keeps a paused stream. Silo closes a progressive remux that stops being read (a paused player's buffer fills), so `resume()` after a longer pause replans at the position (as a seek, playing once open) instead of resuming a closed stream, which would end in an error and a failure recovery that rules the remux out. Silo's web player does the same after a minute.
- A replan the server refuses with a `PlaybackRefusedException` is no longer followed by a fresh start (10.2's fallback for other errors): the server answered, and starting again wouldn't change the answer.

**Silo's resolver implements `StreamReplanner`:**

- `canReplan`: the stream is the current one of a live session Moonfin started.
- `replan` sends `POST /api/v2/playback/{sid}/replan` (`PlaybackReplanBody`, validated against the contract in the tests): the operation for the reason (`seek_reanchor`, `track_change`, `quality_change`, `failure_recovery`); the session's `playback_attempt_id` and installation id; the current plan's `plan_id` (as `failed_plan_id`, which Silo checks against the session's current plan) and `plan_attempt_key`; a `plan_attempt_id` the client mints for each plan it adopts; `selected_tracks` exactly as the plan has them (a seek is checked against them; an absent subtitle would mean "off"); the position; the start's capabilities, context, features, quality and ceiling; a fresh `replan_request_id`.
- **Failure recovery** adds the failed plan's key to `attempted_plan_keys` (Silo's loop guard: it won't hand one back; at most 16), counts `attempt_count` (1–8) and sends `failure.classification: playback_error`. Intents (seek, track, quality) send `attempt_count` 1 and no failure, so the current route stays eligible.
- Interrupted requests (no answer, `5xx` such as `replan_capacity_exhausted`, `409 replan_in_progress`) are resent with the same request id for 30 s; Silo replays the committed answer. `410 playback_session_ended` (an administrator ended it) is a refusal, *"Playback was ended on the Silo server."*, and the session isn't started again. `404` (expired, or the server restarted) and `installation_changed` mark the session ended and throw, and the manager starts a new session at the position. A terminal answer is a refusal (10.8).
- The new plan becomes the session's current one, mapped as at start (a new timeline offset, a new URL with its token); a plan on another version reads that version's tracks.

`siloPlanToResolution` sets `seeksThroughServer` from `can_seek_anywhere: false`, and `reopenAfterPause` (1 minute) for `server_remux_progressive`.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_replan_test.dart` (new, 8 tests): a remux seeks through Silo and reopens after a minute's pause, the original doesn't; only the live session's current stream can be replanned; a seek to 30:00 sends a `seek_reanchor` that passes `PlaybackReplanBody` and echoes the attempt, plan id, attempt key, installation, capabilities and the plan's tracks, and the answer's 29:57.5 offset, URL and plan become the session's; two failure recoveries send the failed keys (one, then two), attempt counts 1 and 2, the classification and a new plan attempt id each; a dropped request, `replan_in_progress` and `replan_capacity_exhausted` are resent with one request id; `410` refuses with its message and ends the session; `404` throws for a new start; a terminal refuses.
- `test/playback/playback_manager_seek_replan_test.dart` (new, 6 tests): a seek on such a stream replans at 30:00 and opens the new stream 2 s in (30:00 on the film) without seeking the player or reporting a stop; a scrub of three seeks while the first is served makes two replans (the first and the last target); a stream that seeks itself is seeked by the player; a two-minute pause resumes by replanning at 10:01 and plays; a 30 s pause just resumes; a refused replan isn't followed by a new start and fails the bringup with its message.
- `test/playback/` 856/856; `playback_silo` 63/63; analyzer: no new issues.

**Manual test plan**

- **Seek anywhere on a remux** (xXx on a stereo Mac is a progressive remux; check the playback info says direct stream): seek forward 30 minutes, back 10, and drag the seek bar a long way. Each seek lands where asked after a short load, and the seek bar shows the film's time throughout. The network log shows one `POST …/replan` per settled seek (not one per scrub step) and no new `…/start`.
- Silo's dashboard shows one session for the whole film (it isn't stopped and started per seek).
- **Pause a remux for two minutes**, then play: it continues where it was after a short load (a `…/replan`), no error.
- **Direct play** (The Salt Path): seeking is instant and makes no request to Silo.
- **HLS** (a 4 Mbit/s ceiling): seeking works too (an HLS transcode can seek by itself, an HLS copy remux goes through a replan).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | replan 8/8; manager seek 6/6; `test/playback/` 856/856; `playback_silo` 63/63; analyzer: no new issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-13"></a>
## 10.13 Switch audio track

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `c56e06970` | previous step |

**Goal.** Via replan using the track map from 5.8.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart` (`_replanTracks`, `siloTrackIdentity`)

### How it works

Moonfin numbers every stream of a file in one index space (Jellyfin's `Index`); Silo numbers each kind on its own and names a track `file:<file id>:audio:<ordinal>` (protocol v3 §8). The version mapper keeps the map between the two (5.8, `siloTracksKey`), so a track Moonfin picks can be named to Silo and the one Silo plays named back.

- **At start** (10.6), the audio track Moonfin carries in (its own pick, the series' remembered one, or none) goes as `audio_track_index`. With none, Silo picks the series' preference, then the profile's audio language.
- **Switching in the player.** `PlaybackManager.changeAudioTrack` re-resolves unless the backend can switch within a direct-played file (`supportsDirectPlayAudioSwitch`; AetherEngine can't, media_kit can). With Silo's resolver that re-resolve is a replan (10.2, 10.12) with reason `trackChange`, and `_replanTracks` turns the new index into Silo's identity: `selected_tracks.audio = {id: "file:4598:audio:1", index: 1}` (both given, as Silo checks they agree), operation `track_change`. The subtitle selection is the plan's, as it stands, so changing audio doesn't turn subtitles off (an absent subtitle means "off" to a track change).
- **What Silo does with it.** On the original file the plan claims `client_selected_audio_track_v1` (10.3), so the route stays the original and the player opens the new track itself (the payload's audio index). A remux or transcode carries only the chosen track, so Silo builds a new stream with the new one, in the same session. A track Silo can't play on this route degrades as Silo decides (for example DTS → AAC).
- **Back to Moonfin.** The new plan's `selected_tracks.audio.index` is mapped back to Moonfin's index (`selectedAudioStreamIndex`), so the track menu shows what Silo plays.
- An index that is no audio track of the file keeps the plan's track. Only a track change touches the tracks: a seek or a quality change resends the plan's exactly.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_audio_switch_test.dart` (new, 5 tests), on xXx with a commentary track added (Moonfin streams: DTS 1, commentary 4): the mapping; picking stream 4 sends a `track_change` for `file:4598:audio:1` with index 1 (passes the contract) and maps Silo's answer back to stream 4; a subtitle index keeps the plan's audio; a seek doesn't change tracks; a start carrying stream 4 asks for audio track 1.
- `playback_silo` 68/68; analyzer: no issues.

**Manual test plan**

- A film with two audio tracks (any with a commentary or a second language; Silo's web app lists them on its page):
  - **direct play**: switch the track from the player's menu; the new track plays from where it was, after a short reload on the Mac (AetherEngine reopens the file);
  - **remux or transcode** (a 4 Mbit/s ceiling, or a DTS film on stereo): switch it; playback continues at the same point on the new track, and Silo's dashboard shows the same session with the new audio.
- **Compare with Emby:** the same switch on the same file behaves alike (a reload on transcodes, in place where the player can).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | audio switch 5/5; `playback_silo` 68/68; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-14"></a>
## 10.14 Subtitles: embedded and sidecar

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `f894d8a03` | previous step |

**Goal.** Subtitle inventory → external subtitles, ASS font bundles; off = -1.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_subtitles.dart` (new)
- `packages/playback_silo/lib/src/silo_plan_mapper.dart`, `silo_media_stream_resolver.dart`

### How it works

**Numbering.** Silo addresses a file's subtitles in one *combined* space (protocol v3 §8): its external sidecar files first, then the tracks embedded in the container, then downloaded subtitles, densely from 0 (`file:<file>:subtitle:<n>`); a client must never derive one by counting. Moonfin numbers them inside the file's stream index space (5.8: an embedded track keeps its container index, a sidecar takes a free one). Silo's version answer lists the embedded tracks first and the sidecars (`external: true`) after them (server `buildVersionSubtitleTracks`), so the combined index of a Moonfin stream is its place among the sidecars, or the sidecar count plus its place among the embedded tracks (`siloSubtitleOrder`, `siloSubtitleCombinedIndex`). Downloaded subtitles appear only in a plan's inventory; Moonfin gives them stream indices after the file's highest (`siloSubtitleIndexByCombined`).

**Asking.** A start names the subtitle Moonfin carries in as `subtitle_track_index` (its combined index); subtitles off (`-1`) or no choice send none, which Silo plays without. A track change (10.13's replan) turns `-1` into no subtitle in `selected_tracks` (Silo's "off" for a track change), names a known index, and keeps the plan's selection for anything else (an audio change doesn't touch subtitles).

**The plan → Moonfin** (`siloPlanSubtitles`, through `siloPlanToResolution`):

- **Sidecars.** Every inventory entry with a URL becomes an `ExternalSubtitle` on Moonfin's index: sidecar files, downloaded subtitles and the embedded tracks Silo extracts; on the server with the account's token (10.7), format from the URL suffix (`.vtt`, `.ass`, `.srt`, part of Silo's contract). The playback manager already loads an embedded track's sidecar only when the stream doesn't carry the track (a remux or transcode), and shows it from the file otherwise (the original, with native selection, 10.3). Silo publishes every sidecar whatever the selection, so the whole menu works without a replan for text tracks.
- **Bitmaps** (`.sup` PGS sidecars) are left out: Moonfin loads no external bitmap file, so picking an embedded PGS track on a remux makes the manager ask again (a replan), and Silo burns it in, as on Emby. On the original file it plays from the file.
- **Downloaded subtitles** are added to `mediaStreams` as external text streams (language, label, forced, hearing impaired), so they appear in the menu.
- **The selection** (`selectedSubtitleStreamIndex`): `subtitle.track_id` back to Moonfin's index, or `-1` when the mode is `off`. A track Silo burns in (`mode: burn_in`) is marked `DeliveryMethod: Encode` on this stream's copy of the streams, which is how Moonfin knows not to draw it a second time over the picture.

**Not done:** an ASS track's font bundle (`font_bundle_url`): Moonfin's subtitle renderers take one file, so a sidecar ASS draws with the system's fonts (Silo was told `font_attachments: false` and fidelity `compatible`, 10.3, 10.6). An embedded ASS track on the original file uses its attached fonts.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_subtitles_test.dart` (new, 7 tests), on xXx with two embedded tracks (SubRip at stream 2, PGS at 3) before its sidecar (4), and a plan whose inventory adds a downloaded Spanish track: the combined order is 4, 2, 3 (and xXx's two sidecars 0 and 1); the downloaded track gets index 5; the text sidecars (not the PGS) become external subtitles on 4, 2 and 5 with the token and their identity pins; `off` selects -1; the downloaded track is a stream; a rendered track maps back (combined 1 → 2) and a burnt-in one (→ 3) is marked `Encode` on the copy only; a start names stream 3 as combined 2, and none for off (passes the contract); track changes send no subtitle for -1, combined 3 for the downloaded stream 5, and keep the plan's for none.
- `playback_silo` 75/75; analyzer: no issues.

**Manual test plan**

- **xXx** (two external SRT files): the subtitle menu lists both; pick each, then *Off*. Each shows (or hides) at once, on direct play and on a remux.
- **A film with embedded subtitles** (text and PGS if you have one; Silo's web app lists the tracks):
  - direct play: every track shows, the PGS too, with no reload;
  - remux or HLS (4 Mbit/s ceiling): text tracks show without a reload; picking the PGS track reloads once and the subtitle is burnt into the picture (and Moonfin draws no second copy); switching back to a text track or *Off* reloads and the burnt-in one is gone.
- A title with a subtitle downloaded in Silo's web app (*Search subtitles*): it is in Moonfin's menu and shows.
- Resume a film that had a subtitle on: it comes back with the same subtitle (Moonfin's remembered choice).
- **Compare with Emby:** the same file's subtitles behave alike.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | subtitles 7/7; `playback_silo` 75/75; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-15"></a>
## 10.15 Change quality / bitrate

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `cb2c89c1b` | previous step |

**Goal.** Via replan.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart`, `silo_playback_sessions.dart` (`bandwidthCapKbps`)

### How it works

Moonfin's quality menu sets a bitrate ceiling (`PlaybackManager.changeBitrate(mbps)`; *Auto* / the maximum is none) and re-resolves; since 10.2 that is a replan with reason `qualityChange` and the new ceiling as `maxStreamingBitrate`. Silo's resolver sends it as a **`quality_change`** replan:

- `bandwidth_cap_kbps` is the new ceiling (bits per second / 1000, within the contract's 100–1,000,000), or left out for none, which lifts an earlier one;
- `quality_preference` stays `auto`: Silo picks the rung that fits the ceiling (protocol v3 §10: 80% of the cap earns a resolution class; a source over the cap is re-encoded, one under it is sent as it is). A quality change must name a preference, and `auto` with a cap is that intent. Silo's own menu of rungs (`available_qualities`, `1080p-high`…) isn't shown: Moonfin's menu is in Mbit/s, the same on every server.
- The session remembers the ceiling (`SiloPlaybackSession.bandwidthCapKbps`, first from the start, which sends the playback setting's ceiling), and every later replan of the session (a seek, a track change) sends it, so a seek doesn't lift it.

A quality change keeps the current route eligible (it is an intent, not a failure), so with no ceiling Silo goes back to the original or the remux it planned before. The answer is mapped as any plan: a transcode shows `ContainerBitrateExceedsLimit` from `quality_bandwidth_cap` / `bandwidth_cap_applied` in the playback info. The manager's request to force a transcode for a ceiling (`enableDirectPlay: false`) means nothing to Silo, which decides from the ceiling.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_quality_test.dart` (new, 3 tests): a 4 Mbit/s ceiling sends a `quality_change` with `auto` and 4000 kbps (passes the contract), and the answered HLS transcode maps to a transcode with `ContainerBitrateExceedsLimit`; a seek afterwards still sends 4000; a start with an 8 Mbit/s setting sends 8000, and a quality change to none sends no ceiling.
- `playback_silo` 78/78; analyzer: no issues.

**Manual test plan**

- Direct play a 1080p film, then pick 4 Mbit/s in the player's quality menu: playback continues at the same point after a short load, as a transcode (playback info: transcode, bitrate limit); Silo's dashboard shows the same session now transcoding.
- Seek: the ceiling holds (still a transcode).
- Pick *Auto* (or the maximum): it goes back to direct play at the same point.
- A 4K film (The Salt Path 2160p) with a 10 Mbit/s ceiling: Silo plays its 1080p version or a lower rung (its admin dashboard shows which).
- **Compare with Emby:** the same choices on the same file.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | quality 3/3; `playback_silo` 78/78; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

<a id="step-10-16"></a>
## 10.16 Pick a version

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `1b39d75a1` | previous step |

**Goal.** Explicit version choice sets `allow_alternate_versions: false`.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart` (`_SiloFile.explicit`, `_playable`)

### How it works

Silo may play another version than the one asked for: with alternate versions allowed (the default), a start or replan that can't play the requested file (a 4K version the account may not transcode, an unreadable file, a bitrate limit) tries the item's other versions. When the viewer picked a version, that's the wrong answer: they asked for that file. Servers with `fixed_media_file_v1` (this one has it) take `allow_alternate_versions: false` on the start, which keeps the whole attempt on the requested file through every replan (quality, track, seek, recovery) and answers a refusal (10.8) instead of substituting a version with a different timeline (Playback API, "Start").

- **When it is sent.** Moonfin passes a version (`mediaSourceId`) when the viewer picks one in the detail page's version picker, and also on every re-resolve (the version it last played). So the start pins the file only when it isn't the item's default (its first version) and the item has others: a picked 1080p version of The Salt Path is kept to 1080p, a plain Play (or a pick of the default) leaves Silo free to fall back. A single-version item is never pinned. On a server without `fixed_media_file_v1` nothing is sent and the file is only requested.
- **Replans** need nothing more: Silo keeps the choice for the attempt and refuses to relax it.
- The capabilities read once per start now answers both the installation id and the feature (`_playable`).

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_version_test.dart` (new, 5 tests), on The Salt Path (2160p `4603` first, 1080p `4602`): picking 1080p starts `4602` with `allow_alternate_versions: false` (passes the contract); no pick or a pick of the default starts `4603` without it; a server without `fixed_media_file_v1` gets the file but not the flag; a single-version film is never pinned.
- `playback_silo` 83/83; analyzer: no issues.

**Manual test plan**

- The Salt Path: play each version.
  - Pick the 1080p version in the detail page's version picker and play: the playback info shows the 1080p file; seek and change the quality: it stays on the 1080p file.
  - Pick the 2160p version and play: the 2160p file (or Silo's refusal, if this account may not play it, rather than a silent switch to 1080p).
  - Plain Play (no pick): Silo's default version, and Silo may fall back to the other one if it can't play it.
- Silo's dashboard shows the file each session plays.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | versions 5/5; `playback_silo` 83/83; analyzer: no issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: the phase 10 test list passed |
| | | | | |

---

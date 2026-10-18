# Phase 12: Other platforms and casting

[← Roadmap](../ROADMAP.md)

One backend or cast target per commit; each declares its own honest codec evidence and sends auth correctly.

**Phase done when:** Plays on every platform you own (Android TV, Fire TV, iOS, Apple TV, web) and casts.

---

<a id="step-12-1"></a>
## 12.1 Android / Android TV / Fire TV (Media3)

| Status | Commit | Depends on |
|---|---|---|
| ◐ Device checks in 17.5 | `0c0028bfe` | previous step |

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
| ◐ Device checks in 17.5 | `b5b653fe3` | previous step |

**Goal.** Silo playback on every Apple platform with the player's honest traits and the stream's headers.

**Where in Moonfin**

- `lib/playback/silo_playback_environment.dart`: tvOS plays with AetherEngine's traits
- `packages/playback_silo/lib/src/silo_capabilities_translator.dart`: the traits' notes
- (`lib/playback/appletv_backend.dart`, `lib/playback/aether_backend.dart`, `tvos/Runner/Playback/AppleTvVideoChannel.swift`: unchanged; see below)
- (`lib/ui/screens/playback/appletv_player_host_screen.dart`: its trickplay, segments and chapters came with 11.1–11.3; its tile headers are 12.7)

### How it works

All three Apple platforms play through **AetherEngine**: the macOS and iOS backend (`AetherBackend`) and the tvOS one (`AppleTvBackend`, whose native view wraps the same engine, `AetherPlayerWrapper`). AVPlayer only plays trailers and previews.

- **macOS and iOS** have had AetherEngine's traits since 10.4 (any audio track, embedded and bitmap subtitles with styling and fonts, HDR and Dolby Vision presented through the system, which maps them to an SDR screen). The Mac is what phase 10 and 11 were tested on.
- **tvOS** claimed nothing beyond its profile until now. It now sends the same traits, since it is the same engine. Its form factor is `tv` and platform `tvos` (10.4).
- **Headers.** Both backends hand the stream's headers to the engine at open (`SourceConfiguration.headers` → the engine's `httpHeaders`), which sends them on every request for that stream, HLS segments and sidecars included. Nothing changed there.
- **Display HDR** stays unknown on Apple: nothing in Moonfin asks an Apple display what it shows yet (that would be a native call such as `AVPlayer.eligibleForHDRPlayback`). With HDR unknown, Silo makes no native HDR claim. An original HDR file still plays as it is, since the engine presents it through the system; a remux of one is tone-mapped by Silo. Raise later if Apple TV users see HDR remuxes come out SDR.
- **Evidence** stays `declared`. Silo's `platform_attested` tier (VideoToolbox) needs per-codec decode entries, which Moonfin doesn't build; like Android's `exact` (12.1), that is a follow-up once it can be tested on the devices.

### Testing

**Automated tests**

- `test/playback/silo_playback_environment_test.dart` (5 tests, 1 new): iOS plays through AetherEngine's traits, as Apple, with no display HDR. tvOS is a build flag (`MOONFIN_TVOS`), so its branch can't be switched on in a test; it shares the macOS/iOS line.

**Manual test plan**

The Mac was tested in phases 10 and 11. iOS and Apple TV go to the deferred platform checks in 17.5 unless Brady has the devices at hand.

- a. iPhone or iPad: xXx, Young Justice 1x01 and an HDR film start, seek, resume, switch audio and subtitles as on the Mac.
- b. Apple TV: the same, with the remote; skip intro, Next Up and previews on the scrub bar (11.1, 11.2, 11.4).
- c. Apple TV with an HDR TV: an HDR10 or Dolby Vision original direct plays.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | environment 5/5; analyzer: no issues in the changed files |
| 2026-10-17 | iOS, tvOS | — | Deferred | checks a–c in 17.5 |
| | | | | |

---

<a id="step-12-3"></a>
## 12.3 Web

| Status | Commit | Depends on |
|---|---|---|
| ◐ Deferred by Brady | `8e085e7e0` | previous step |

**Goal.** `isTypeSupported` evidence; query token because `<video>` can't send headers.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_capabilities_translator.dart`: `SiloPlayerTraits.web`, the `sendsRequestHeaders` trait
- `packages/playback_silo/lib/src/silo_plan_mapper.dart`: `siloAuthorizeUrl(…, allMedia:)`, `siloPlanToResolution(…, tokenInEveryUrl:)`
- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart`: asks for it when the player sends no headers
- `lib/playback/silo_playback_environment.dart`: the web's traits
- (`lib/playback/html_video_backend_web.dart`: unchanged)

### How it works

On the web Moonfin plays through the browser's `<video>` element, with hls.js for HLS where the browser has no native HLS (`HtmlVideoBackend`). Its device profile already comes from the browser's own answers (`MediaSource.isTypeSupported`, `canPlayType`; `web_playback_capabilities.dart`). Silo calls that evidence tier `declared` (boolean support statements, flat codec lists), which is what the translator sends on every platform, so the profile needed no change.

What it can't do is send headers: a media element sends only cookies, and hls.js is attached without a header hook (`MoonfinHlsBridge.attach(video, url)`). Until now only Silo's `/api/v2/stream/` URLs carried the account's token (10.7). An HLS stream (`/api/v2/playback/transcode/…`) went by headers alone, so on the web every transcode would have been refused.

- **A new trait, `sendsRequestHeaders`** (true by default). `SiloPlayerTraits.web` has it false and claims nothing else: a browser picks no audio track of a file, draws no embedded subtitles (sidecars are loaded as text tracks) and maps no HDR.
- **The token in every media URL.** For a player without headers, the resolver asks `siloPlanToResolution` for `tokenInEveryUrl`, and `siloAuthorizeUrl(…, allMedia: true)` adds `token=` to Silo's HLS routes too. Silo accepts it there ("media-element fallback for the account bearer token" on the manifest, segment and subtitle routes) and copies a manifest's query onto every playlist and segment URI, so each request carries it. It still goes only to the server's own origin and never onto artwork. Replans (seeks, track changes) do the same.
- **The environment** sends the web's traits first, since a browser on a phone also reports the phone's platform; form factor and platform are `web` (10.4).
- The headers are still set on the resolution: a backend that can send them (media_kit, if the web falls back to it) does.

**Open:** the web app loads Silo from another origin, so Silo must allow Moonfin's origin (CORS) for the API and the media routes. Silo's web app is served from Silo itself, so this hasn't been exercised. If the browser's console shows CORS refusals, it's a Silo setting or a follow-up for Silo.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_stream_auth_test.dart` (2 new): a player without headers gets `token=` on an HLS manifest URL from a start; `siloAuthorizeUrl(…, allMedia:)` adds it to `/api/v2/playback/` routes and never to artwork or another origin.
- `silo_capabilities_translator_test.dart` (1 new): the web's traits claim nothing beyond the profile, send no headers, and fit the contract. `playback_silo` 88/88.

**Manual test plan**

On the Mac, run Moonfin for the web (`flutter run -d chrome`, or Brady's usual web build) and sign in to Silo.

- a. Play xXx (a remux: progressive with `token=`), an original MP4 (direct play), and something that transcodes (a high bitrate with *Max streaming bitrate* lowered): each starts and seeks. The network tab shows `token=` on the media URLs, on the HLS manifest and on its segments.
- b. Subtitles: an external SRT sidecar shows.
- c. The browser console: no CORS errors on Silo's API or media. If there are, note which requests.
- d. Images (posters, backdrops) load; none carries a token.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | stream auth 2 new, translator 1 new; `playback_silo` 88/88; analyzer: no issues |
| 2026-10-18 | macOS (web) | `bd9d59ea` | Deferred | Brady deferred the web build; checks a–d are in 17.5 |
| | | | | |

---

<a id="step-12-4"></a>
## 12.4 Chromecast

| Status | Commit | Depends on |
|---|---|---|
| ◐ Device checks in 17.5 | `952e75808` | previous step |

**Goal.** Receiver-specific capabilities; token query on the stream URL; the Silo session kept alive while the receiver plays.

**Where in Moonfin**

- `packages/playback_silo/lib/src/silo_capabilities_translator.dart`: `SiloPlayerTraits.castReceiver`
- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart`: a nearly fresh token for a player that carries it in its URLs
- `lib/playback/silo_playback_environment.dart`: `siloReceiverEnvironment`
- `lib/data/services/cast/cast_session_reporter.dart` (new): `CastSessionReporter`, `CastServerPlayback`, `CastServerPlaybackSource`
- `lib/data/services/cast/cast_service.dart`: reports a cast that needs it
- `lib/data/services/cast/google_cast_provider.dart`: the receiver's environment, one item at a time on Silo, the session to report

### How it works

Casting hands the receiver a URL: the receiver loads the stream itself, with its own player, and the phone only controls it. Moonfin resolves the stream on the phone with the receiver's device profile (`chromecastDeviceProfile`). For Silo four things needed changing:

- **The receiver's start.** The cast resolver now describes the receiver, not the phone (`siloReceiverEnvironment('chromecast', manufacturer: 'Google')`): form factor `tv` and `SiloPlayerTraits.castReceiver`. That means no headers (12.3: `token=` on every media URL, HLS included), and **no progressive remux**: the receiver's player seeks by byte ranges, which a chunked remux has none of, so Silo plans the original file (ranges) or HLS. It picks no audio track and draws no embedded subtitles, so Silo burns or extracts them as needed. Before this, a Silo cast described the phone (`desktop`, no traits), and an HLS stream had no token, so the receiver would have been refused.
- **Keeping the session alive.** A Silo session that hears no progress for 45 seconds is ended (10.9), and its stream stops being served. On the phone the playback manager reports; for a cast nothing did. `CastSessionReporter` now reports what the receiver does, every 10 s, through Silo's session service (`SiloPlaySessionService`): the receiver's position plus the stream's timeline offset (10.1), and paused or not, from the cast service's receiver state (its events and polling); before the receiver has said anything (still loading) it is kept alive at the start position. It stops the session, with the last position as Silo's resume point, when the cast ends, the receiver plays another item, or it goes idle after playing; a new cast stops the one before. The cast service starts it for a provider that hands over its last cast (`CastServerPlaybackSource.takeServerPlayback`), and only Silo's need it (`castNeedsSessionReports`). Jellyfin and Emby casts are as before.
- **One item at a time on Silo.** The provider resolves every queued item before it starts the cast. On Silo each resolve opens a session, and every one but the playing one would end 45 seconds later, so the receiver's later items would be refused. On Silo the cast is the item alone; the rest of a queue isn't sent.
- **The token's life.** The receiver's URLs carry the token they were made with, and Silo checks it on every request. A player that carries the token (the web, a receiver) now gets a nearly fresh one: anything past a tenth of its life is refreshed before the stream is described, so a cast works for close to the token's full life (an hour on this server).

**Open:** a cast longer than the token's life (a film over an hour) will be refused once the token expires: the receiver keeps the URL it was given. Fixing that needs either a replan with a new URL before expiry (the receiver would have to load it, interrupting playback briefly) or Silo accepting the signed stream reference (`st`) alone for a live session. To raise with Brady and Silo after a test.

### Testing

**Automated tests**

- `test/data/services/cast/cast_session_reporter_test.dart` (new, 4 tests): the receiver's position on the film's timeline (a 9:53 remux offset), paused or not, the start position before the receiver says anything; a stop at the last position when the cast ends, nothing after; idle before playing keeps going, idle after playing or another item stops; a new cast stops the one before.
- `packages/playback_silo/test/silo_capabilities_translator_test.dart` (1 new): a receiver has no progressive remux (`player_has_no_progressive_remux`), claims nothing on the original, and fits the contract.
- `packages/playback_silo/test/silo_stream_auth_test.dart` (1 new): with 45 minutes left a phone keeps its token and a receiver gets a new one; 57 minutes is fresh enough. `playback_silo` 90/90.
- `chromecast_device_profile_test.dart` and the player tests that build a cast service pass.

**Manual test plan**

Casting needs the app on an Android or iOS device and a Chromecast (or a Google TV), so this goes to the deferred platform checks in 17.5 unless Brady has them at hand.

- a. Cast xXx from its detail page: it plays on the TV. The phone's log shows the cast URL with `token=` and a start with form factor `tv`.
- b. Pause, seek, resume from the phone: the TV follows. Silo's web app (Activity/Sessions) shows the session staying alive past a minute.
- c. Stop the cast at some point: Silo's web app shows the resume point there, and Moonfin's Continue Watching too.
- d. Cast a film that transcodes (lower *Max streaming bitrate*): HLS plays on the TV.
- e. Cast an episode with a queue: only that episode plays (on Silo).
- f. Optional: a cast longer than an hour, to see whether the token's expiry stops it (open above).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | reporter 4/4; translator, stream auth 1 new each (`playback_silo` 90/90); cast and player tests pass; analyzer: no issues in the changed files |
| 2026-10-17 | Chromecast | — | Deferred | checks a–f in 17.5 |
| | | | | |

---

<a id="step-12-5"></a>
## 12.5 AirPlay

| Status | Commit | Depends on |
|---|---|---|
| ◐ Device checks in 17.5 | `aa84deebe` | previous step |

**Goal.** AirPlay from iOS to an Apple TV with Silo's stream, its token, and its session kept alive.

**Where in Moonfin**

- `lib/data/services/cast/airplay_provider.dart`: the receiver's environment, no second token for Silo, the session to report

### How it works

Moonfin's AirPlay (iOS only) loads the stream into a phone-side AVPlayer and shows the system route picker; once an Apple TV is picked, the Apple TV fetches the stream itself. So it is a receiver like a Chromecast (12.4), and gets the same treatment:

- **The receiver's start**: `siloReceiverEnvironment('airplay', manufacturer: 'Apple')` with the AirPlay device profile (`airPlayDeviceProfile`): no headers, so `token=` on every media URL, and no progressive remux (AVPlayer seeks by byte ranges).
- **No second token.** The provider appends the account's token to the stream URL for Jellyfin and Emby. On Silo the resolver already did, only where Silo takes one and only on Silo's own origin, so the provider no longer appends it there. Before, a Silo URL got the token twice, and a proxy node's URL would have been handed the account's token.
- **The session** is reported like a Chromecast's (`CastSessionReporter`, 12.4) from the AirPlay events the cast service already reads (state and position), and stopped when the AirPlay session ends.
- AirPlay casts one item at a time already. The start is resolved from the beginning and the Apple TV seeks to the resume point itself (as before); on an original file that is a byte-range seek, and on HLS it is within what Silo has produced.

### Testing

**Automated tests**

- No new test: the provider's Silo branch is covered by the shared pieces (receiver traits and token handling, 12.3 and 12.4; the reporter, 12.4). Its native channel can't run in a unit test.

**Manual test plan**

Needs an iPhone or iPad and an Apple TV, so it goes to the deferred platform checks in 17.5 unless Brady has them at hand.

- a. On iOS, cast xXx to an Apple TV with AirPlay: it plays; the stream URL carries one `token=`.
- b. Pause, seek, resume from the phone; Silo's web app keeps the session past a minute; stopping keeps the resume point.
- c. Resume a film part way through over AirPlay: it starts at the resume point.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | analyzer: no issues in the changed files |
| 2026-10-17 | iOS + Apple TV | — | Deferred | checks a–c in 17.5 |
| | | | | |

---

<a id="step-12-6"></a>
## 12.6 DLNA

| Status | Commit | Depends on |
|---|---|---|
| ◐ Device checks in 17.5 | `35d853139` | previous step |

**Goal.** Casting to a DLNA renderer with Silo's stream, its token, and its session kept alive.

**Where in Moonfin**

- `lib/data/services/cast/dlna_provider.dart`: the receiver's environment, the session to report

### How it works

A DLNA renderer (a smart TV, an AV receiver) is handed the stream URL and fetches it itself, so it gets the receiver treatment of 12.4:

- **The start** describes a receiver (`siloReceiverEnvironment('dlna')`): no headers, so `token=` on every media URL, and no progressive remux, since renderers seek by byte ranges.
- **The session** is reported from the renderer's state events (`PLAYING`, `PAUSED_PLAYBACK` and its position, which the native DLNA controllers already send) through `CastSessionReporter`, and stopped when the cast ends.
- **The profile.** DLNA has no receiver profile in Moonfin: the provider resolves with the phone's own (`DeviceProfileBuilder.build()`), for every server, as before. A renderer that can't play what the phone can (HEVC, MKV, HLS: many can't) fails on the TV. That isn't Silo-specific; a DLNA receiver profile would be an upstream change.

### Testing

**Automated tests**

- No new test: the Silo branch uses the shared receiver traits, token handling and reporter (12.3, 12.4). The native DLNA channel can't run in a unit test.

**Manual test plan**

Needs an Android or iOS device and a DLNA renderer, so it goes to the deferred platform checks in 17.5 unless Brady has them at hand.

- a. Cast an MP4 film (H.264/AAC) to a DLNA TV: it plays; the URL carries `token=`.
- b. Pause, seek, resume from the phone; the session stays alive past a minute; stopping keeps the resume point.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | cast tests pass; analyzer: no issues in the changed files |
| 2026-10-17 | DLNA | — | Deferred | checks a–b in 17.5 |
| | | | | |

---

<a id="step-12-7"></a>
## 12.7 Trickplay and image headers in the player screens

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `dfec537ab` | previous step |

**Goal.** Replace the hand-built `MediaBrowser Token=` headers with `serverAuthHeaders()` (or none for signed URLs).

**Where in Moonfin**

- `lib/data/utils/trickplay_headers.dart` (new): `trickplayImageHeaders`
- `lib/ui/screens/playback/video_player_screen.dart` (the sheet prefetch and the preview tile)
- `lib/ui/screens/playback/appletv_player_host_screen.dart` (the sheets handed to the native scrubber)
- `lib/ui/widgets/video_mini_player.dart` (the mini player's preview tile)

### How it works

The players loaded seek-preview sheets and frames with a header written by hand, `Authorization: MediaBrowser Token="…"`, for every server. That is Jellyfin's legacy form. Emby's own scheme is `Emby`, and Silo's sheet URLs are signed and need nothing: a stray `MediaBrowser` authorization next to them was at best ignored, and it put the account's token beside signed artwork, which Moonfin otherwise never does (10.7).

`trickplayImageHeaders(client)` now builds them in one place:

- **Jellyfin and Emby** get the server's own authorization through `server_core`'s `serverAuthHeaders` (the right scheme with the device fields and the token, as every other request to them carries), plus the app's image User-Agent where the Flutter image loader sent it before.
- **Silo** gets none beyond the User-Agent: the URL carries its signature (11.2).
- The tvOS host hands the same headers to its native scrubber, without the User-Agent, as before.

The four call sites are the only hand-built authorization headers left in the player screens.

### Testing

**Automated tests**

- `test/data/utils/trickplay_headers_test.dart` (new, 2 tests): Jellyfin's `MediaBrowser` and Emby's `Emby` authorization with the token, with or without the User-Agent; Silo's none.
- The trickplay model and player tests pass.

**Manual test plan**

- a. On the Mac, scrub Young Justice 1x01 on Silo: previews still show (11.2).
- b. Regression: on Emby, scrub an episode with previews (BIF, or trickplay if the server has it): previews still show.
- c. Apple TV: the scrubber's previews on Silo and on Emby (deferred to 17.5 with 12.2).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | trickplay headers 2/2; analyzer: no issues in the changed files |
| 2026-10-18 | macOS | `bd9d59ea` | Pass | Brady: previews on the Mac pass ("previews work great") |
| | | | | |

---

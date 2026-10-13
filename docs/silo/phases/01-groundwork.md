# Phase 1: Groundwork

[← Roadmap](../ROADMAP.md)

Make Silo a server type the code knows about. Jellyfin and Emby users see no change. Each step must build and keep every Jellyfin and Emby test passing.

**Phase done when:** Adding your Silo server is recognised as Silo and lands on a sign-in screen that can't sign in yet. Jellyfin and Emby behave exactly as before.

---

<a id="step-1-1"></a>
## 1.1 `ServerType.silo`

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `5194df8` | 0.4 |

**Goal.** Add the enum value, `productName`, `tokenQueryParam` (`token`), and Silo detection in `detect()`. Fix each exhaustive `switch` the compiler flags with a safe default.

**Where in Moonfin**

- `packages/server_core/lib/src/models/server_type.dart`
- the 8 exhaustive `switch (serverType)` sites listed below

**Earlier work to port:** silo-1 `server_type.dart` (without the build flag: `detect()` no longer takes `allowSilo`)

### How it works

Silo becomes the third value of `ServerType`, the enum every layer of Moonfin uses to pick a backend. This step adds the value and keeps the app compiling and behaving exactly as before; nothing can create a Silo server yet.

**`packages/server_core/lib/src/models/server_type.dart`**

- `ServerType.silo` is added after `jellyfin` and `emby`. Saved servers store the enum by `name` (`lib/auth/models/server.dart`), so existing entries are unaffected and `"silo"` round-trips.
- `tokenQueryParam` becomes a `switch` and returns `token` for Silo. Silo accepts the access token as `?token=` only on media requests that can't send headers (stream and subtitle URLs). Most Silo URLs are already signed and must not get a token, so the callers that append it (`lib/util/server_url.dart`, casting, theme music…) get a per-URL Silo rule in later steps rather than here.
- New `productName` (`Jellyfin` / `Emby` / `Silo`) for user-facing text such as the add-server error (step 1.17).
- `detect()` checks for "silo" in the product name before the Jellyfin and Emby checks. Silo's **Jellyfin-compatible** listener (port 8096) reports `ProductName: "Jellyfin Server"`, so a server added on that port is still a Jellyfin server; only the native API is Silo. The native API isn't probed until step 1.4.

**The eight exhaustive `switch`es the compiler flagged.** Dart refuses to compile a `switch` over an enum that misses a value, which is how every place needing Silo handling was found:

| Where | Silo case in this step | Replaced in |
|---|---|---|
| `media_server_client_factory.dart` `_createRawClient` | throws `UnsupportedError('Silo servers are not supported yet')` | 1.9 (`SiloMediaServerClient`, built in 1.5) |
| `playback_module.dart`, `media_bar.dart`, the AirPlay, DLNA and Google Cast providers (stream resolver) | same throw | 1.9 (`playback_silo` plugin, built in 1.8) |
| `socket_handler.dart` (websocket client) | same throw | 1.9 (idle Silo socket), 13.2 (events socket) |
| `server_type_icon.dart` | generic `Icons.dns_outlined` glyph | 1.11 (Silo icon) |

The throws are unreachable: every other switch needs a `MediaServerClient`, and the factory is the only way to get one, so a Silo client can't exist until 1.9. Nothing produces a Silo `Server` in the first place (the probe only reads `/System/Info/Public`, which Silo's native site answers with HTML). The icon is the exception because a widget must never throw: server lists render it for any saved entry.

### Testing

**Automated tests**

- `packages/server_core/test/server_type_test.dart` (new): Silo product names detected; "Jellyfin Server" (Silo's compat listener) stays Jellyfin; Emby and Jellyfin rules unchanged; `tokenQueryParam` and `productName` per type.
- `test/server_model_test.dart`: a saved Silo server round-trips its type.
- `test/ui/widgets/server_type_icon_test.dart` (new): every server type renders without throwing; Silo shows the generic glyph.

**Manual test plan**

- `flutter run -d macos`: the app starts; the server list shows your Jellyfin/Emby servers with their usual icons.
- Sign in to Emby, open a movie, play it for a few seconds, stop. Same on a Jellyfin server if you have one.
- Cast or AirPlay menu still lists targets for an Emby item (the resolver switch changed there).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | `dart analyze` on the app and core packages: 0 errors, 0 warnings (same as before). Tests: server_core 50/50, app 4,272 passed, 1 skipped, 0 failed. |
| 2026-10-13 | macOS | — | Pass | Brady: app runs, Emby playback works |

---

<a id="step-1-2"></a>
## 1.2 Silo capabilities in `FeatureDetector`

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 1.1 |

**Goal.** Add `supportsLiveTv`, `supportsMusic`, `supportsPlaylists`, `supportsInstantMix`, `supportsAdmin`, `supportsMoonfinPlugin` and `supportsProfiles`, and decide each existing flag for Silo. Nothing reads the new flags yet.

**Where in Moonfin**

- `packages/server_core/lib/src/feature/feature_detector.dart`

**Earlier work to port:** silo-1 `feature_detector.dart` and its test (changed: Silo flags start off until implemented)

### How it works

`FeatureDetector` (`packages/server_core/lib/src/feature/feature_detector.dart`) is how the UI asks "can this server do X?" before showing a button, row or tab. This step teaches it about Silo and adds the flags phase 4 needs to hide what Silo doesn't have. **No code reads the new flags yet**, and every existing flag returns exactly what it did before for Jellyfin and Emby.

**Rule for Silo: a flag says what Moonfin can do with the server today, not what Silo can do.** A feature Silo offers but Moonfin hasn't implemented stays `false` and is switched on by the step that implements it. Otherwise the first playable build (phase 10) would turn on trickplay and skip-intro calls that don't exist yet. (The first-pass branch declared them `true` up front; this is the main difference from the ported code.)

| Flag | Jellyfin | Emby | Silo | Silo note |
|---|---|---|---|---|
| `supportsLiveTv` *(new)* | ✓ | ✓ | ✗ | Never: Silo has no Live TV/DVR by design |
| `supportsMusic` *(new)* | ✓ | ✓ | ✗ | Never: no music libraries |
| `supportsPlaylists` *(new)* | ✓ | ✓ | ✗ | Never: personal collections are the nearest thing |
| `supportsInstantMix` *(new)* | ✓ | ✓ | ✗ | Never |
| `supportsAdmin` *(new)* | ✓ | ✓ | ✗ | Never: Silo is administered in its own web app |
| `supportsMoonfinPlugin` *(new)* | ✓ | ✓ | ✗ | Never: the `/Moonfin/*` plugin is Jellyfin/Emby only |
| `supportsProfiles` *(new)* | ✗ | ✗ | ✗ | On with profile sign-in (phase 3) |
| `supportsTrickplay` | ✓ | ✗ | ✗ | On in 11.2 |
| `supportsMediaSegments` | ✓ | ✗ | ✗ | On in 11.1 |
| `supportsSkipSegments` | ✓ | ✓ | ✗ | On in 11.1 |
| `supportsQuickConnect` | ✓ | ✗ | ✗ | On in 14.3 (Silo device sign-in) |
| `supportsClientLog` | ✓ | ✗ | ✗ | Optional, 13.5 |
| `supportsSyncPlay`, `supportsLyrics`, `supportsBifTrickplay` | as before | as before | ✗ | Never |
| `supportsJellyseerr` | ✓ | ✓ | ✓ | Direct Seerr works without the Moonfin plugin (4.9) |

`supportsAdmin` is `true` for Emby to match today's behaviour (the admin panel's own Jellyfin-only checks are untouched); it only exists so phase 4 can hide the entry for Silo.

### Testing

**Automated tests**

- `packages/server_core/test/feature_detector_test.dart` (new, 6 tests): every existing flag unchanged for Jellyfin and Emby; new flags on for both; the "never" flags off for Silo; the "not yet" flags off for Silo, each tagged with the step that turns it on; Seerr stays available.

**Manual test plan**

- No visible change. Optional: launch the app and play something on Emby with skip-intro to confirm the skip button still appears (`supportsSkipSegments` was rewritten).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | server_core 56/56; app tests that use the detector (media segment service, Apple TV prompt controller) 40/40; analyzer 0 errors/warnings |
| | | | | |

---

<a id="step-1-3"></a>
## 1.3 Silo request headers

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `buildSiloRequestHeaders()`: `Authorization: Bearer`, `X-Profile-Id`, `X-Profile-Token`, `X-Silo-Device-Id/-Name/-Platform`, `X-Silo-Client(-Version)`, sanitised and length-clamped (a bad device id gets a 422).

**Where in Moonfin**

- `packages/server_core/lib/src/network/auth_header.dart`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- `auth_header_test.dart`: sanitising, clamping, device-id character set

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-4"></a>
## 1.4 Detect Silo in the server probe

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Try `/api/v2/system/info` before the Jellyfin and Emby paths, then build `Id`/`ServerName`/`Version` from identity, branding and setup. Reject the HTML 200 that the native host returns for `/System/Info/Public`.

**Silo v2 endpoints**

- `GET /system/info`
- `GET /system/identity`
- `GET /theme/branding`
- `GET /system/setup`

**Where in Moonfin**

- `packages/server_core/lib/src/network/server_probe.dart`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- `server_probe_test.dart`: Silo detected; HTML 200 rejected; sub-path base URL kept; Jellyfin-compat port still detected as Jellyfin

**Manual test plan**

- Add `silo.snowystreams.com`. The server tile shows your Silo server name.
- Store the **v2** identity id, not the v1 health id.
- Compare with Emby: Add your Emby server again and confirm it is still detected as Emby.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-5"></a>
## 1.5 `server_silo` package skeleton

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Create the package, `SiloMediaServerClient` (Dio set up like Emby, Silo headers on every request), and placeholder APIs that throw a readable `SiloNotImplementedError` naming the step that replaces them. Live TV and Instant Mix are permanently empty.

**Where in Moonfin**

- `packages/server_silo/**`
- `pubspec.yaml`
- `pubspec.lock`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- `silo_media_server_client_test.dart`: headers present; placeholders name their step

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-6"></a>
## 1.6 Silo error responses (Problem Details)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Parse RFC 7807 Problem Details into `SiloApiException(code, status, detail, retryAfter)`, including bodies served as `text/plain`.

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_problem.dart`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- Problem body parsed; plain-text JSON parsed; non-JSON body falls back to status text

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-7"></a>
## 1.7 `SiloSystemApi`

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Public info, system info and ping, returned in the shape the app already reads.

**Silo v2 endpoints**

- `GET /system/info`
- `GET /system/identity`
- `GET /theme/branding`
- `GET /system/setup`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_system_api.dart`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- fixture → `{Id, ServerName, Version, ProductName: 'Silo'}`

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-8"></a>
## 1.8 `playback_silo` package skeleton

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Plugin, a resolver that refuses with a clear "Silo playback isn't available yet" message, and a no-op session service.

**Where in Moonfin**

- `packages/playback_silo/**`

**Earlier work to port:** silo-1

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

<a id="step-1-9"></a>
## 1.9 Wire Silo into the app's factories

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Client factory, playback module, media bar, the three cast providers and the websocket factory (idle Silo client).

**Where in Moonfin**

- `lib/data/services/media_server_client_factory.dart`
- `lib/di/modules/playback_module.dart`
- `lib/ui/widgets/media_bar.dart`
- `lib/data/services/cast/*_provider.dart`
- `lib/data/services/socket_handler.dart`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Adding the Silo server no longer crashes at the factory.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-10"></a>
## 1.10 Add the Silo packages to CI

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Add `server_silo` and `playback_silo` to the package list in the build workflow so their analyzer and tests run on PRs.

**Where in Moonfin**

- `.github/workflows/build.yml`

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

<a id="step-1-11"></a>
## 1.11 Silo server icon

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** A simple original glyph in `ServerTypeIcon` (not Silo's trademarked logo).

**Where in Moonfin**

- `lib/ui/widgets/server_type_icon.dart`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Server list shows the Silo glyph on phone and TV layouts.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-12"></a>
## 1.12 Shared auth headers for hand-built requests

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** A `serverAuthHeaders()` helper (via a separate `ProfileAwareClient` interface so the test fakes stay untouched). Move the bitrate probe and retro-artwork transport onto it.

**Where in Moonfin**

- `packages/server_core/lib/src/profile_aware_client.dart`
- `lib/playback/auto_bitrate_service.dart`
- `lib/data/services/retro_artwork/retro_artwork_transport.dart`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Jellyfin and Emby: auto-bitrate still measures; retro artwork still loads.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-13"></a>
## 1.13 Skip the bandwidth probe on Silo

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Silo has no speed-test route. Skip the probe and leave the estimate to passive measurement.

**Where in Moonfin**

- `lib/playback/auto_bitrate_service.dart`

**Earlier work to port:** silo-1

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

<a id="step-1-14"></a>
## 1.14 Safer redirects for Silo sessions

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Only follow same-origin redirects with credentials attached, and only upgrade http→https on 443 or the same port.

**Where in Moonfin**

- `packages/server_core/lib/src/network/redirect_interceptor.dart`

**Earlier work to port:** silo-1 (commits 08bb227, 59c87ef)

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- cross-origin redirect drops auth headers; http→https upgrade rules

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-15"></a>
## 1.15 No public user list on Silo

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Silo has no `/Users/Public`. Return an empty list so the login screen goes straight to username and password.

**Where in Moonfin**

- `lib/auth/repositories/server_user_repository.dart`
- `lib/ui/screens/auth/server_screen.dart`

**Earlier work to port:** silo-1

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Selecting the Silo server opens the username/password form.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-1-16"></a>
## 1.16 Skip Moonfin plugin sync at sign-in for Silo

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** The `/Moonfin/*` plugin doesn't exist on Silo, so don't call it.

**Where in Moonfin**

- `lib/auth/repositories/session_repository.dart`
- `lib/data/services/plugin_sync_service.dart`

**Earlier work to port:** silo-1

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

<a id="step-1-17"></a>
## 1.17 Web discovery hint and add-server wording

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Accept the `silo` type hint in web discovery, and name Silo in the add-server error.

**Where in Moonfin**

- `lib/auth/services/server_discovery_service_web.dart`
- `lib/auth/repositories/server_repository.dart`

**Earlier work to port:** silo-1

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

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
- `detect()` checks for "silo" in the product name before the Jellyfin and Emby checks. Silo's **Jellyfin-compatible** listener (port 8096) reports `ProductName: "Jellyfin Server"`, so a server added on that port is still a Jellyfin server; only the native API is Silo. The native API isn't probed until step 1.9.

**The eight exhaustive `switch`es the compiler flagged.** Dart refuses to compile a `switch` over an enum that misses a value, which is how every place needing Silo handling was found:

| Where | Silo case in this step | Replaced in |
|---|---|---|
| `media_server_client_factory.dart` `_createRawClient` | throws `UnsupportedError('Silo servers are not supported yet')` | 1.8 (`SiloMediaServerClient`, built in 1.4) |
| `playback_module.dart`, `media_bar.dart`, the AirPlay, DLNA and Google Cast providers (stream resolver) | same throw | 1.8 (`playback_silo` plugin, built in 1.7) |
| `socket_handler.dart` (websocket client) | same throw | 1.8 (idle Silo socket), 13.2 (events socket) |
| `server_type_icon.dart` | generic `Icons.dns_outlined` glyph | 1.11 (Silo icon) |

The throws are unreachable: every other switch needs a `MediaServerClient`, and the factory is the only way to get one, so a Silo client can't exist until 1.8. Nothing produces a Silo `Server` in the first place (the probe only reads `/System/Info/Public`, which Silo's native site answers with HTML). The icon is the exception because a widget must never throw: server lists render it for any saved entry.

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
| ☑ Done | `05275d8` | 1.1 |

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
| 2026-10-13 | macOS | — | Pass | Brady: skip intro still works on Emby |

---

<a id="step-1-3"></a>
## 1.3 Silo request headers

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `7a57ef5` | 1.2 |

**Goal.** `buildSiloRequestHeaders()`: `Authorization: Bearer`, `X-Profile-Id`, `X-Profile-Token`, `X-Silo-Device-Id/-Name/-Platform`, `X-Silo-Client(-Version)`, sanitised and length-clamped (a bad device id gets a 422).

**Where in Moonfin**

- `packages/server_core/lib/src/network/auth_header.dart`

**Earlier work to port:** silo-1 `buildSiloRequestHeaders` (added: `X-Silo-Device-Platform`, empty-value handling, public `siloDeviceId`; the 422 rule re-verified live)

### How it works

Jellyfin and Emby take one `Authorization: MediaBrowser Client=…, Device=…, Token=…` header. Silo splits the same information over several headers, so `packages/server_core/lib/src/network/auth_header.dart` gains `buildSiloRequestHeaders()` next to the existing `buildServerAuthorizationHeader()` (which is unchanged). Nothing calls it yet; the Silo client (1.4) sends its result on every request.

| Header | Value | Sent when |
|---|---|---|
| `Authorization` | `Bearer <access token>` | signed in |
| `X-Profile-Id` | the selected household profile | a profile is selected (most viewer routes require it) |
| `X-Profile-Token` | proof from `verify-pin` | a PIN-locked profile is unlocked |
| `X-Silo-Device-Id` | `DeviceInfo.id` (Moonfin's per-install UUID) | always |
| `X-Silo-Device-Name` | `DeviceInfo.name`, max 120 chars | always |
| `X-Silo-Device-Platform` | e.g. `macOS`, `tvOS`, `Android TV`, max 40 chars | when the caller passes `platform` |
| `X-Silo-Client` / `-Version` | `DeviceInfo.appName` / `appVersion` (e.g. `Moonfin for macOS`, `2.7.0`) | always |

**Why the device headers go on every request, not only at sign-in.** Silo records the device in its registry at sign-in and playback start, and its catalog and settings routes use `X-Silo-Device-Id` to pick device-scoped playback preferences ("absent resolves the profile's preferences"). Sending it everywhere keeps those preferences per device, like Silo's own apps.

**Device id validation (found on the live server, not in the OpenAPI document).** The contract only says `maxLength: 128`, but build `4b2e921c` answers `422 validation_failed` with *"X-Silo-Device-Id must be a single device identifier: letters, digits, '.', '_', ':' or '-', with no comma or interior whitespace"*. Checked on 2026-10-13 with a sign-in for a non-existent user: `moonfin-test.1:2_3` → 401 (header accepted), `tv box/01 {x}` and `Brady’s-tv` → 422. `siloDeviceId()` therefore drops every other character and clamps to 128; if nothing is left, the header is omitted rather than sent empty. Moonfin's ids are UUID v4s, which already qualify, so in practice this only guards odd legacy or test ids.

**`platform` is a parameter, not a `DeviceInfo` field.** `DeviceInfo` is shared by every backend and built in `lib/di/injection.dart`; adding a field would touch all of them and every test fake. `server_core` can't import Flutter's platform detection, so the Silo client passes the platform name in (step 1.4).

**Values are sanitised like the Jellyfin header** (ASCII only, no quotes, commas or control characters) because HTTP header values must be ASCII; `Brady’s Apple TV` becomes `Brady s Apple TV`.

### Testing

**Automated tests**

- `packages/server_core/test/auth_header_test.dart` (new, 10 tests): full header set; missing and empty values left out; name and platform clamps; UUID kept; refused characters dropped (with the live 422 examples); 128 clamp; no header when nothing usable is left; the Jellyfin/Emby header string unchanged.

**Manual test plan**

- Nothing to see in the app (no caller yet). Optional: read the test file; each case is a rule from the table above.
- Optional, on the Mac: `curl -s -X POST https://silo.snowystreams.com/api/v2/auth/login -H 'Content-Type: application/json' -H 'X-Silo-Device-Id: tv box' --data '{"username":"nobody","password":"x"}'` returns the 422 quoted above.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | 4b2e921c+dirty | Pass | server_core 66/66; `dart analyze` clean for server_core and the app; device-id rule checked live (401 for a valid id, 422 for refused characters) |
| 2026-10-13 | macOS | — | Pass | Brady reviewed; no app-visible change |

---

<a id="step-1-4"></a>
## 1.4 `server_silo` package skeleton

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `7f25317` | 1.3 |

**Goal.** Create the package, `SiloMediaServerClient` (Dio set up like Emby, Silo headers on every request), and placeholder APIs that throw a readable `SiloNotImplementedError` naming the step that replaces them. Live TV and Instant Mix are permanently empty.

**Where in Moonfin**

- `packages/server_silo/**`
- `pubspec.yaml`
- `pubspec.lock`

**Earlier work to port:** silo-1 package (reduced to the skeleton; session, refresh and Problem Details split out to their own steps; placeholders renumbered to the current roadmap)

### How it works

A new package, `packages/server_silo`, holds Moonfin's Silo backend, mirroring `server_emby` and `server_jellyfin`. This step creates the package and its client with every API stubbed. Nothing in the app uses it yet (the factory is wired in 1.8), and the app's `pubspec.yaml` doesn't list it yet either.

**Files**

| File | What it is |
|---|---|
| `pubspec.yaml` | Depends on `server_core` and `dio` only (the first-pass package also pulled in `logger`, which nothing used). |
| `lib/server_silo.dart` | Public exports: the client, the Live TV and Instant Mix classes, `SiloNotImplementedError`. |
| `lib/src/silo_media_server_client.dart` | `SiloMediaServerClient extends MediaServerClient`. |
| `lib/src/api/silo_pending_api.dart` | Placeholders for the APIs not translated yet. |
| `lib/src/api/silo_live_tv_api.dart`, `silo_instant_mix_api.dart` | Permanent empty implementations. |

**`SiloMediaServerClient`** is built like `EmbyMediaServerClient`: one Dio with the same timeouts (8 s connect, 3 min receive), `configureServerDio` for certificates and the user agent, the shared redirect interceptor, and the same request logging (progress pings thinned to one in twelve; the Silo path is `/api/v2/playback/<session>/progress`). The difference is the header interceptor: instead of one `Authorization: Emby …` header it adds `buildSiloRequestHeaders()` from step 1.3 on every request. Besides the usual `accessToken` and `userId` it holds `profileId` and `profileToken` (Silo's household profile and PIN proof) and a `platform` string the app supplies for `X-Silo-Device-Platform`. An optional `httpClientAdapter` lets tests answer requests from fixtures.

On Silo, Moonfin's "user" is a household profile (decision D1), so `userId` and `profileId` normally hold the same id. They stay separate fields because an account signs in before a profile is chosen.

**Placeholders.** Each not-yet-translated API is a small class that implements the real interface and answers *every* member with `SiloNotImplementedError("Silo ItemsApi.getItems is not implemented yet (roadmap step 6.5)")`, through `noSuchMethod`, so a 40-method interface doesn't need 40 stubs. A call that arrives too early becomes a readable error naming the step that fixes it, not a crash. Each placeholder is deleted by its step:

| API | Replaced in |
|---|---|
| `SystemApi` | 1.6 |
| `AuthApi` | 2.3 |
| `UsersApi` | 2.7 |
| `SessionApi` | phase 3 (sign-in reports capabilities) and 13.6 |
| `UserViewsApi` | 6.4 |
| `ItemsApi` | 6.5 onward |
| `UserLibraryApi` | 6.6 and phase 9 |
| `DisplayPreferencesApi` | 6.19 |
| `PlaybackApi` | 6.18 and 10.6 |
| `ImageApi` | 6.1. It returns `''` instead of throwing, because image URLs are built synchronously while widgets render; an empty URL shows the placeholder art. |

**Permanent answers.** Live TV reads return an empty `{Items: [], TotalRecordCount: 0}` and writes fail with `UnsupportedError` (Silo has no Live TV by design); Instant Mix is always empty. They return empty rather than throwing so shared rows simply render nothing. The admin getters throw `UnsupportedError` (Silo is administered in its own web app; `FeatureDetector.supportsAdmin` hides the panel). Trickplay, SyncPlay, client-log and games APIs are left at the base class's `null`.

**Left for later steps:** token refresh (2.1–2.2), stricter same-origin redirects (1.14), the shared `serverAuthHeaders()` interface (1.12), Problem Details errors (1.5). The first-pass client had all of these in one file.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_media_server_client_test.dart` (new, 13 tests): server type and base URL; headers before sign-in and as token/profile change; each placeholder throws `SiloNotImplementedError` with its API, member and step; image URLs empty; Live TV and Instant Mix empty, Live TV writes and admin refused; optional APIs null. (Headers on the wire are tested in 1.6, the first step with a real request.)

**Manual test plan**

- No app change. Optional: `cd packages/server_silo && flutter pub get && flutter test` on the Mac (13 tests).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | server_silo 13/13; `dart analyze` clean; `dart format` applied |
| 2026-10-13 | macOS | — | Pass | Brady committed after review |

---

<a id="step-1-5"></a>
## 1.5 Silo error responses (Problem Details)

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `af10e59` | 1.4 |

**Goal.** Parse RFC 7807 Problem Details into `SiloApiException(code, status, detail, retryAfter)`, including bodies served as `text/plain`.

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_problem.dart`

**Earlier work to port:** silo-2 `silo_problem.dart` and silo-1 "parse Silo JSON bodies sent as plain text" (extended, see below)

### How it works

Every Silo error comes back as an RFC 9457 *Problem Details* JSON body. Its `type` URI ends in a stable code (`invalid_token`, `validation_failed`, `token_refresh_required`, `session_expired`…), `detail` is text meant for people, `instance` identifies the request in Silo's logs, and validation failures list each bad field in `errors`. This step teaches the Silo client to read them, so failures are readable in logs and in the UI, and later steps (token refresh in 2.2, PIN lockout in 2.6, unplayable media in 10.8) can branch on the code.

**`packages/server_silo/lib/src/silo_problem.dart`**

- `SiloProblem.fromJson(body)` parses a problem from a map **or a string**. Silo sometimes serves problem JSON as `text/plain`, which Dio leaves undecoded. It returns null for anything that isn't a problem (no body, HTML from a proxy, ordinary JSON), and tolerates wrongly typed fields rather than throwing while handling an error.
- `code` is the last path segment of `type`; code that reacts to an error checks this, never the human `title`/`detail`. `message` is the text to show (detail, else title). `errors` holds `SiloProblemError(location, code, detail)` entries such as `header.x-silo-device-id / invalid`.
- `SiloProblem.of(e)` / `codeOf(e)` read the problem from a `DioException`.
- `SiloProblem.retryAfter(e)` reads `Retry-After` (Silo sends it with `429` and `503`) as seconds or an HTTP date. `dart:io`'s `HttpDate` isn't available on the web build, so a small IMF-fixdate parser is used instead.
- `toString()` gives one line: `Silo 401 invalid_token: Invalid username or password.`, plus `[location code: detail]` per field error.

**`siloProblemInterceptor()`**, added to the client's Dio right after the redirect interceptor, so **before** the logging interceptor (Dio runs error interceptors in the order they were added). For a failed response with a problem body it puts the `SiloProblem` in `DioException.error` and its one-line text in `DioException.message`. The log line and anything in the app that shows `e.message` then read Silo's own explanation instead of Dio's generic "bad response". Network errors and non-problem bodies pass through unchanged.

**`asJsonMap` moved to `server_core`.** The server probe already had a private helper that decodes JSON sent as text. It now lives in `packages/server_core/lib/src/network/json_body.dart` as the public `asJsonMap`, used by both the probe and `SiloProblem`, so there's one implementation. The probe's behaviour is unchanged (its existing tests pass).

**Changed from the first pass:** the silo-2 `SiloProblem` was parse-only and returned `Retry-After` as integer seconds; this version adds the interceptor, `message`, a readable `toString`, tolerant field parsing and HTTP-date support.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_problem_test.dart` (new, 13 tests): the real 401 and 422 bodies captured from your server in step 1.3; problem sent as text; non-problems (HTML, plain JSON, arrays) ignored; wrongly typed fields tolerated; `code` extraction; one-line text; the interceptor attaches the problem (JSON and `text/plain`) and leaves HTML and network errors alone; `Retry-After` as seconds, as an HTTP date (future and past), missing and unreadable.
- `packages/server_core/test/json_body_test.dart` (new, 3 tests): `asJsonMap` for maps, JSON text and non-objects.

**Manual test plan**

- No app change. Optional: `flutter test` in `packages/server_silo` (26 tests) and `packages/server_core` (69 tests).
- Jellyfin/Emby: add a server by address once to confirm the probe still works (its JSON helper moved).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | 4b2e921c+dirty (captured bodies) | Pass | server_silo 26/26, server_core 69/69, app analyzer 0 errors/warnings |
| 2026-10-13 | macOS | — | Pass | Brady: adding a server still works |

---

<a id="step-1-6"></a>
## 1.6 `SiloSystemApi`

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `4361368` | 1.5 |

**Goal.** Public info, system info and ping, returned in the shape the app already reads.

**Silo v2 endpoints**

- `GET /system/info`
- `GET /system/identity`
- `GET /theme/branding`
- `GET /system/setup`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_system_api.dart`

**Earlier work to port:** silo-1 `silo_system_api.dart` and the shaping function from its probe (setup now reads `wizard_completed` first; blank branding handled)

### How it works

The Silo client's first real API, replacing the `SystemApi` placeholder. Jellyfin's `PublicSystemInfo` comes from one call; Silo spreads the same facts over four public endpoints, so they are fetched together and folded into the Jellyfin keys the app reads.

| Jellyfin key | Silo source (captured value) |
|---|---|
| `Id` | `/system/identity` → `server_id` (`7b72fbd5-…`; the v2 identity, never v1's) |
| `ServerName` | `/theme/branding` → `server_name` (`Silo`), else "Silo" |
| `Version` | `/system/info` → `server_version` (`4b2e921c+dirty`, a git hash: shown, never parsed) |
| `ProductName` | always `Silo` |
| `StartupWizardCompleted` | `/system/setup` → `wizard_completed`, else `!needs_setup`, else true |
| `LoginDisclaimer` | `/theme/branding` → `login_subtitle` ("Sign in with an existing account."), shown on the login screen |
| `SiloApiMajor`, `SiloContractDigest` | `/system/info`, for compatibility checks and logs |

**Where the mapping lives:** `packages/server_core/lib/src/network/silo_public_info.dart` (`siloPublicInfoToJellyfinShape`, `isSiloSystemInfo`, `siloSystemInfoPath`). It sits in `server_core`, not `server_silo`, because the server probe (step 1.9) has to build the same shape from the same endpoints and `server_core` can't depend on `server_silo`. One function, used by both.

**`packages/server_silo/lib/src/api/silo_system_api.dart`**

- `getPublicSystemInfo()` fetches the four endpoints in parallel. `/system/info` decides success and must look like Silo (`api_major` + `server_version`), otherwise a `FormatException`; identity, branding and setup are best effort and simply left out if they fail, since they only decorate a server already known to be Silo.
- `getSystemInfo()` adds `GET /account/me` as `SiloAccount`. Jellyfin's `/System/Info` needs a valid session, so this deliberately does too: a missing or revoked login fails with Silo's 401 problem (thanks to step 1.5 the error reads "Silo 401 authentication_required: …").
- `ping()` uses `/system/identity`: Silo has no ping route, and identity is public, tiny and served by every API node.

In the app today only the admin dashboard calls `SystemApi`, which Silo users can't reach (`supportsAdmin` is false), and the connectivity check still hard-codes `/System/Ping` (fixed in 13.1). So this step mostly provides the shared mapping and the first tested request path.

**Test helper:** `packages/server_silo/test/fixture_server.dart` is a fake Silo server. It answers each path from the captured fixtures (unknown paths get a Silo-style 404 problem) and records every request, which lets tests check the headers the client really puts on the wire. Later API steps reuse it.

### Testing

**Automated tests**

- `packages/server_core/test/silo_public_info_test.dart` (new, 6 tests): Silo detection; the full mapping from the captured responses; system info alone; setup precedence; blank and custom server names.
- `packages/server_silo/test/silo_system_api_test.dart` (new, 10 tests): public info from the captured fixtures through the real client; cosmetic endpoints failing; a Jellyfin body and an HTML page at `/system/info` rejected; `getSystemInfo` with and without a token (401 problem text); `ping` true/false; **headers on the wire** before and after sign-in.
- The `SystemApi` placeholder and its test are removed.

**Manual test plan**

- No app change. Optional: `flutter test` in `packages/server_silo` (35) and `packages/server_core` (75).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | 4b2e921c+dirty (fixtures) | Pass | server_silo 35/35, server_core 75/75, app analyzer 0 errors/warnings |
| 2026-10-13 | macOS | — | Pass | Brady committed after review |

---

<a id="step-1-7"></a>
## 1.7 `playback_silo` package skeleton

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `12c3e7a` | 1.6 |

**Goal.** Plugin, a resolver that refuses with a clear "Silo playback isn't available yet" message, and a no-op session service.

**Where in Moonfin**

- `packages/playback_silo/**`

**Earlier work to port:** silo-1 `playback_silo` (message constant added, unused `logger` dependency dropped, step references updated)

### How it works

A new package, `packages/playback_silo`, mirroring `playback_emby`/`playback_jellyfin`. Moonfin's player asks a per-server *plugin* for two objects: a `MediaStreamResolver` (item → playable URL) and a `PlayerService` (start/progress/stop reports). This step provides Silo's versions as safe stubs so the app can be wired to them in 1.8; real playback is phase 10.

| File | What it does now | Real version |
|---|---|---|
| `lib/src/silo_plugin.dart` | `SiloPlugin(client)` with `createStreamResolver()` and `createPlaySessionService()`, same shape as `EmbyPlugin` | stays |
| `lib/src/silo_media_stream_resolver.dart` | `resolve()` returns a failed future with `UnsupportedError(siloPlaybackUnavailableMessage)`: *"Playback from Silo servers isn't available in this build yet."* | 10.6 (`POST /playback/start` → plan) |
| `lib/src/silo_play_session_service.dart` | every report is a no-op that makes no request | 10.9 progress, 10.10 stop |

**Why fail in `resolve` rather than earlier:** the player already turns a failed resolve into its error screen, so pressing Play on a Silo item (once browsing works) shows the message instead of crashing. The error is returned as a failed `Future` (not thrown synchronously) because callers handle resolve errors through the future.

**Why the session service is silent:** a session only exists after `/playback/start` answers, which can't happen yet; sending progress or stop would hit routes that need a session id.

**How Silo playback will differ** (recorded here for reviewers; designed in phase 10): Jellyfin and Emby use `PlaybackInfo` + a `DeviceProfile` and the client picks a URL. Silo decides on the server: the client posts codec *evidence* to `/playback/start` and gets one plan (delivery, signed stream URL, subtitles, timeline, `session_id`); progress is sequenced and the stop is idempotent with a `stop_id`. That's why the package is separate and why its pubspec depends only on `playback_core` and `server_core` (not on `server_silo`), like the other playback packages.

The first-pass package also depended on `logger`, which nothing used; it's dropped.

### Testing

**Automated tests**

- `packages/playback_silo/test/silo_plugin_test.dart` (new, 3 tests): `resolve` fails with the message for any option combination; every session report completes without touching the client (the stub client fails the test on any call); the plugin builds both objects.

**Manual test plan**

- No app change. Optional: `cd packages/playback_silo && flutter pub get && flutter test` (3 tests).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | playback_silo 3/3, `dart analyze` clean |
| 2026-10-13 | macOS | — | Pass | Brady committed after review |

---

<a id="step-1-8"></a>
## 1.8 Wire Silo into the app's factories

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `c263071` | 1.7 |

**Goal.** Client factory, playback module, media bar, the three cast providers and the websocket factory (idle Silo client).

**Where in Moonfin**

- `lib/data/services/media_server_client_factory.dart`
- `lib/di/modules/playback_module.dart`
- `lib/ui/widgets/media_bar.dart`
- `lib/data/services/cast/*_provider.dart`
- `lib/data/services/socket_handler.dart`

**Earlier work to port:** silo-1 wiring (only the Silo lines; the branch also carried unrelated drift from an older main). Added the device-platform name.

### How it works

This step connects the two Silo packages to the app. It replaces the seven `UnsupportedError('Silo servers are not supported yet')` stand-ins from step 1.1 with the real Silo objects. Users still see no change: the server probe doesn't recognise Silo until 1.9, so no Silo server can be added yet.

| Where | Silo case now |
|---|---|
| `pubspec.yaml` / `pubspec.lock` | `server_silo` and `playback_silo` added as path dependencies, next to the Emby and Jellyfin ones |
| `lib/data/services/media_server_client_factory.dart` | `SiloMediaServerClient(baseUrl, deviceInfo, platform: _siloDevicePlatform())` |
| `lib/di/modules/playback_module.dart` (`setActiveStreamResolver`) | `SiloPlugin(client)` resolver and session service, wrapped by the same local-first/offline layers as the others |
| `lib/ui/widgets/media_bar.dart`, the AirPlay, DLNA and Google Cast providers | `SiloPlugin(client).createStreamResolver()` |
| `lib/data/services/socket_handler.dart` | `SiloWebSocketClient`, an idle socket (below) |

**Device platform.** `_siloDevicePlatform()` in the factory names the platform for `X-Silo-Device-Platform` the same way `_clientName()` in `lib/di/injection.dart` names the app: `tvOS`, `Web`, `Android TV`, `Android`, `iOS`, `macOS`, `Windows`, `Linux`. It lives in the app because only the app can see `PlatformDetection` (step 1.3 explains why `server_core` takes it as a parameter).

**`SiloWebSocketClient`** implements `ServerWebSocketClient` but never connects and never emits. Everything that listens for server pushes (user data changes, library updates, remote commands) simply hears nothing, which is safe. Silo's real-time channel is a different protocol: a ticketed `/api/v2/events/ws` socket with its own frames, built in step 13.2. A Jellyfin/Emby-style socket would 404 and reconnect forever.

**What a Silo client can do after this step:** be created; answer `systemApi` (1.6); report Live TV and Instant Mix as empty; and refuse playback with the 1.7 message. Everything else raises the "not implemented yet (roadmap step X)" error from 1.4.

**What still stops a user from reaching any of it:** the probe (1.9).

### Testing

**Automated tests**

- `test/offline/media_server_client_factory_test.dart`: new test, the factory builds a `SiloMediaServerClient` for a Silo server with the platform and device headers filled in.
- `test/data/services/silo_web_socket_client_test.dart` (new): `ServerWebSocketClient.forServer` gives a Silo client the idle socket; connect, retry and disconnect emit nothing.
- Full app suite and analyzer (results below).

**Manual test plan**

- `flutter pub get` then `flutter run -d macos`: the app builds with the two new packages.
- Jellyfin/Emby unchanged: sign in, play something, open the cast menu on an item.
- Adding `silo.snowystreams.com` still fails as "not a Jellyfin or Emby server" (expected until 1.9).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | App suite 4,274 passed, 1 skipped, 0 failed (4,272 before + 2 new); analyzer 0 errors/warnings; `pubspec.lock` diff adds only the two path packages |
| 2026-10-13 | macOS | — | Pass | Brady: builds, Jellyfin/Emby unchanged |

---

<a id="step-1-9"></a>
## 1.9 Detect Silo in the server probe

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `3ce09fa` | 1.8 |

**Goal.** Try `/api/v2/system/info` before the Jellyfin and Emby paths, then build `Id`/`ServerName`/`Version` from identity, branding and setup. Reject the HTML 200 that the native host returns for `/System/Info/Public`.

**Why it comes after 1.8** (moved from 1.4 on 2026-10-13): with no build flag, recognising Silo saves a Silo server and opens its sign-in screen, which asks the client factory for a client straight away. Before 1.8 that factory refuses Silo, so the screen would hang on its spinner. Probing last means the step that makes Silo addable also lands on a working (if not yet able to sign in) screen.

**Silo v2 endpoints**

- `GET /system/info`
- `GET /system/identity`
- `GET /theme/branding`
- `GET /system/setup`

**Where in Moonfin**

- `packages/server_core/lib/src/network/server_probe.dart`

**Earlier work to port:** silo-1 probe (without the `detectSilo` flag parameter; added: fast failure on host-level errors)

### How it works

The step that makes Silo reachable. When you add a server, `addServer` in `lib/auth/repositories/server_repository.dart` builds a list of candidate URLs (schemes and default ports) and runs `probeServerPublicInfo` (`packages/server_core/lib/src/network/server_probe.dart`) on each until one answers. The probe now recognises Silo's native API.

**Probe order for each candidate URL**

1. `GET <base>/api/v2/system/info`. If the body is Silo's (`api_major` + `server_version`, checked by `isSiloSystemInfo` from 1.6), it's a Silo server. Identity, branding and setup are then fetched in parallel, best effort, and folded into the Jellyfin keys by `siloPublicInfoToJellyfinShape` (the same function `SiloSystemApi` uses), so `addServer` gets the `Id`, `ServerName`, `Version`, `LoginDisclaimer` and `StartupWizardCompleted` it already reads.
2. Otherwise the existing Jellyfin/Emby paths, `/System/Info/Public` then `/emby/System/Info/Public`, exactly as before.

**Why Silo goes first.** The native Silo host answers `/System/Info/Public` with its web app's HTML (seen behind your proxy), and Silo's Jellyfin-compatible listener answers it as "Jellyfin Server". Asking for `/api/v2/system/info` first means a native Silo address is recognised as Silo, while the compat port (no `/api/v2`) is still recognised as Jellyfin, as before. An HTML page or non-Silo JSON at `/api/v2/system/info` (a catch-all proxy rule in front of Jellyfin or Emby) is ignored and the old paths take over.

**Cost for Jellyfin and Emby: one extra request.** Their probe now starts with a request that 404s. In exchange, **an unreachable address now fails faster than before**: a connection-level failure (refused, connect timeout, rejected certificate) applies to the whole host, so when the first attempt fails that way the probe rethrows it immediately instead of trying each path. Before this step a dead address waited out two attempts per candidate; now one. The error is the same `DioException` as before, so the "untrusted certificate" prompt in `addServer` still works. Other failures (404, a receive timeout) still fall through to the next path.

**Shared plumbing.** Redirect following (up to 5 hops, `Location` resolved relative to the request) is factored into `_getFollowingRedirects` and used by both the Silo and Jellyfin/Emby paths; the base URL is cut at the endpoint suffix so a reverse-proxy prefix (`https://host/silo`) is kept.

**What you get in the app now:** adding `silo.snowystreams.com` saves a server named from Silo's branding ("Silo"), shows the generic server glyph (Silo icon in 1.11), and opens the username/password screen with Silo's sign-in subtitle. No public user list appears: Silo has no `/Users/Public`, so the existing fallback returns an empty list (it logs an error until 1.15 skips the call). Pressing **Sign in** shows "Silo AuthApi.authenticateByName is not implemented yet (roadmap step 2.3)", which is expected until phase 2. The web build's server discovery uses the same probe, so it can find Silo too.

### Testing

**Automated tests**

- `packages/server_core/test/server_probe_test.dart`, 8 new tests (the 4 existing ones unchanged): Silo identified from your server's responses, with the Jellyfin paths never asked; reverse-proxy prefix kept; redirect to the Silo host followed; cosmetic endpoints failing; Silo's compat port still Jellyfin; HTML at `/api/v2/system/info` (catch-all proxy) falls through to Emby; non-Silo JSON falls through to Jellyfin; an unreachable host makes exactly one request for connection errors, connect timeouts and bad certificates.

**Manual test plan**

- Add `silo.snowystreams.com`. It is accepted; the tile is named "Silo" with the generic server glyph.
- Selecting it opens the username/password form with "Sign in with an existing account." No user list, no Quick Connect button.
- Enter anything and press Sign in: the error names roadmap step 2.3. Nothing crashes, and you can go back.
- Also try `https://silo.snowystreams.com/` with a trailing slash; it should resolve to the same server.
- Compare with Emby: add your Emby server again (or a second time) and confirm it is still detected as Emby and signs in normally.
- Add an address that doesn't exist (e.g. `nothing.invalid`): it fails with the usual message, and faster than before.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | 4b2e921c+dirty (captured responses) | Pass | server_core 83/83; app suite 4,274 passed, 1 skipped, 0 failed; analyzer 0 errors/warnings |
| 2026-10-13 | macOS | 4b2e921c+dirty | Pass | Brady: Silo added and opens the sign-in form; sign-in shows the step 2.3 message; Emby still detected; bad address fails fast |

---

<a id="step-1-10"></a>
## 1.10 Add the Silo packages to CI

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `956ed17` | 1.9 |

**Goal.** Add `server_silo` and `playback_silo` to the package list in the build workflow so their analyzer and tests run on PRs.

**Where in Moonfin**

- `.github/workflows/build.yml`

### How it works

The build workflow's test job (`.github/workflows/build.yml`, "Run analyzer and tests") loops over a fixed list of packages: for each it runs `flutter pub get`, collects `dart analyze` errors and runs `flutter test`. `server_silo` and `playback_silo` are added to that list, so their analyzer errors gate PRs and their tests run in CI like the Jellyfin and Emby packages'.

The other playback packages aren't in the list (they have no tests of their own); `playback_silo` is, because it has a test file. The app-level tests that touch Silo (`test/...`) already run in the job's root `flutter test`.

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Locally, the same loop the job runs: `for p in server_silo playback_silo; do (cd packages/$p && flutter pub get && dart analyze && flutter test); done`
- After pushing the branch, the "Run analyzer and tests" job on your fork lists `pkg-server_silo` and `pkg-playback_silo` results (if Actions are enabled on the fork).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | macOS | — | Pass | Brady: both packages analyze and test clean locally |
| | | | | |

---

<a id="step-1-11"></a>
## 1.11 Silo server icon

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `bee9a63` | 1.10 |

**Goal.** A simple original glyph in `ServerTypeIcon` (not Silo's trademarked logo).

**Where in Moonfin**

- `lib/ui/widgets/server_type_icon.dart`

**Earlier work to port:** silo-1 `_SiloGlyphPainter` (as is; replaces the 1.1 placeholder)

### How it works

`ServerTypeIcon` (`lib/ui/widgets/server_type_icon.dart`) draws each server type's mark with a `CustomPainter`, in the caller's colour, wherever servers are listed (server select, user menu, multi-server rows). Step 1.1 gave Silo a temporary Material `Icons.dns_outlined`; this step replaces it with `_SiloGlyphPainter` and goes back to a single `CustomPaint` for every type.

**The glyph:** a domed cylinder (a grain silo) with three horizontal bands, on a 24×24 grid like Material icons. It's deliberately **not** the Silo project's logo, which is its own trademark; a generic shape avoids implying endorsement and needs no permission.

**How the bands are drawn:** the body is filled inside `saveLayer`, then the three band lines are drawn with `BlendMode.clear`, which punches them out of the layer. The bands therefore show whatever is behind the icon (card, list tile, focus highlight) instead of a hard-coded background colour, so the icon looks right on light, dark, OLED and focused backgrounds. `shouldRepaint` only repaints on a colour change, like the Jellyfin and Emby painters.

### Testing

**Automated tests**

- `test/ui/widgets/server_type_icon_test.dart`: every server type still renders without throwing; the 1.1 placeholder test is replaced by one checking Silo now paints its own glyph (a `CustomPaint` at the requested size, no Material `Icon`).

**Manual test plan**

- Server list shows the Silo glyph on phone and TV layouts.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | macOS | — | Pass | Brady committed after review |

---

<a id="step-1-12"></a>
## 1.12 Shared auth headers for hand-built requests

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `3330ef9` | 1.11 |

**Goal.** A `serverAuthHeaders()` helper (via a separate `ProfileAwareClient` interface so the test fakes stay untouched). Move the bitrate probe and retro-artwork transport onto it.

**Where in Moonfin**

- `packages/server_core/lib/src/profile_aware_client.dart`
- `lib/playback/auto_bitrate_service.dart`
- `lib/data/services/retro_artwork/retro_artwork_transport.dart`

**Earlier work to port:** silo-1 `profile_aware_client.dart`, the wrapper forwarding and the two call sites (the bitrate-probe skip is split out to 1.13)

### How it works

A few places in the app make HTTP requests outside the server client's own Dio and build the Jellyfin/Emby `Authorization` header by hand (`scheme: client.serverType == ServerType.emby ? 'Emby' : 'MediaBrowser'`). On Silo that header means nothing. This step gives them one helper that returns the right headers for any server.

**`packages/server_core/lib/src/profile_aware_client.dart`**

- `ProfileAwareClient`, an interface for clients with household profiles: `profileId`, `profileToken` and `authHeaders()`. It is **not** added to `MediaServerClient` itself: that abstract class is implemented by the Jellyfin and Emby clients and by ~90 test fakes, which would all have to change. A separate interface leaves them untouched.
- `serverAuthHeaders(client)`: a `ProfileAwareClient` returns its own `authHeaders()`; every other client gets exactly the header the call sites built before (`MediaBrowser …` for Jellyfin, `Emby …` for Emby).
- `clientProfileId(client)`: the profile id, or null on servers without profiles. Used from phase 3 on.

**Who implements it**

- `SiloMediaServerClient`: its existing `profileId`/`profileToken` fields become the interface members, and `authHeaders()` returns the same headers its own requests carry (bearer, profile, device, client; step 1.3).
- `ConnectivityAwareMediaServerClient` (`lib/data/offline/`): the factory wraps every client in this offline-aware wrapper, so a `client is ProfileAwareClient` check would otherwise never see the Silo client inside. The wrapper forwards the profile members and `authHeaders()` to the wrapped client; for Jellyfin/Emby the profile reads null, writes are ignored, and the headers are the old ones.

**Call sites switched to `serverAuthHeaders(client)`**

- `lib/playback/auto_bitrate_service.dart`: the bandwidth probe request. (Skipping the probe on Silo entirely is step 1.13.)
- `lib/data/services/retro_artwork/retro_artwork_transport.dart`: the retro-game artwork downloader.

Behaviour for Jellyfin and Emby is identical: the helper builds the same header string from the same inputs, which the tests assert byte for byte.

### Testing

**Automated tests**

- `packages/server_core/test/profile_aware_client_test.dart` (new, 4 tests): Jellyfin header identical to `buildServerAuthorizationHeader(MediaBrowser)`; Emby header; a profile-aware client's own headers; `clientProfileId`.
- `packages/server_silo/test/silo_media_server_client_test.dart`: new test, the Silo client is a `ProfileAwareClient` and `authHeaders()` equals its request headers.
- `test/offline/connectivity_aware_profile_test.dart` (new, 2 tests): the offline wrapper forwards profile id, profile token and headers to a Silo client, and is inert (null profile, unchanged MediaBrowser header) for a Jellyfin client.
- Existing tests for the bitrate service, the retro-artwork transport and data source, and the game screens pass unchanged.

**Manual test plan**

- Jellyfin and Emby: with the streaming quality on "Auto", play something and confirm playback picks a sensible quality (the bandwidth probe still authenticates).
- If you have the Moonbase games plugin on Jellyfin: open the games library and confirm the artwork loads.
- Full app suite on the Mac.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | server_core 87/87, server_silo 36/36, related app tests 61/61, analyzer 0 errors/warnings. Full app suite left to Brady. |
| 2026-10-13 | macOS | — | Pass | Brady: full suite and manual checks |

---

<a id="step-1-13"></a>
## 1.13 Skip the bandwidth probe on Silo

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `8385961` | 1.12 |

**Goal.** Silo has no speed-test route. Skip the probe and leave the estimate to passive measurement.

**Where in Moonfin**

- `lib/playback/auto_bitrate_service.dart`

**Earlier work to port:** silo-1 (the skip that was bundled with the shared-headers change)

### How it works

`AutoBitrateService.measuredBpsForActiveServer()` (`lib/playback/auto_bitrate_service.dart`) measures the link before an "Auto" quality stream by downloading test payloads from Jellyfin/Emby's `/Playback/BitrateTest`, then caps the stream request at 80 % of the result. Silo has no such route, so on a Silo server the probe would only time out and delay playback.

The change is one early return: when the active client is a Silo client the method returns `null`, which callers already treat as "no measurement" (the same answer as offline or no server). No request is made.

**Why nothing is lost:** Silo plans the stream on the server. `POST /playback/start` accepts the client's own bandwidth estimate and cap (`bandwidth_estimate_kbps`, `bandwidth_cap_kbps`) and applies the server's bitrate policy itself. Feeding Moonfin's preferences and any passive estimate into those fields is part of the capabilities translator (step 10.3), not this probe.

### Testing

**Automated tests**

- `test/playback/auto_bitrate_silo_test.dart` (new, 2 tests): a Silo client pointed at a local HTTP server gets `null` and the server receives **no** request; a Jellyfin client pointed at the same server does reach it (control). The test deliberately avoids the Flutter test binding, which would replace `HttpClient` with a fake that never connects.
- Existing `auto_bitrate_cap_test.dart` passes unchanged.

**Manual test plan**

- Nothing to see until Silo playback exists (phase 10). Jellyfin/Emby: Auto quality still measures (unchanged code path).
- Full app suite on the Mac.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | New and existing bitrate tests 12/12; analyzer clean. Full suite left to Brady. |
| 2026-10-13 | macOS | — | Pass | Brady: full app suite |

---

<a id="step-1-14"></a>
## 1.14 Safer redirects for Silo sessions

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 1.13 |

**Goal.** Only follow same-origin redirects with credentials attached, and only upgrade http→https on 443 or the same port.

**Where in Moonfin**

- `packages/server_core/lib/src/network/redirect_interceptor.dart`

**Earlier work to port:** silo-1 commits 08bb227 (same-origin redirects) and 59c87ef (limit upgrades to 443 or the same port), as is

### How it works

Every Moonfin server client follows HTTP redirects with the shared `redirectInterceptor` (`packages/server_core/lib/src/network/redirect_interceptor.dart`), because Dart's `HttpClient` won't follow them for `POST`/`PUT`. It resends the request **with its headers and body** to wherever `Location` points. For Silo those headers carry the bearer token, and the sign-in body (phase 2) carries the password, so a redirect to another site would hand both over.

**The change**

- `redirectInterceptor(dio, {bool sameOriginOnly = false})`. With the option on, a redirect whose target fails `isSameOriginRedirect` isn't followed; the caller gets the original 3xx as an error, exactly as if no interceptor were installed.
- `isSameOriginRedirect(from, to)`:
  - same host (case-insensitive), same scheme and same port → follow;
  - `http` → `https` on the same host → follow only if the target port is 443 or the port it came from (a server on `:8080` redirecting to its HTTPS address is normal; another port on that host could be a different service);
  - anything else (another host or subdomain, another port, an `https` → `http` downgrade, another scheme) → don't follow.
- `SiloMediaServerClient` installs the interceptor with `sameOriginOnly: true`.

**Jellyfin and Emby are unchanged:** the option defaults to off and their clients don't pass it. (Whether to tighten them too is a separate question for the maintainers; it's out of scope here.)

The server probe follows redirects with its own loop rather than this interceptor and sends no credentials, so a reverse proxy or domain move is still discovered when a server is added.

### Testing

**Automated tests**

- `packages/server_core/test/redirect_interceptor_test.dart` (new, 7 tests): `isSameOriginRedirect` for same origin, other host/subdomain/port, upgrades to 443 / same port / other port, downgrades and other schemes; the interceptor follows a same-origin redirect with the request intact, refuses a cross-origin one when restricted (only one request made), and still follows anywhere when unrestricted (the Jellyfin/Emby behaviour).
- `packages/server_silo/test/silo_system_api_test.dart`, 2 new tests through the real Silo client: a redirect to another site isn't followed, one within the server is.

**Manual test plan**

- Package tests: `server_core` (94) and `server_silo` (38).
- Jellyfin/Emby: sign in and browse as usual (unchanged path). If one of your servers sits behind a redirect (e.g. `http://` → `https://`), sign in through that address once.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | server_core 94/94, server_silo 38/38, analyzers clean. App suite left to Brady. |
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

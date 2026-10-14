# Phase 2: Sign-in API (package only)

[← Roadmap](../ROADMAP.md)

Sessions, sign-in and profiles inside `server_silo`. Still no UI changes; everything is unit-tested against fixtures.

**Phase done when:** `server_silo` can sign in, refresh, list profiles, check a PIN and describe the current user, all covered by tests.

---

<a id="step-2-1"></a>
## 2.1 Token pair and single-flight refresh (`SiloSession`)

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `1fc1c21` | 1.17 |

**Goal.** Hold the access/refresh token pair and expiry. Refresh once even when many requests ask at the same time. End the session only when Silo refuses the refresh token, never on a 503 or a network error.

**Silo v2 endpoints**

- `POST /auth/refresh`

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_session.dart`
- `packages/server_silo/lib/src/silo_media_server_client.dart`

**Earlier work to port:** silo-2 `silo_session.dart` and the client wiring (the interceptor and the separate refresh Dio are step 2.2)

### How it works

Jellyfin and Emby hand out one access token that lasts until you sign out. Silo hands out a **pair**: a short-lived access token (sent as `Authorization: Bearer …`) and a refresh token that buys a new pair from `POST /api/v2/auth/refresh`. The refresh token **rotates**: each refresh returns a new one and the old one stops working. This step adds the object that holds the pair and refreshes it. Nothing calls `refresh()` automatically yet; the request interceptor in 2.2 does.

**`packages/server_silo/lib/src/silo_session.dart`**

- **`SiloTokens`**: the pair plus `expiresAt` (UTC) and `lifetime`, built from a sign-in `TokenPair` or a `RefreshedTokens` response (`access_token`, `refresh_token`, `expires_in` seconds). `needsRefresh(now)` is true once four fifths of the lifetime has passed or under a minute is left, so a busy app renews early instead of collecting 401s. `toJson`/`fromJson` give the form the app will store in phase 3.
- **`SiloSession`** holds the current `SiloTokens` and:
  - `refresh(dio)` posts the refresh token. **Concurrent callers share one request** (a stored `Future`): when ten requests notice expiry at once, one refresh goes out and all ten wait on it. Sending the old refresh token twice would fail the second time, because the token rotates.
  - **Only a `401` ends the session.** The pair is dropped and `onSessionEnded(expired)` fires once, so the app can return to sign-in. A `503`, no network or a malformed answer keeps the tokens: those say nothing about whether the login is still good, and signing someone out because their Wi-Fi blinked would be wrong.
  - After a successful refresh, `onTokensChanged(pair)` lets the app save the rotated pair. If saving throws, the in-memory session still counts as renewed; the next cold start then meets a refused refresh and asks you to sign in again.
  - **Identity.** `identity` is a counter bumped whenever requests start acting for someone else: new tokens, a bare token, sign-out, or a profile switch (`identityChanged()`). It is *not* bumped by a refresh of the same login. A refresh that finishes after a new sign-in is discarded rather than overwriting the new login. Step 2.2 uses the same counter so a late reply is never retried as a different person.
  - `setAccessToken(token)` supports the generic `MediaServerClient.accessToken` setter: the same token as the current pair changes nothing (the refresh token survives); any other token is held without refresh (for example a personal API key); null signs out.
  - The refresh request is marked `siloNoAuthExtra` (sent without the bearer token, since the refresh token is the credential) and `siloNoRefreshExtra` (never refresh-and-retry it).

**`SiloMediaServerClient` changes**

- The client owns a `SiloSession`; `accessToken` reads and writes through it, and `requestHeaders` takes the bearer token from it.
- `profileId`/`profileToken` setters bump the session identity when they change.
- **The profile belongs to the login.** When the login is replaced or ends (new tokens, sign-out, refused refresh), the client clears `profileId` and `profileToken`. A PIN proof from one login must never ride along on another. A refresh of the same login keeps the profile.
- The header interceptor drops `Authorization` from requests marked `siloNoAuthExtra`.
- A `clock` parameter lets tests move time.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_session_test.dart` (new, 18 tests):
  - `SiloTokens`: parsing a response, tolerating bad fields, the refresh-due rule (4/5 of life or the last minute), no refresh without a refresh token, JSON round-trip;
  - refresh: rotated pair swapped in and saved, request body and flags; three concurrent callers make **one** request; a 401 ends the session once; 503, network error and malformed answers keep the tokens; nothing sent without a refresh token; a refresh finishing after a new sign-in changes nothing; failing save/end callbacks don't break it;
  - identity changes on new login, bare token, sign-out and profile switch, but not on a refresh or the same token;
  - client: access token comes from the session; a new login or sign-out drops the profile and PIN proof; a refresh keeps them; requests carry the bearer token.
- `silo_media_server_client_test.dart`: one assertion updated, since signing out now drops the profile header too.

**Manual test plan**

- No app change. `cd packages/server_silo && flutter test` (56 tests).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | server_silo 56/56; analyzers clean (package and app) |
| | | | | |

---

<a id="step-2-2"></a>
## 2.2 Session interceptor

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `2cb4fc5` | 2.1 |

**Goal.** Refresh shortly before expiry, retry a 401 once after refreshing, and never replay login, refresh, device sign-in or PIN checks. Refreshes use a separate HTTP client so they can't deadlock.

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_session_interceptor.dart`
- `packages/server_silo/lib/src/silo_media_server_client.dart`

**Earlier work to port:** silo-2 (commits 34b9b9b, b40b956, 717c21d)

### How it works

Step 2.1 gave the client a token pair that *can* be refreshed. This step decides **when**: a Dio interceptor that sits in front of every Silo request. Jellyfin and Emby never need this, because their tokens don't expire.

**`packages/server_silo/lib/src/silo_session_interceptor.dart`** (`SiloSessionInterceptor`)

- **Early refresh (`onRequest`).** If the access token is due (`SiloSession.needsRefresh`: 4/5 of its life gone or under a minute left), the request waits for a refresh and then goes out with the new token. Because `refresh()` is single-flight, a screen that fires twenty requests at once triggers one refresh.
- **Refresh and replay (`onError`).** A `401` on a request that carried a bearer token refreshes once and replays the request once. Silo uses several codes for a 401 (`invalid_token`, `token_refresh_required` after a role change, `session_expired`, `authentication_required`) and they can't be told apart before trying, so the interceptor always tries the refresh: a dead login refuses it, which ends the session through 2.1's `onSessionEnded`, and the original 401 is passed back to the caller.
  - If another request already refreshed while this one was in flight (the token it sent is no longer the current one), it replays straight away without a second refresh.
  - The replay is a **copy** of the request with the old `Authorization` removed and a `silo.retried` mark; the header interceptor writes the new token on it. A replay that gets a 401 again is returned as is, so there is never a loop.
  - A `503` or network error during the refresh keeps the login (2.1's rule) and the request fails with its original error.
- **Never replayed.** Requests marked `siloNoRefreshExtra` (sign-in, refresh, device sign-in, PIN checks, set from 2.3 on) or `siloNoAuthExtra` are never refreshed for, before or after. Replaying a password sign-in or a PIN attempt could count as a second attempt against Silo's rate limits, and a 401 there means "wrong credentials", not "stale token".
- **Never replayed as someone else.** Each request is stamped with `SiloSession.identity` the first time it is sent. Every later dispatch of the same request comes back through `onRequest`: the refresh replay, a redirect followed by the redirect interceptor, the dead-connection retry from `configureServerDio`, and the send after waiting on an early refresh. Each one only goes out while the stamp still matches; otherwise it fails with a `cancel`-type `DioException`. So a reply that arrives after a sign-out, a new sign-in or a profile switch can't be retried with the new person's token or PIN proof.

**`SiloMediaServerClient` changes**

- A second Dio, `_authDio`, built by the same `_newDio()` with the same redirect rule, problem parser, headers and logging, but **without** the session interceptor. Refreshes go through it (`refreshSession()`), and step 2.3 sends sign-in through it. Sending a refresh through the main Dio would re-enter the interceptor that is waiting on it.
- Interceptor order on the main Dio: same-origin redirects → Silo problems → session → headers and logging. The session interceptor runs before the header interceptor so a refresh made before sending is in place when the bearer token is written.
- `baseUrl` and `dispose()` cover both Dio instances.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_session_interceptor_test.dart` (new, 17 tests, against `FixtureServer`):
  - refresh and replay: a 401 refreshes once and replays once (the refresh carries no bearer token); a nearly expired token is refreshed before sending; three simultaneous 401s share one refresh and all three are replayed; a second 401 is not retried; a refused refresh ends the session and fails the request; a 503 refresh keeps the login; nothing is refreshed without a refresh token;
  - never replayed as someone else: a profile switch during the refresh fails the request; a request waiting on an early refresh isn't sent if the profile changes; redirects arriving after a profile switch or a sign-out aren't followed; a dead-connection retry after a profile switch isn't sent, but one with no change still is;
  - never refreshed for: no-refresh and no-auth requests get their 401 as is, and an expiring token isn't refreshed before them;
  - `refreshSession()` refreshes on demand.
- `silo_session_test.dart`: the client bearer-token test now fixes the clock, since an expired token would now be refreshed before sending.

**Manual test plan**

- No visible app change yet (sign-in arrives in 2.3). `cd packages/server_silo && flutter test` (73 tests).
- Regression: sign in to Emby and play something, to check the shared `configureServerDio` path is untouched.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | server_silo 73/73; analyzer clean (package and app, no new warnings) |
| | | | | |

---

<a id="step-2-3"></a>
## 2.3 Password sign-in

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 2.2 |

**Goal.** `authenticateByName` → `POST /auth/login` with device headers, translated to the Jellyfin `AuthenticationResult` shape plus the Silo token data.

**Silo v2 endpoints**

- `POST /auth/login`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_auth_api.dart`
- `packages/server_silo/lib/src/mappers/silo_user_mapper.dart`
- `packages/server_silo/lib/src/silo_media_server_client.dart`

**Earlier work to port:** silo-2

### How it works

Jellyfin's `AuthenticateByName` returns one long-lived token and the user. Silo's `POST /api/v2/auth/login` returns a `TokenPair`: an access token, a rotating refresh token, `expires_in` seconds and the signed-in `Account`. This step translates that into the `AuthenticationResult` map the app already reads, so the existing login screen signs in to Silo with no app change.

**`packages/server_silo/lib/src/api/silo_auth_api.dart`** (`SiloAuthApi`, replaces `SiloPendingAuthApi`)

- `authenticateByName(username, password)` posts `{username, password}` on the client's **sign-in Dio** (`_authDio` from 2.2, which has no session interceptor). It carries the device headers like every Silo request.
- The request is flagged `siloNoAuthExtra`, so it carries no bearer token: the password is the credential, and a token left over from another login mustn't ride along. It is also flagged `siloNoRefreshExtra`, so it is never refreshed for or replayed. That matters because **Silo answers a wrong password with `401 invalid_token`**, the same code as an expired token (checked on the live server), and a replayed sign-in would count as a second attempt against Silo's rate limits.
- On success:
  - the pair becomes the client's session (`SiloSession.setTokens`). That is a new login, so any earlier login's profile and PIN proof are dropped (2.1's rule);
  - the result is `AccessToken`, `User` (the account translated to a Jellyfin `UserDto`), `SiloTokens` (the pair as JSON, for the app to store in step 3.2) and `SiloPasswordChangeRequired`.
- **`SiloPasswordChangeRequired`** is true when the account holds a temporary password. Until it is changed, Silo lets the session only read the account, change the password and sign out; everything else answers `403 password_change_required`. The app reacts to it in step 3.11.
- An answer without both tokens or without an account id is a `FormatException`, and the current session is left untouched. A failed sign-in (wrong password, validation error) also leaves the current session as it was.
- Errors are Dio errors whose message is Silo's problem text from 1.5 (for example `Silo 401 invalid_token: Invalid username or password.`, or the field errors of a `422`). The app's auth repository already turns a 401 into "Invalid username or password"; nicer messages for other errors come with the login screen work in 3.3.
- The other `AuthApi` members throw `SiloNotImplementedError` naming their step: `logout` → 2.4, the QuickConnect methods → phase 14 (Silo device sign-in).

**`packages/server_silo/lib/src/mappers/silo_user_mapper.dart`** (new)

- `siloAccountToUserDto(account)`: `Id` and `Name` from the account id and username, `SiloAccountId` and the raw `SiloAccount` alongside. Silo has no per-user policy object, only a server-wide `role` and `download_allowed`, so the policy is `IsAdministrator` (role `admin`), `EnableContentDownloading`, and `EnableCollectionManagement` (always true; personal collections are open to every Silo account). Other policy flags read as their defaults.
- **For now the Moonfin user is the account.** Per decision D1 it becomes the household profile in 2.7 and phase 3, so a Silo user signed in during phase 2 will be stored under the account id and should be removed once phase 3 lands.

**Smaller changes**

- `SiloSession.now` exposes the session clock so sign-in computes the expiry on the same clock as refreshes (tests move it).
- `server_silo.dart` exports the auth API and the user mapper.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_auth_api_test.dart` (new, 10 tests, built on the captured `auth_login.json`):
  - the Jellyfin result shape, and the policy reading through Moonfin's `UserPolicy`;
  - the token pair lands on the session with the right expiry and is returned as JSON;
  - the request: method, body, device headers, no bearer token even when one is set;
  - a new sign-in replaces the earlier login, bumps the identity and drops the profile and PIN proof;
  - `password_change_required` is flagged;
  - a wrong password (the live server's `401 invalid_token`) is a readable error, is not refreshed or retried, and keeps the current login;
  - a `422` carries Silo's field errors;
  - answers without a token pair or an account fail and change nothing.
- `silo_media_server_client_test.dart`: the placeholder test now checks `logout` (2.4) and QuickConnect (phase 14) instead of sign-in.

**Manual test plan** (macOS, Silo server; Emby for the regression)

1. Add the Silo server (or pick it) and sign in with a **wrong password**. Expected: "Invalid username or password", and the app stays on the login screen.
2. Sign in with the right password. Expected: sign-in succeeds and the app leaves the login screen. Home and libraries are still empty or show "not implemented yet" errors (those are phases 5 and 6). In the log: `→ POST …/api/v2/auth/login` then `← 200`.
3. Optional: sign in with an account that has a temporary password. Expected: sign-in still succeeds (the app ignores the flag until 3.11).
4. Regression: sign in to Emby and play something.
5. Afterwards, remove the Silo user from the user list. Phase 3 stores Silo users differently, and the session isn't saved across restarts yet (3.9).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | 4b2e921c (wrong-password answer checked live) | Pass | server_silo 84/84; analyzer clean |
| | | | | |

---

<a id="step-2-4"></a>
## 2.4 Sign out

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `logout` → `POST /auth/logout`.

**Silo v2 endpoints**

- `POST /auth/logout`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_auth_api.dart`

**Earlier work to port:** silo-2

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

<a id="step-2-5"></a>
## 2.5 List household profiles

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `SiloProfilesApi.list()`.

**Silo v2 endpoints**

- `GET /profiles`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_profiles_api.dart`

**Earlier work to port:** silo-2

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- fixture `profiles.json` parsed; PIN flag read

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-6"></a>
## 2.6 Profile PIN check

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `verify-pin` → profile token with expiry; 429 lockout with `Retry-After`, not retried automatically.

**Silo v2 endpoints**

- `POST /profiles/{id}/verify-pin`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_profiles_api.dart`

**Earlier work to port:** silo-2

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- correct PIN; wrong PIN; lockout

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-7"></a>
## 2.7 Current user (account + profile → user)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `SiloUsersApi.getCurrentUser` and the user mapper: profile id as the Moonfin user id, admin/download permissions from the account.

**Silo v2 endpoints**

- `GET /account/me`
- `GET /profiles`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_users_api.dart`
- `packages/server_silo/lib/src/mappers/silo_user_mapper.dart`

**Earlier work to port:** silo-2

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: Compare the mapped user with Emby's `/Users/{id}` for the fields Moonfin reads (`Policy`, `Configuration`).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-8"></a>
## 2.8 User playback settings

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Read and save subtitle language/mode, audio language and autoplay-next through the profile; keep Jellyfin-only fields local.

**Silo v2 endpoints**

- `GET /settings/values/effective`
- `PATCH /profiles/{id}`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_users_api.dart`

**Earlier work to port:** silo-2

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

# Phase 2: Sign-in API (package only)

[← Roadmap](../ROADMAP.md)

Sessions, sign-in and profiles inside `server_silo`. Still no UI changes; everything is unit-tested against fixtures.

**Phase done when:** `server_silo` can sign in, refresh, list profiles, check a PIN and describe the current user, all covered by tests.

---

<a id="step-2-1"></a>
## 2.1 Token pair and single-flight refresh (`SiloSession`)

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 1.17 |

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
| ☐ Not started | — | previous step |

**Goal.** Refresh shortly before expiry, retry a 401 once after refreshing, and never replay login, refresh, device sign-in or PIN checks. Refreshes use a separate HTTP client so they can't deadlock.

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_session_interceptor.dart`

**Earlier work to port:** silo-2 (commits 34b9b9b, b40b956, 717c21d)

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- proactive refresh; one retry; non-replayable ops; identity-bound retries

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-3"></a>
## 2.3 Password sign-in

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `authenticateByName` → `POST /auth/login` with device headers, translated to the Jellyfin `AuthenticationResult` shape plus the Silo token data.

**Silo v2 endpoints**

- `POST /auth/login`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_auth_api.dart`

**Earlier work to port:** silo-2

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- success; wrong password → readable error; `password_change_required` flagged

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
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

# Phase 2: Sign-in API (package only)

[← Roadmap](../ROADMAP.md)

Sessions and sign-in inside `server_silo`. Until the optional profiles phase (18), Moonfin acts as the account's **main profile** (decision D9). Still no UI changes; everything is unit-tested against fixtures.

**Phase done when:** `server_silo` can sign in, refresh, sign out, find the account's main profile and describe the current user, all covered by tests.

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
| ☑ Done | `83bd066` | 2.2 |

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
- **`SiloPasswordChangeRequired`** is true when the account holds a temporary password. Until it is changed, Silo lets the session only read the account, change the password and sign out; everything else answers `403 password_change_required`. The app reacts to it in step 3.6.
- An answer without both tokens or without an account id is a `FormatException`, and the current session is left untouched. A failed sign-in (wrong password, validation error) also leaves the current session as it was.
- Errors are Dio errors whose message is Silo's problem text from 1.5 (for example `Silo 401 invalid_token: Invalid username or password.`, or the field errors of a `422`). The app's auth repository already turns a 401 into "Invalid username or password"; nicer messages for other errors come with the login screen work in 3.3.
- The other `AuthApi` members throw `SiloNotImplementedError` naming their step: `logout` → 2.4, the QuickConnect methods → phase 14 (Silo device sign-in).

**`packages/server_silo/lib/src/mappers/silo_user_mapper.dart`** (new)

- `siloAccountToUserDto(account)`: `Id` and `Name` from the account id and username, `SiloAccountId` and the raw `SiloAccount` alongside. Silo has no per-user policy object, only a server-wide `role` and `download_allowed`, so the policy is `IsAdministrator` (role `admin`), `EnableContentDownloading`, and `EnableCollectionManagement` (always true; personal collections are open to every Silo account). Other policy flags read as their defaults.
- **For now the Moonfin user is the account.** From step 3.3 the stored user is the account's main profile (decision D9; 2.6 maps it), so a Silo user signed in during phase 2 is stored under the account id and should be removed once phase 3 lands.

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
3. Optional: sign in with an account that has a temporary password. Expected: sign-in still succeeds (the app ignores the flag until 3.6).
4. Regression: sign in to Emby and play something.
5. Afterwards, remove the Silo user from the user list. Phase 3 stores Silo users differently, and the session isn't saved across restarts yet (3.4).

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
| ☑ Done | `379c378` | 2.3 |

**Goal.** `logout` → `POST /auth/logout`.

**Silo v2 endpoints**

- `POST /auth/logout`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_auth_api.dart`

**Earlier work to port:** silo-2

### How it works

Jellyfin's `/Sessions/Logout` just invalidates the one token. On Silo, signing out has to end the **server-side login session**, because that is what keeps the refresh token alive. Dropping the tokens on the device alone would leave a refresh token that still works on the server until it expires.

**`SiloAuthApi.logout()`** (`packages/server_silo/lib/src/api/silo_auth_api.dart`)

- Sends `POST /api/v2/auth/logout` with the bearer token (and profile header, if any). Silo answers `204` and revokes the session.
- It goes through the **main** Dio, unlike sign-in, so the session interceptor from 2.2 applies: an expired access token is refreshed first and the logout is replayed once. That is safe because Silo marks logout as naturally idempotent, and it means a device that sat idle past token expiry still revokes its session instead of failing with a 401.
- **The client always signs out locally**, whatever the server answers (`finally`): tokens cleared, and with them the profile and PIN proof (2.1's rule).
  - A `401` means the session is already gone (revoked from the web UI, or the refresh was refused). That counts as success.
  - Any other failure (no network, `503`) is rethrown **after** the local sign-out, so the caller can log it. Both app callers (`AuthRepository.logout` and `SessionRepository`'s sign-out) already catch errors from `logout()` and carry on removing the user, as they do for Jellyfin and Emby.
- Not signed in: nothing is sent.
- A bare token set through `accessToken` (no refresh token) is revoked the same way.

**Smaller changes**

- `SiloAuthApi` now also takes the client's main Dio.
- `silo_session.dart`: moved the `now` getter added in 2.3 above `needsRefresh`'s doc comment, which it had split from its getter.
- The placeholder test for `logout` is gone, since the method is real now.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_auth_api_test.dart`, new `logout` group (6 tests):
  - revokes on Silo (method, path, bearer and profile headers) and clears tokens, profile and PIN proof;
  - an expired access token is refreshed first, then the logout is sent with the new token;
  - a `401` (with a refused refresh) is not an error and still signs out;
  - a `503` signs out locally and is rethrown;
  - nothing is sent when not signed in;
  - a bare token is revoked too.

**Manual test plan** (macOS, Silo server)

1. Sign in to Silo (2.3). In Silo's web app, open your account's sessions: a Moonfin session for this Mac is listed.
2. In Moonfin, sign out from the user menu. Expected: back on the login screen. The log shows `→ POST …/api/v2/auth/logout` then `← 204`.
3. Refresh the sessions page in Silo's web app. Expected: the Moonfin session is gone.
4. Sign in again. Expected: works. Then revoke that session from Silo's web app and sign out in Moonfin. Expected: still back on the login screen with no error, and the log shows the 401.
5. Regression: sign out of Emby and sign back in.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | server_silo 89/89; analyzer clean |
| 2026-10-13 | macOS (Brady) | 4b2e921c | Pass | Session listed in Silo's account sessions as "Brady s Mac mini Mac16 10" and removed on sign-out; revoked-session sign-out and Emby regression fine. The name lost its apostrophe and comma to the shared header sanitiser (see note below). |


**Note from testing.** Silo shows the device name from `X-Silo-Device-Name`. `buildSiloRequestHeaders` reuses the Jellyfin header sanitiser, which turns non-ASCII characters (macOS's curly ’) and commas into spaces, because commas break Jellyfin's quoted `Authorization` format. Silo's headers are plain values, so a Silo-specific sanitiser could keep commas and map typographic quotes to ASCII. Candidate polish step; not part of 2.4.

---

<a id="step-2-5"></a>
## 2.5 Use the account's main profile

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `99f95c0` | 2.4 |

**Goal.** Find the account's primary profile (`is_primary`) with `GET /profiles` and send its `X-Profile-Id` on every request. Silo keeps watch progress, favourites and home rows per profile, and refuses requests without the header once any profile on the account has a PIN or restrictions. If the main profile has a PIN, fail with a typed error the app can explain (PIN entry comes with the optional profiles phase, 18.4).

**Silo v2 endpoints**

- `GET /profiles`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_profiles_api.dart`
- `packages/server_silo/lib/src/silo_media_server_client.dart`

**Earlier work to port:** silo-2 (the list part)

### How it works

Jellyfin and Emby have one user per login. A Silo login belongs to an **account**, and the account's data (watch progress, favourites, home rows, playback settings) belongs to its **household profiles**. Requests pick a profile with `X-Profile-Id`; the contract describes per-viewer data as "absent without a profile", and 28 operations refuse a request without the header once any profile on the account has a PIN or restrictions. So even though choosing between profiles is deferred to the optional phase 18 (decision D9), Moonfin has to act as *some* profile. It acts as the account's **main profile** (`is_primary`), which every account has.

**`packages/server_silo/lib/src/api/silo_profiles_api.dart`** (new)

- `SiloProfile`: `id`, `name`, `isPrimary`, `hasPin`, `isChild`, plus the full JSON for the user and settings mappers in 2.6 and 2.7.
- `SiloProfilesApi.list()`: `GET /api/v2/profiles` (the list is unpaginated). Entries without an id are skipped; a body without an `items` list is a `FormatException`.
- `SiloProfilesApi.mainProfile()`: the primary profile, wherever it sits in the list.
  - If it has a PIN, it throws `SiloMainProfileLockedError`. Acting as a locked profile needs a PIN proof (`X-Profile-Token`), and PIN entry comes with 18.4. Step 3.7 turns this error into a clear message on the login screen.
  - If no profile is primary, it throws a `StateError` with the count. Every account has one, so this would mean a broken answer.
- It isn't a Moonfin interface: Jellyfin and Emby have nothing like it, so only the app's Silo sign-in (3.3) will call it.

**`SiloMediaServerClient` changes**

- `profilesApi` exposes the API above.
- `useMainProfile()` lists the profiles, picks the main one, and sets `profileId`, so every later request carries its `X-Profile-Id` (the header builder from 1.3 already sends it when set). It first clears any old profile and PIN proof: a stale id, for example a profile deleted on the web, would get the listing itself refused. Changing the profile bumps the session identity (2.1), so requests in flight for the old profile aren't replayed for the new one.
- If the main profile is locked, the error propagates and the client is left without a profile.

Nothing in the app calls this yet; sign-in from the login screen uses it in 3.3.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_profiles_api_test.dart` (new, 8 tests):
  - the captured `profiles.json` parses (id, name, flags, raw settings);
  - PIN and child flags; entries without an id skipped; a non-list answer rejected;
  - `useMainProfile` picks the primary profile when it isn't first, and later requests carry its `X-Profile-Id`;
  - the listing goes out without a stale profile or PIN proof, and the old proof is dropped;
  - a PIN-locked main profile gives `SiloMainProfileLockedError` and selects nothing;
  - no primary profile is a readable error;
  - selecting the profile changes the session identity.

**Manual test plan**

- No app change. `cd packages/server_silo && flutter test` (97 tests).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | 4b2e921c (captured `profiles.json`) | Pass | server_silo 97/97; analyzer clean |
| | | | | |

---

<a id="step-2-6"></a>
## 2.6 Current user (account + main profile → user)

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `435e04c` | 2.5 |

**Goal.** `SiloUsersApi.getCurrentUser` and the user mapper: the main profile's id as the Moonfin user id (so the optional profiles phase adds the other profiles as users without migrating anyone), name from the profile, admin/download permissions from the account.

**Silo v2 endpoints**

- `GET /account/me`
- `GET /profiles`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_users_api.dart`
- `packages/server_silo/lib/src/mappers/silo_user_mapper.dart`
- `packages/server_silo/lib/src/silo_media_server_client.dart`

**Earlier work to port:** silo-2

### How it works

Moonfin reads the signed-in user through `UsersApi.getCurrentUser()`: when a stored session is restored (a rejected token there signs out), when a session starts (to refresh the admin, download, subtitle and collection rights it keeps on the stored user), when signing in from saved credentials, and in the library-scope service (`EnableAllFolders`/`EnabledFolders`). Jellyfin and Emby answer from `/Users/{id}`. Silo splits that information between the **account** (role, download right) and the **profile** (name, PIN, restrictions, settings).

**`packages/server_silo/lib/src/api/silo_users_api.dart`** (`SiloUsersApi`, replaces `SiloPendingUsersApi`)

- `getCurrentUser()` reads `GET /account/me` and `GET /profiles` at the same time and maps the account with the profile the client acts as (`X-Profile-Id`, set by 2.5's `useMainProfile`). With no profile chosen yet it describes the main profile, the one the client will act as.
- Failures stay plain Dio errors: the two reads are awaited one by one rather than with a record's `.wait`, which would wrap them in a `ParallelWaitError`. That matters because the app signs out only on a `DioException` with status 401.
- A chosen profile that no longer exists (deleted on the web) is a `StateError`, not a 401, so it is reported rather than signing the user out.
- `getUserConfiguration`/`updateUserConfiguration` still throw `SiloNotImplementedError` naming 2.7.

**`packages/server_silo/lib/src/mappers/silo_user_mapper.dart`**: `siloProfileToUserDto(profile, account)`

- `Id` is the **profile** id. With the main profile as the Moonfin user (D9), the optional profiles phase can add the other profiles as users and the main one keeps its id.
- `Name` is the profile name, falling back to the username when blank.
- Silo has no per-user policy object, so the policy is derived:

  | Moonfin reads | From | Why |
  |---|---|---|
  | `IsAdministrator` | account `role == admin` **and** the primary profile | Silo withholds administrator routes from secondary profiles |
  | `EnableContentDownloading` | account `download_allowed` | |
  | `EnableCollectionManagement` | always true | personal collections are open to every Silo profile |
  | `EnableSubtitleDownloading` | always true | subtitle search and download are profile-scoped routes, open to every profile |
  | `EnableAllFolders` | always true | Silo enforces a profile's library restrictions itself, and its library ids aren't Moonfin's view ids until phase 6. Passing them on could hide libraries the profile may see |
  | `EnableLiveTvAccess`/`Management` | false | Silo has no Live TV |
  | `EnableMediaPlayback` | true | |

- The raw account and profile ride along under `SiloAccount` and `SiloProfile` for 2.7 and phase 3.

**App effect.** None of the callers above needed changes. After a Silo sign-in, starting the session now reads the user instead of logging a "not implemented" error.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_users_api_test.dart` (new, 9 tests):
  - the captured account and main profile map to id, name and the full policy table above;
  - the profile the client acts as is described; a secondary profile of an admin account isn't an administrator;
  - with no profile chosen, the main profile is described;
  - a non-admin account without downloads;
  - a blank profile name falls back to the username;
  - raw account and profile ride along;
  - a deleted profile is a readable `StateError`;
  - a rejected token surfaces as a plain 401 `DioException` (this caught the `ParallelWaitError` problem);
  - both reads carry the profile header.
- `silo_media_server_client_test.dart`: the placeholder test now checks `getUserConfiguration` (2.7).

**Manual test plan** (macOS, Silo server)

1. Sign in to Silo. Expected in the log: `→ GET …/api/v2/account/me` and `→ GET …/api/v2/profiles`, both `← 200`, and no "UsersApi … not implemented" error.
2. Quit and relaunch with the Silo user active (within the hour, since restoring the session properly is 3.4). Expected: the same two reads at start-up, no sign-out.
3. Regression: same on Emby.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | 4b2e921c (captured `account_me.json`, `profiles.json`) | Pass | server_silo 106/106; analyzer clean |
| 2026-10-13 | macOS (Brady) | 4b2e921c | Pass | Signed in, relaunched, stayed signed in. Silo's sessions page showed "Active now" after sign-in but not after the relaunch: see note. |


**Note from testing: "Active now" in Silo's sessions page.** Silo's web app shows "Active now" when the login session's `last_seen_at` is under two minutes old (`sessionLastSeen` in `web/src/lib/loginSessionDevice.ts`). The server updates it on every authenticated request, at most once a minute (`SessionLastSeenTracker`). At this stage Moonfin only makes the two current-user reads when a session starts. Everything else on Home is still a local placeholder, so two minutes after start-up the page shows "Last seen N min ago". That's expected; browsing (phase 6), realtime events (phase 13) and playback keep the session active.

---

<a id="step-2-7"></a>
## 2.7 User configuration (library order, hidden libraries, playback keys)

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `4e6b1dc` | 2.6 |

**Goal.** `getUserConfiguration`/`updateUserConfiguration` on Silo's settings store for the acting profile: library order and hidden libraries (what Moonfin reads from it), plus subtitle/audio language, subtitle mode and autoplay-next. Changed from the plan while building; see How it works.

**Silo v2 endpoints**

- `GET /settings/values/effective`
- `PUT /settings/values/{key}?scope=profile`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_users_api.dart`
- `packages/server_silo/lib/src/mappers/silo_settings_mapper.dart`

**Earlier work to port:** silo-2

### How it works

**What changed from the plan.** The step was planned as "subtitle and audio language, subtitle mode and autoplay-next through the profile". While building it, two things came up:

- **Moonfin doesn't read playback settings from `UserConfiguration`.** Subtitle mode, languages and autoplay are local Moonfin preferences (`UserPreferences`) on every server. What the app reads from the server's `UserConfiguration` is the **library order** (`OrderedViews`, library order screen), the **libraries hidden from My Media** (`MyMediaExcludes`, library settings screen and every views load), and **libraries left out of "Latest"** (`LatestItemsExcludes`, the multi-server home rows).
- **Silo has a settings store with matching keys.** Its settings contract (`contracts/settings/v1/manifest.json`) defines `ui.library_order` and `ui.disabled_library_ids` at profile scope. Silo's own web app uses them for the same two things, so they're the right home, rather than a private Moonfin key or local storage.

So this step implements `getUserConfiguration`/`updateUserConfiguration` on Silo's settings store. The library keys are the part the app uses today. The playback keys come along in the same request, so the configuration Moonfin sees is faithful if a later step starts reading it.

**Mapping** (`packages/server_silo/lib/src/mappers/silo_settings_mapper.dart`)

| Jellyfin `UserConfiguration` | Silo setting (profile scope) | Notes |
|---|---|---|
| `OrderedViews` | `ui.library_order` | Silo ids are positive integers; Moonfin's are strings. Libraries missing from the list sort after the listed ones (Silo's rule) |
| `MyMediaExcludes` | `ui.disabled_library_ids` | The profile hiding a library from itself; not access control |
| `EnableNextEpisodeAutoPlay` | `playback.auto_play_next` | |
| `AudioLanguagePreference` / `SubtitleLanguagePreference` | `playback.audio_language` / `playback.subtitle_language` | Passed through as written. Silo uses language tags; Moonfin doesn't read these today |
| `SubtitleMode` | `playback.subtitle_mode` + `playback.show_forced_subtitles` | `always`→Always, `off`+forced→OnlyForced, `off`→None, `auto`→Default. Writing Default/Smart keeps the current forced switch |
| `LatestItemsExcludes`, `GroupedFolders`, remember/default-track switches | — | No Silo setting: read as empty/defaults, not saved |

These ids only line up with Moonfin's library ids if the views from step 6.4 use Silo's library id (`"1"`, `"3"` in the captured `user_libraries.json`) as the view `Id`, which is the plan.

**`SiloUsersApi`**

- `getUserConfiguration()` makes one `GET /api/v2/settings/values/effective` with a `keys` parameter per key. Silo resolves each key for the acting profile **on this device**: device, library and series overrides take part, and missing keys come back as contract defaults.
- `updateUserConfiguration(config)` writes **only the keys that changed** since the last read, each with `PUT /api/v2/settings/values/{key}?scope=profile` and body `{"value": …}`. The library screens pass the whole configuration back after changing one list, and rewriting every key would turn Silo's defaults into stored values. If there was no read for the acting profile yet, it reads first. If one write fails, the keys already written stay the new baseline, so a retry writes only what's still different.
- Both need a profile: Silo's settings routes require `X-Profile-Id` and answer 422 without it, so they fail early with a `StateError` pointing at `useMainProfile()` (2.5).
- **Known limits:**
  - "Hide from Latest" doesn't persist on Silo; it has no such setting. Phase 8 (Home) decides whether to map it onto Silo's home layout or hide the toggle.
  - Writes go to profile scope. If a playback key has a device, library or series override in Silo, that override still wins for this device. Silo's library keys only exist at profile scope, so they're unaffected.

This also answers part of open decision D3: Moonfin's library order and hidden libraries live in Silo's settings store. Per-library view settings (step 6.19) are still open; Silo's `ui.library_page_state` (profile + device) is a candidate.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_settings_mapper_test.dart` (new, 8 tests): every key mapped; Silo defaults; non-integer library ids dropped; subtitle mode both ways, any case, Default keeping the forced switch, round trip; configuration to Silo values (de-duplicated ids, trimmed languages, `none`→`off`/false).
- `packages/server_silo/test/silo_user_configuration_test.dart` (new, 11 tests):
  - the effective read: path, one `keys` parameter per key, profile and device headers;
  - no profile gives a clear error with nothing sent; a malformed answer is an error;
  - hiding a library writes only `ui.disabled_library_ids` with `scope=profile` and `{"value":[3]}`; reordering writes only `ui.library_order`;
  - an unchanged configuration writes nothing; "Latest" exclusions write nothing and the stored forced switch survives;
  - changing the subtitle mode writes mode and switch;
  - an update without a read reads first;
  - a failed write keeps what was saved, and the retry writes only the rest;
  - a profile change re-reads that profile's settings.
- `silo_media_server_client_test.dart`: the last `UsersApi` placeholder test is gone.

**Manual test plan**

- No visible app change yet: the library screens need a profile on the client, which sign-in sets from 3.3. `cd packages/server_silo && flutter test` (124 tests).
- After 3.3 (recorded there): hide a library and reorder libraries in Moonfin's library settings, and check that Silo's web app shows the same.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | 4b2e921c (contract; settings manifest from silo-server `main`) | Pass | server_silo 124/124; analyzer clean |
| | | | | |

---

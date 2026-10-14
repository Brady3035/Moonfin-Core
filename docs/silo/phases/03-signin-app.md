# Phase 3: Sign-in in the app

[← Roadmap](../ROADMAP.md)

Moonfin signs in to the Silo account and acts as its main profile (decision D9). One Silo login is one Moonfin user. Choosing between household profiles, PINs and profile switching are the optional phase 18.

**Phase done when:** You can sign in, restart the app and stay signed in, and a refused login sends you back to sign-in. Home is still empty until phase 5.

---

<a id="step-3-1"></a>
## 3.1 Silo fields on the stored user

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `bf49b64` | 2.7 |

**Goal.** `PrivateUser` gains `siloAccountId`, with backward-compatible JSON.

**Where in Moonfin**

- `lib/auth/models/user.dart`

**Earlier work to port:** stash `Add_silo` (the account id only; its PIN fields go to phase 18)

### How it works

Moonfin stores each signed-in user as a `PrivateUser` (`lib/auth/models/user.dart`), saved as JSON by `AuthenticationStore` under its server. On Silo the login belongs to an **account**, and the Moonfin user is one of the account's profiles: the main profile until the optional phase 18 (decision D9). The stored user needs to know which account it belongs to:
- step 3.2 keys the stored token pair by (server, account);
- phase 18 groups an account's profiles under one login.

**`PrivateUser` changes**

- `siloAccountId` (nullable) and `isSiloProfile`. Null means a Jellyfin or Emby user.
- `toJson` writes `siloAccountId` **only when set**, so Jellyfin and Emby entries are stored exactly as before.
- `fromJson` reads it if present. Entries saved by older builds have no such key and load unchanged. An empty or non-string value reads as none rather than throwing on a damaged entry.
- `copyWith` carries it, so the existing permission refresh at session start (`SessionRepository`, which uses `copyWith`) keeps it.

Nothing sets it yet; 3.3 does at sign-in. The PIN fields from the earlier stash (`siloHasPin`, profile token and expiry) are left out: they belong to profile PINs, now phase 18.

**Also in this commit (plan only):** new step **9.7 Hide from Continue Watching and Next Up**. Moonfin's "Hide from Continue Watching" is a local, per-device list. Silo keeps the same thing on the server (`PUT/DELETE /home/dismissals/{surface}/{item_id}`), dropping a whole show from both rows until the profile watches it again. Raised by Brady after 2.7.

### Testing

**Automated tests**

- `test/auth/private_user_silo_test.dart` (new, 5 tests):
  - a Silo user round-trips its account id;
  - a Jellyfin/Emby user's JSON has exactly the old keys;
  - an entry saved by an older build loads;
  - empty or wrongly typed account ids read as none;
  - `copyWith` keeps or replaces the account id.

**Manual test plan**

- No visible change. With an Emby user already signed in, update and relaunch. Expected: still signed in, same user (old entries load).
- Full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | new test 5/5; analyzer: no new issues in `lib/auth` |
| | | | | |

---

<a id="step-3-2"></a>
## 3.2 Store the Silo token pair

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `0db88e5` | 3.1 |

**Goal.** Store the token pair with the user, keyed by (server, account), and save refreshed tokens through the session callback.

**Where in Moonfin**

- `lib/auth/store/authentication_store.dart`
- `lib/auth/services/silo_token_storage.dart`

**Earlier work to port:** silo-1/stash

### How it works

Jellyfin and Emby hand out a token that lasts until sign-out, which Moonfin stores on the user (`PrivateUser.accessToken`, in `AuthenticationStore`'s shared preferences). Silo's login is a **pair** with a refresh token that **rotates**: every refresh returns a new refresh token and the old one stops working (2.1). So the stored copy has to be replaced every time the session refreshes, or the next app start presents a dead refresh token and has to sign in again.

**`AuthenticationStore`** (`lib/auth/store/authentication_store.dart`)

- Each server's entry gains `siloAccounts`: account id → `{"tokens": <SiloTokens JSON>}`. It's keyed by (server, account), not by user, because the login belongs to the account. Today each account has one Moonfin user (its main profile, D9); with the optional phase 18 its profiles will share this one record.
- `getSiloTokens`, `putSiloTokens`, `getSiloAccountIds`, `removeSiloAccount`.
- **`putServer` keeps `siloAccounts`.** It already kept `users` when a server is edited (renamed, address changed). Without this, editing a Silo server would silently sign its accounts out at the next start.
- **`removeUser` drops the account's tokens with its last user** on that server. Sign-out (`SessionRepository`) removes the user, so a signed-out Silo login leaves no refresh token behind. A Jellyfin/Emby user, or a user whose account still has another user, leaves the record alone.
- Storage is the same place Moonfin keeps every other access token. Moonfin has a secure `CredentialStore`, but the current sign-in code only reads it as a legacy fallback and never writes to it. Moving tokens there (for all servers) would be an upstream discussion, not part of Silo support.

**`SiloTokenStorage`** (`lib/auth/services/silo_token_storage.dart`, new)

- `read`/`save` convert between `SiloTokens` and the store.
- `bind(client, serverId, accountId)` sets the session's `onTokensChanged` (2.1) so **every refreshed pair is saved** under that account. Rebinding replaces the earlier binding; `unbind` stops it. A failed save is swallowed: the session in memory is already renewed, and the worst case is a sign-in at the next start.
- `siloClientOf(client)` finds the Silo client inside the offline-aware wrapper the client factory puts around every client.

Nothing calls these yet: 3.3 saves and binds at sign-in, 3.4 reads at start-up.

### Testing

**Automated tests**

- `test/auth/authentication_store_silo_test.dart` (new, 8 tests): pairs per (server, account); a refresh replaces the pair; survives a restart; editing the server keeps accounts and users; the last user's removal removes the tokens; tokens stay while another user of the account remains; removing a Jellyfin user touches no Silo account; `removeSiloAccount` forgets only the tokens.
- `test/auth/silo_token_storage_test.dart` (new, 6 tests): `siloClientOf` for Silo and Jellyfin; save/read round trip; every refresh through a real `SiloMediaServerClient` replaces the stored pair; a refused refresh saves nothing; `unbind`; rebinding to another account.
- Every existing test that uses `AuthenticationStore` still passes (114 tests in those files).

**Manual test plan**

- No visible change. Regression: rename your Emby server (or edit its address) and relaunch; still signed in.
- Full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | `test/auth` 98/98, store-related tests 114/114; analyzer: no new issues |
| | | | | |

---

<a id="step-3-3"></a>
## 3.3 Password sign-in from the login screen

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `5d55dd5` | 3.2 |

**Goal.** The auth repository's Silo branch: sign in, find the main profile (2.5), store the user under the main profile's id with its tokens, and set the client's profile.

**Where in Moonfin**

- `lib/auth/repositories/auth_repository.dart`

**Earlier work to port:** stash (the sign-in branch; its household and profile-choice parts go to phase 18)

### How it works

The login screen already calls `AuthRepository.authenticate`, which since 2.3 reaches Silo's sign-in. Until now the generic path then stored the **account** as the user, with only the access token. This step adds the Silo branch that phase 2 prepared for.

**`AuthRepository._handleSiloSignIn`** (`lib/auth/repositories/auth_repository.dart`). When the client is a Silo client (`siloClientOf`, which looks inside the offline wrapper), after the password is accepted:

1. **Act as the main profile:** `useMainProfile()` (2.5). From here on every request carries its `X-Profile-Id`.
2. **Describe it as the user:** `usersApi.getCurrentUser()` (2.6) gives the main profile's id and name, plus the permissions derived from the account.
3. **Store the account's token pair** under (server, account) and **bind** the session so every refresh saves the rotated pair (3.2).
4. **Store the user** as a `PrivateUser` with the main profile's id, `siloAccountId` (3.1) and the permission flags. It also keeps the current access token in `accessToken`, because existing code (multi-server rows, the session switch) checks that a stored user has one. Restoring the session after a restart uses the stored pair instead (3.4).
5. Remember it as the last server and user, set it current, and answer `Authenticated`. The login screen then switches the session exactly as for Jellyfin and Emby. It reuses the same client from the client factory, so the profile and token pair set here carry over.

**If anything after the password fails** (the main profile is PIN-locked, the network drops, a 5xx), the new login is **ended on Silo too** (`logout`, 2.4), so no session is left open that the app has no record of. Nothing is stored, and the error goes back to the login screen as before: a Dio error through the existing error mapping, anything else as its text. The PIN-locked case shows the error's text for now; 3.7 gives it a proper message.

Wrong password needed no change: Silo's 401 already reads "Invalid username or password" (2.3).

Sign-out needed no change either: `logout` revokes the session (2.4), and removing the user removes the account's tokens with it (3.2).

**Not yet:**
- **After a relaunch the client doesn't act as the main profile, and holds the access token without its refresh token.** Restoring both from the store is 3.4. Until then a relaunch works for up to an hour, but requests that need the profile (user settings) fail.
- **The 2.7 library check moves to step 6.4.** It was planned to run after this step, but the library settings screens also need the library list (`UserViewsApi`), which arrives in 6.4.

### Testing

**Automated tests**

- `test/auth/auth_repository_silo_test.dart` (new, 7 tests, a real `SiloMediaServerClient` against a small fake Silo):
  - signs in as the main profile: the stored user has the profile's id and name, the account id, token and permissions; last server/user and current user are set;
  - the client acts as the main profile (`profileId`, `userId`, token);
  - the account's pair is stored, and a refresh replaces it;
  - a wrong password gives "Invalid username or password" and stores nothing;
  - a PIN-locked main profile fails, ends the new login on Silo (`/auth/logout`), clears the session and stores nothing;
  - a 503 while picking the profile does the same and keeps the status code;
  - signing in twice leaves one user and one token record.

**Manual test plan** (macOS, Silo server; Emby for the regression)

1. In the user list, remove the Silo user left from phase 2 (it was stored under the account id).
2. Sign in with a wrong password. Expected: "Invalid username or password".
3. Sign in properly. Expected: you land on Home (still empty; that's phase 6/8). The user shown is your **main profile's name**. The log shows `POST /auth/login`, then `GET /profiles`, then `GET /account/me` and `GET /profiles`, all 2xx.
4. Sign out. Expected: back to the login screen, and the Moonfin session is gone from Silo's sessions page.
5. Regression: sign in and out on Emby.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | `test/auth` 105/105; analyzer: no new issues |
| | | | | |

---

<a id="step-3-4"></a>
## 3.4 Restore the session on app start

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `9c1345d` | 3.3 |

**Goal.** Set token and profile on the client, refreshing first when the access token has expired.

**Where in Moonfin**

- `lib/auth/services/silo_token_storage.dart`
- `lib/auth/repositories/session_repository.dart`
- `lib/data/repositories/multi_server_repository.dart`
- `lib/playback/headless_session_bootstrap.dart`

**Earlier work to port:** stash

### How it works

When the app starts (or switches users), Moonfin hands each stored user's login to a client by setting `client.accessToken = user.accessToken`. That is all a Jellyfin or Emby session needs. A Silo session also needs its **refresh token** (to renew the short-lived access token) and its **profile** (`X-Profile-Id`). Neither survives in `accessToken`, so before this step a relaunch only worked until the stored access token expired, and requests that need a profile failed.

**`SiloTokenStorage.restore(client, user)`** (`lib/auth/services/silo_token_storage.dart`). For a stored Silo user (`siloAccountId`, 3.1) on a Silo client:
- puts the account's **stored token pair** on the session (3.2);
- sets the **main profile** as `profileId` (the stored user's id is the main profile's, D9);
- **binds** the session so later refreshes are saved;
- returns true, so the caller skips the old token setter. For a Jellyfin/Emby user or client it returns false and nothing changes.

**An expired access token isn't refreshed here.** The session interceptor (2.2) refreshes it before the first request goes out, once, however many requests start together. If Silo refuses the refresh (login revoked, or idle past the refresh token's expiry), the first request gets a 401. At start-up that is the token check the session repository already does: it signs out and returns to the login screen, as it does for a dead Jellyfin token. Handling a refused refresh later in a session is 3.5.

**Never clobber a live session.** The same client is handed its user more than once: the multi-server rows reuse the active client. The `accessToken` setter with the stored access token would replace the live pair with a bare, possibly expired token, drop the refresh token and clear the profile (2.1). That's why every place that hands a stored login to a client now goes through `restore`. It also leaves a client alone when it already holds this account's current pair, compared by refresh token. Bound sessions save each refresh synchronously before anything else runs, so the stored pair is always the current one. Another login found on the client is replaced.

**Call sites** (each a few lines):
- `SessionRepository.switchCurrentSession`: start-up and user switching.
- `MultiServerRepository`: the cross-server rows. It now remembers which stored user it picked.
- `headless_session_bootstrap.dart`: Android Auto/CarPlay and background engines.

**Fallback.** A Silo user stored without a pair (signed in before 3.2) gets its stored access token, as before, but now also its profile. It works until that token expires, then signs in again.

### Testing

**Automated tests**

- `test/auth/silo_session_restore_test.dart` (new, 7 tests):
  - restores pair, profile, user id and binding;
  - an expired pair is refreshed before the first request, the new pair is saved, and the profile is kept;
  - restoring onto a client that already holds the current pair changes nothing (same identity);
  - **after a refresh, restoring again keeps the refreshed pair** rather than the stale token on the stored user;
  - another login on the client is replaced;
  - no stored pair falls back to the stored access token;
  - Jellyfin users and clients are not handled.
- Existing tests for the session repository, multi-server rows and everything that builds them: 232 passed.

**Manual test plan** (macOS, Silo server)

1. Sign in to Silo, quit Moonfin, relaunch. Expected: signed in, no login screen, and the start-up user check (`GET /account/me`, `GET /profiles`) succeeds.
2. Expired token: leave Moonfin closed for over an hour (or overnight), relaunch. Expected: still signed in, and the log shows `POST /auth/refresh` before the first other request.
3. Revoked login: sign out of the Moonfin session from Silo's sessions page while Moonfin is closed, relaunch. Expected: Moonfin returns to the login screen.
4. Regression: relaunch with Emby active.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-13 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | `test/auth` 112/112; session/multi-server related tests 232/232; analyzer: no errors |
| 2026-10-14 | macOS (Brady) | 4b2e921c | Pass | Overnight relaunch (test 2) went well: stayed signed in. Tests 1, 3 and 4 run before committing. |

---

<a id="step-3-5"></a>
## 3.5 Refused refresh → back to sign-in

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 3.4 |

**Goal.** When Silo refuses the refresh token, forget that Silo user and route to the login screen.

**Where in Moonfin**

- `lib/auth/services/silo_token_storage.dart`
- `lib/auth/repositories/session_repository.dart`

**Earlier work to port:** stash

### How it works

A Silo login can end while Moonfin is running: someone signs the session out from Silo's sessions page, an admin revokes it, or the device sat idle past the refresh token's expiry. Silo then refuses the next refresh with a 401, and 2.1 ends the session (`onSessionEnded`). Before this step nothing listened. The session kept going with no tokens, and every request failed until the app was restarted. At start-up, 3.4 already covers it: the token check signs out.

**`SiloTokenStorage.bind`** now also listens for the end of the session:
- **Forgets the dead pair** (`removeSiloAccount`), so nothing restores a refresh token Silo has already refused (before, the next start would have tried it once more).
- Calls an optional **`onEnded`**.

**`SessionRepository`** passes `onEnded` when it restores the active session (3.4). `_onSiloLoginEnded` checks that the ended login is still the **active** session; a late callback for a session the person already left does nothing. It then does what a rejected token at start-up does:
- `destroyCurrentSession(tokenKnownInvalid: true)`: removes the stored user, sends no logout with the dead token, and clears the active client;
- opens the login screen with the server and the name filled in.

**Keeping the handler.** The multi-server rows restore the active client again (3.4), without an `onEnded`. `restore` now keeps an existing binding for the same (server, account) when no `onEnded` is given, so that second restore doesn't silently remove the sign-out handling. A restore *with* `onEnded` (the session repository) always rebinds. The binding is tracked per session in an `Expando`.

**Only a refused refresh does this.** A refresh that fails with a 503, a timeout or no network keeps the login (2.1), so a flaky connection never signs anyone out.

### Testing

**Automated tests**

- `test/auth/silo_session_restore_test.dart`, new group (5 tests):
  - a refused refresh forgets the stored pair, clears the session and calls `onEnded` once;
  - a later restore without `onEnded` (the multi-server rows) keeps the handler;
  - a restore with a new `onEnded` replaces the old one;
  - a 503 refresh ends nothing and keeps the stored pair;
  - `unbind` stops the reporting.
- `test/auth/silo_token_storage_test.dart`: the refused-refresh test now expects the stored pair to be forgotten.
- `SessionRepository._onSiloLoginEnded` itself isn't unit-tested. Driving `switchCurrentSession` to an active session needs most of the app's services. It reuses the start-up path (`destroyCurrentSession(tokenKnownInvalid: true)` and the login route), which `session_dead_token_test.dart` covers.

**Manual test plan**

- Nothing triggers it yet: at this stage Moonfin makes no requests after a session starts (Home and libraries are still placeholders), so a revoked login is only noticed at the next start (3.4, test 3). The live check is in step 6.4's test plan: revoke while browsing, open another library, and land on the login screen.
- Regression: sign in and out on Silo and Emby; full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | `test/auth` 117/117; analyzer: no new issues |
| | | | | |

---

<a id="step-3-6"></a>
## 3.6 Password change required

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** When sign-in returns `password_change_required`, show a change-password dialog, or at minimum a message pointing to Silo's web app.

**Silo v2 endpoints**

- `GET /account/password/capability`
- `POST /account/password`

**Where in Moonfin**

- `lib/ui/screens/auth/login_screen.dart`

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

<a id="step-3-7"></a>
## 3.7 Main profile has a PIN

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** When the account's main profile is PIN-locked, sign-in stops with a clear message instead of a generic error: PIN entry comes with the optional profiles phase (18.4), which lifts this.

**Where in Moonfin**

- `lib/auth/repositories/auth_repository.dart`
- `lib/ui/screens/auth/login_screen.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- the typed error from 2.5 becomes a readable login state

**Manual test plan**

- Give the main profile a PIN in Silo's web app, sign in: the message explains it. Remove the PIN afterwards.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---


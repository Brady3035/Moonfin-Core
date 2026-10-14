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
| ◐ Ready for testing | — | 3.1 |

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
| ☐ Not started | — | previous step |

**Goal.** The auth repository's Silo branch: sign in, find the main profile (2.5), store the user under the main profile's id with its tokens, and set the client's profile.

**Where in Moonfin**

- `lib/auth/repositories/auth_repository.dart`
- `lib/ui/screens/auth/login_screen.dart`

**Earlier work to port:** stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Sign in with your account; wrong password shows Silo's message.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-3-4"></a>
## 3.4 Restore the session on app start

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Set token and profile on the client, refreshing first when the access token has expired.

**Where in Moonfin**

- `lib/auth/repositories/session_repository.dart`

**Earlier work to port:** stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Quit and relaunch: still signed in. Leave it past token expiry and relaunch.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-3-5"></a>
## 3.5 Refused refresh → back to sign-in

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** When Silo refuses the refresh token, forget that Silo user and route to the login screen.

**Where in Moonfin**

- `lib/auth/services/silo_account_service.dart`

**Earlier work to port:** stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Revoke the session from Silo's web UI (account → sessions); Moonfin returns to sign-in.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
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


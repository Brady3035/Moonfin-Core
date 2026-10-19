# Phase 18: Household profiles (optional)

[← Roadmap](../ROADMAP.md)

Silo accounts can hold several household profiles, each with its own progress, favourites and settings, optionally locked with a PIN. Until this phase Moonfin acts as the account's main profile (decision D9). This phase makes each profile its own Moonfin user (decision D1), so the existing user switcher, per-user settings and offline data work per household member. Profiles of one account share one token pair. Optional: everything before it works without it. Moved here from phases 2 and 3 on 2026-10-13.

**Phase done when:** You can pick a profile (with PIN if locked), switch profiles without re-entering the password, and sign out of one profile or the whole account.

---

<a id="step-18-1"></a>
## 18.1 Profile PIN check

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** `verify-pin` → profile token with expiry; 429 lockout with `Retry-After`, not retried automatically.

**Silo v2 endpoints**

- `POST /profiles/{id}/verify-pin`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_profiles_api.dart`: `verifyPin`, `SiloPinResult` (`SiloPinAccepted`, `SiloPinRejected`, `SiloPinLocked`); `list` asks as the account
- `packages/server_silo/lib/src/silo_session.dart`, `silo_media_server_client.dart`: `siloNoProfileExtra` (a request without `X-Profile-Id` and `X-Profile-Token`)

**Earlier work to port:** silo-2 (`origin/silo-2-signin-api`: the same three answers; ported, now reading `Retry-After` through `SiloProblem.retryAfter`, and with the session's normal handling instead of `siloNoRefreshExtra`)

**Also in this commit:** the 17.6 fix hash `af9f217ec`; this file's second "18.3" section is 18.2 ("Store the household as users"), as the roadmap has it.

### How it works

A Silo profile can be locked with a PIN (1–72 characters, any text). Requests acting as a locked profile need, next to its `X-Profile-Id`, an `X-Profile-Token` proving the PIN was entered. `verifyPin(profileId, pin)` asks for one: `POST /profiles/{id}/verify-pin` with `{"pin": …}`, as the signed-in account (bearer token). The answer is one of:

- **`SiloPinAccepted(profileToken, expiresAt)`**: `valid: true` with a `profile_token`. The token is bound to this login session and to the profile's current PIN (Silo's `profile-verification-tokens.md`): it keeps working across token refreshes and stops when the login ends or the PIN is changed or cleared. `expires_at` is null when it has no other expiry (Silo's current build sends null).
- **`SiloPinRejected`**: `valid: false`. Silo counted the attempt.
- **`SiloPinLocked(retryAfter)`**: `429 rate_limited`. Five wrong PINs lock the profile for five minutes, during which every check is refused, the right PIN included; `Retry-After` gives the seconds left.

Anything else (no network, `404` for a profile deleted meanwhile) is thrown, for the dialog (18.4) to show.

**As the account.** Checking a PIN and listing the profiles are account-wide routes (`ProfileOptional` in Silo's registry): they don't need a profile, and a profile header naming a locked profile without its proof would get them refused, which is exactly the situation when a profile is about to be unlocked (or after a PIN was added on the web). The new request flag `siloNoProfileExtra` leaves both profile headers off; `verifyPin` and `list` always use it. (`useMainProfile` cleared the profile before listing for the same reason; that is now done by the flag.)

**Never sent twice.** Every check counts towards the lockout, so a PIN goes out only when the person entered it. The earlier branch marked the request `siloNoRefreshExtra`, which also skipped refreshing a due token first and could then fail with a `401`. Here the request goes through the session like any other: a token that is due is refreshed before it is sent, and the one replay the session makes is after a `401`, which Silo answers before it looks at the PIN (authentication comes first), so that attempt was never counted. No other retry exists in the Silo client.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_profiles_api_test.dart` (7 new, 15/15): a matching PIN gives the token and its expiry, and the request is a `POST` with `{"pin": …}` and the bearer token, fitting the pinned contract (`ProfilePINCheck`, `ProfileVerification`); a token without an expiry; a wrong PIN is rejected and sent once; a lockout gives `Retry-After` (287 s) and isn't retried; other failures are thrown, once; the profile id is escaped in the path; the check and the listing go out without the profile headers even while a profile and an old proof are set. `silo_users_api_test.dart`: `getCurrentUser`'s listing now goes out as the account (1 changed); `useMainProfile`'s test checks the selected profile in the client's headers instead of on a second listing (1 changed).

**Manual test plan**

Nothing to see in the app yet: the PIN dialog arrives with 18.4 and is tested there (correct PIN, wrong PIN, lockout message).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace, Flutter 3.47.7) | — | Pass | profiles API 15/15 (7 new); `server_silo` analyzer: no issues |
| | | | | |

---

<a id="step-18-2"></a>
## 18.2 Store the household as users

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** After sign-in, save every profile as a user (the main profile is already one, 3.3), share the account's token record between them, and continue straight in when there is only one unlocked profile.

**Silo v2 endpoints**

- `GET /account/me`, `GET /profiles` (as the account, 18.1)

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_users_api.dart`: `getHousehold` → `SiloHouseholdMember` (profile + Moonfin user)
- `lib/auth/services/silo_household.dart` (new): `SiloHousehold.store`
- `lib/auth/models/user.dart`: `PrivateUser.siloHasPin`
- `lib/auth/repositories/auth_repository.dart`: `_finishSiloHouseholdSignIn`; `lib/auth/models/login_state.dart`: `SiloChooseProfile`
- `lib/auth/repositories/session_repository.dart`: `_syncSiloHousehold` at each session start

**Earlier work to port:** stash (gone from Brady's repo: written fresh)

### How it works

Until now a Silo sign-in stored one Moonfin user, the account's main profile (D9). With profiles, every profile of the account is a Moonfin user (D1): the server's user grid, the account switcher, per-user settings, offline data and "last user" then work per household member, with no new screens.

**One login, several users.** A Silo login belongs to the account; its token pair is already stored once under (server, account) (3.2) and every refresh replaces it there (`SiloTokenStorage.bind`). The profiles' users only carry their profile id (the Moonfin user id) and the account id; none holds tokens of its own (`accessToken` keeps the access token at sign-in for the code that checks a stored user has one, as before). `AuthenticationStore.removeUser` already drops the account's tokens only with its last user.

**At sign-in** (password, code or after a temporary password, which all end in `_finishSiloSignIn`):

1. `getHousehold`: `GET /account/me` and `GET /profiles`, the profiles mapped to Moonfin users by the same mapper as the current user (2.6: name, avatar, administrator only for the main profile of an admin account), each with its `has_pin`.
2. The pair is saved and bound; `SiloHousehold.store` writes one user per profile (`siloHasPin` from Silo) and removes stored profiles of this account that Silo no longer lists (deleted on the web). A profile already stored keeps when it was last used and its download permission; a new one sorts last.
3. **A single profile without a PIN** goes straight in, as before: it acts as that profile, its downloads permission is read for it (15.1), it becomes the current user, and the screen goes Home.
4. **Anything else** (several profiles, or one with a PIN) answers the new `SiloChooseProfile`: the login is kept, nobody is the current user yet, and the login screen opens the user grid (18.3).

**Reading the goal.** The roadmap says "continue straight in when there is only one unlocked profile". Read literally, an account with a PIN-locked parent profile and an unlocked child profile would sign the parent in as the child. Here only a household of one profile skips the choice; with more than one, the person picks, as in Silo's own apps. Easy to change if Brady prefers the literal reading.

**Afterwards.** Profiles change on the web (a new profile, a PIN added, a rename). At every session start, after the user is read, the household is read again and stored the same way (`_syncSiloHousehold`, best effort). That is also how a login from before this phase, holding only the main profile, gets the other profiles without signing in again.

**Gated.** All of this runs only when `FeatureDetector.supportsProfiles` is on for Silo, which 18.8 does. Until then nothing changes; the tests turn it on through `AuthRepository(siloProfiles: true)`.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_users_api_test.dart` (1 new, 12/12): every profile comes back with its user, PIN flag and avatar; the listing goes out as the account; no downloads capability is read.
- `test/auth/auth_repository_silo_test.dart` (7 new): one profile without a PIN goes straight in and is stored; several profiles are all stored under the account with their PIN flags and administrator flags, the pair once, nobody current, `SiloChooseProfile`; one profile with a PIN asks to choose too; the household is read as the account; signing in again forgets a deleted profile, renames, and keeps when each was used; a household that can't be read ends the new login; a code sign-in stores the household the same way.
- `test/auth/private_user_silo_test.dart` (1 new): `siloHasPin` round-trips and isn't written for others.
- Not unit-tested: `_syncSiloHousehold` at session start (the session repository's start-up path has no Silo test harness); covered by the manual test.

**Manual test plan**

Visible only from 18.8 on, so tested with the batch. On Silo's web app, give the account a second profile ("Kid") and a third with a PIN ("Teen").

- a. Sign out of Silo in Moonfin and sign in with the password: the user grid shows Brady, Kid and Teen (18.3).
- b. Delete "Kid" on the web, restart Moonfin: Kid is gone from the switcher.
- c. An account with one profile and no PIN (a second test account, if there is one) goes straight to Home, as before.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace, Flutter 3.47.7) | — | Pass | users API 12/12 (1 new), `test/auth` all pass (8 new); analyzer: no new issues |
| | | | | |

---

<a id="step-18-3"></a>
## 18.3 "Who's watching" picker

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Route to the server screen's user grid when there is a choice to make.

**Where in Moonfin**

- `lib/ui/screens/auth/server_screen.dart`

**Earlier work to port:** stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Phone, desktop and TV (D-pad focus) layouts.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-18-4"></a>
## 18.4 PIN entry for locked profiles

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Free-text PIN dialog (Silo PINs are 1–72 characters), TV-focusable, showing the lockout time. Also lifts 3.7: a PIN-locked main profile can now be unlocked at sign-in.

**Where in Moonfin**

- `lib/ui/screens/auth/silo_profile_unlock.dart`

**Earlier work to port:** stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Correct PIN, wrong PIN, lockout message.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-18-5"></a>
## 18.5 Switch profile without signing in again

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Same client and tokens; swap `X-Profile-Id` and reload user-scoped state.

**Where in Moonfin**

- `lib/auth/services/silo_account_service.dart`
- `lib/ui/widgets/user_menu_dialog.dart`

**Earlier work to port:** stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Switch between two profiles; no password prompt; locked profile asks for PIN.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-18-6"></a>
## 18.6 Sign out of one profile vs the account

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Removing a profile only calls `logout` when it was the account's last profile on the device; add "Sign out of account" to remove all of them.

**Where in Moonfin**

- `lib/auth/repositories/session_repository.dart`
- `lib/ui/widgets/user_menu_dialog.dart`

**Earlier work to port:** stash (account sign-out was a known gap)

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Remove one profile: siblings still work. Remove the last: the server session ends.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-18-7"></a>
## 18.7 Which profile feeds cross-server rows

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** In the multi-server repository, use the active profile for the active server and the most recent unlocked profile for other Silo servers.

**Where in Moonfin**

- `lib/data/repositories/multi_server_repository.dart`

**Earlier work to port:** stash

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
<a id="step-18-8"></a>
## 18.8 Turn on `supportsProfiles` for Silo

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Flip the flag added in 1.2 so profile-only UI (avatars, the switcher entry) appears for Silo, and recheck every screen that reads it.

**Where in Moonfin**

- `packages/server_core/lib/src/feature_detector.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- feature detector table updated

**Manual test plan**

- Profile switcher visible on Silo, unchanged on Emby.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---


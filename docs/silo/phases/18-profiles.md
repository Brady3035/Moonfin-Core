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
| ◐ Ready for testing | — | previous step |

**Goal.** Route to the server screen's user grid when there is a choice to make.

**Where in Moonfin**

- `lib/ui/screens/auth/login_screen.dart`: `SiloChooseProfile` opens the server screen (`_openProfileChoice`), after a password or a code sign-in
- `lib/ui/screens/auth/server_screen.dart`: Silo avatars from the server's client; a lock under a PIN-locked profile

**Earlier work to port:** stash (gone: written fresh)

### How it works

Moonfin already has a "who's watching" screen: the server screen's user grid, which lists a server's stored users (and Jellyfin's public ones) and switches to the one picked. Since 18.2 stores every profile of a Silo account as a user of that server, the grid lists the household, and picking a profile switches to it with the stored login, no password (the same `switchCurrentSession` as any stored user: the account's pair and the profile's `X-Profile-Id`).

So the picker needs no new screen: when a Silo sign-in answers `SiloChooseProfile`, the login screen goes to `/server?serverId=…` instead of Home. That covers the password sign-in, the code sign-in (14.1) and the end of a temporary-password change (3.6). Phone, desktop and TV get the grid as they already lay it out (horizontal row, D-pad focus, arrows).

Two Silo details on the grid:

- **Avatars.** The grid built Jellyfin's `/Users/{id}/Images/Primary` for every server, which Silo doesn't have. A Silo profile's avatar comes from the server's client, which recorded the profile's `avatar_url` when it read the household (as the account switcher already does); without one the tile shows the person icon.
- **A lock** under the name of a profile with a PIN, so it is clear before choosing that it will ask (18.4).

**Not done here:** with two Silo accounts stored on the same server, their profiles appear side by side without saying which account each belongs to. The design note (reference §4.2.1) suggests the account name as a subtitle in that case; it's rare enough to leave until someone has it.

### Testing

**Automated tests**

- None new: the change is the routing of one state and the tile's image and lock. `flutter analyze` on both screens: no issues. The state itself is covered by 18.2's tests.

**Manual test plan**

With the batch (visible from 18.8), Brady's account with Brady, Kid and Teen (PIN):

- a. Sign out of Silo, sign in with the password: the grid opens with the three profiles, their avatars (or the person icon), and a lock under Teen.
- b. Pick Kid: Home loads as Kid (Kid's Continue Watching), no password asked.
- c. Sign in with a code instead (from another device): the grid opens the same way.
- d. TV (deferred to 17.5): D-pad moves across the profiles; select opens one.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace, Flutter 3.47.7) | — | Pass | analyzer: no issues in both screens; `test/auth` and `test/ui/screens/auth` pass |
| | | | | |

---

<a id="step-18-4"></a>
## 18.4 PIN entry for locked profiles

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Free-text PIN dialog (Silo PINs are 1–72 characters), TV-focusable, showing the lockout time. Also lifts 3.7: a PIN-locked main profile can now be unlocked at sign-in.

**Silo v2 endpoints**

- `POST /profiles/{id}/verify-pin` (18.1)

**Where in Moonfin**

- `lib/ui/screens/auth/silo_profile_unlock.dart` (new): `unlockSiloProfileIfNeeded`, `SiloPinDialog`
- `lib/auth/store/authentication_store.dart`: the PIN proofs under the account (`getSiloProfileToken`, `putSiloProfileToken`; `putSiloTokens(newLogin:)`)
- `lib/auth/services/silo_token_storage.dart`: `profileToken`, `needsPin`, `saveProfileToken`; `restore` sends the proof; `save(newLogin:)`
- `lib/auth/repositories/session_repository.dart`: a locked profile without a proof isn't switched to; `auth_repository.dart`: sign-in saves as a new login
- `lib/ui/screens/auth/server_screen.dart` (the grid), `lib/ui/widgets/user_menu_dialog.dart` (the switcher): ask before switching
- `lib/l10n/app_en.arb`: 7 strings (`siloPin…`)

**Earlier work to port:** stash (gone: written fresh)

### How it works

**When it asks.** Before switching to a Silo profile that is locked (`siloHasPin`, from Silo's household, 18.2) and has no live proof, the grid (18.3) and the account switcher call `unlockSiloProfileIfNeeded`. Nothing else changes in those screens: Moonfin's own app PIN (`PinCodeUtil`, a device lock on any user) still comes first when it is set; the Silo PIN is the server's lock on the profile.

**The dialog** (`SiloPinDialog`): "PIN for Teen", one obscured text field (Silo PINs are any text of 1–72 bytes, so not Moonfin's digit pad), Cancel and Unlock. Each Unlock sends the PIN once (18.1):

- right: the dialog closes, the proof is kept, and the switch goes on;
- wrong: "That PIN isn't right.", the field is emptied and keeps focus;
- locked (five wrong): "Too many wrong PINs. Try again in 5 minutes." (`Retry-After`, worded as in 17.3), or "… Try again later." without it;
- failed (no network, server error): "The PIN couldn't be checked. Try again." (or 17.3's texts for `429`/`503`);
- empty: nothing is sent; longer than 72 bytes: "That PIN isn't right." without spending an attempt.

On a TV the field works as in the temporary-password dialog (3.6): select opens the keyboard, down reaches Unlock.

**The proof.** Silo's `profile_token` is bound to the login (session) and the profile's PIN; it survives token refreshes and has no other expiry in the current build. It is stored next to the account's pair, under the profile (`siloAccounts[account].profileTokens[profile]`), so a restart and later switches don't ask again, as Silo's own apps do while a login lasts. A refresh keeps the proofs (`putSiloTokens` merges); a new sign-in (`save(newLogin: true)`) drops them, since Silo no longer accepts them; they go with the account's last user. `restore` puts the profile's proof on the client (`X-Profile-Token`) along with its id, and none for an unlocked profile, so switching from Teen to Kid doesn't carry Teen's proof along. An `expiresAt`, if Silo ever sends one, is honoured.

**Which login checks the PIN.** The check goes through the server's client as the account (no profile headers, 18.1). If that client holds no login (the grid after a restart) or another account's, the account's stored login is put on it first.

**No proof, no switch.** `switchCurrentSession` refuses a locked profile without a live proof (the caller asks first). At start-up that is what happens for "last user" or auto-login on a locked profile whose proof is gone (a new sign-in elsewhere ended it): the start-up screen sends the person to the server's grid, where tapping the profile asks for the PIN, instead of opening Home and having every request refused.

**3.7 is lifted.** With profiles, a sign-in never stops at "the main profile is locked" (`SiloMainProfileLocked`): the household is stored and the grid lets the person enter the main profile's PIN like any other. The old message stays for the main-profile-only mode (profiles off).

**Not done here:** a PIN added or changed on the web while Moonfin acts as that profile. Silo then refuses the old proof (`403 profile_verification_required`) on every request until the profile is chosen again; the household read at the next start marks it locked, and the grid asks. Handling it mid-session (ending the session and asking) is the open 3.7 question; Brady's call.

### Testing

**Automated tests**

- `test/ui/screens/auth/silo_pin_dialog_test.dart` (new, 7 tests): the title names the profile and the right PIN closes it unlocked; a wrong PIN stays open, says so and clears the field; a lockout says how long (287 s → "5 minutes"), or "later"; a failed check says so, and an empty PIN sends nothing; a PIN over 72 bytes is wrong without a check; Cancel closes it locked.
- `test/auth/authentication_store_silo_test.dart` (4 new): proofs are stored per profile under the account; a refresh keeps them and a new login drops them; null forgets one, and nothing is stored without a login; they go with the account.
- `test/auth/silo_session_restore_test.dart` (5 new): a locked profile needs its PIN until a proof is kept; an expired proof counts as none; restore sends the profile and its proof; switching to an unlocked profile drops the proof; a new sign-in drops the old login's proofs.

**Manual test plan**

With the batch, Teen locked with a PIN on Silo's web app:

- a. In the grid (or the switcher), pick Teen: "PIN for Teen". A wrong PIN: "That PIN isn't right."; the right one opens Teen's Home.
- b. Restart Moonfin (last user is Teen): Home opens as Teen without asking again.
- c. Switch to Kid and back to Teen: no PIN asked the second time.
- d. Sign out of the account and sign in again: Teen asks again (new login).
- e. Lockout: enter five wrong PINs: "Too many wrong PINs. Try again in 5 minutes."; even the right PIN is refused until then.
- f. Lock the main profile (Brady) with a PIN on the web, sign out, sign in: the grid opens and Brady asks for the PIN (3.7 lifted).
- g. TV (deferred to 17.5): select opens the keyboard on the PIN field, down reaches Unlock, back closes the dialog.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace, Flutter 3.47.7) | — | Pass | PIN dialog 7/7, store 12/12 (4 new), restore 17/17 (5 new); `test/auth`, `test/ui/screens/auth`, `test/l10n` 202/202; analyzer: no new issues |
| | | | | |

---

<a id="step-18-5"></a>
## 18.5 Switch profile without signing in again

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Same client and tokens; swap `X-Profile-Id` and reload user-scoped state.

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_media_server_client.dart`: changing `profileId` forgets the previous profile's reads (`_forgetProfileReads`)
- `packages/server_silo/lib/src/api/silo_items_api.dart`: `noteProfileChanged`

The roadmap also listed a `silo_account_service.dart` and changes to `user_menu_dialog.dart`; neither turned out to be needed (below).

### How it works

Most of this already works once the profiles are users (18.2). Switching to another stored user, from the account switcher or the server's grid, is `SessionRepository.switchCurrentSession`, the same as switching between two Jellyfin users of one server:

- **Same client.** The client factory keeps one client per server, and `SiloTokenStorage.restore` leaves a client alone when it already holds the account's current pair, so the login, its tokens and its refresh timer carry on. No password, no `POST /auth/login`, no refresh.
- **Another profile.** `restore` sets the profile's `X-Profile-Id` and, for a locked profile, its PIN proof (18.4); for an unlocked one, none.
- **User-scoped state.** The session switch already resets the app's per-user singletons (`resetUserScopedSingletons`), reconnects the events socket (a new ticket, minted for the new profile, 13.2), re-binds user-data sync to the new user id and reloads Home.

**What was missing: the Silo client's own reads.** The client keeps some answers for a while, and they belong to the profile they were read as: the libraries (5 min), Home's sections (1 min layout, 5 s cards), the read-once lists (2 min), the "hide watched items" setting (1 min), the items this profile changed recently (9.4), the downloads capability (1 min, 15.1) and the playback capabilities (1 min). Without forgetting them, a switch to Kid could show Brady's libraries and rows for a few minutes. Now setting a different `profileId` on a client that already acted as a profile forgets all of them (`_forgetProfileReads`; the item catalog itself, which is the same for every profile, is not touched beyond what `noteCatalogChanged` already clears). Picking a first profile (from none, after sign-in) has nothing to forget.

A request held back when the profile changes (waiting for a token refresh, or about to be replayed) is refused rather than sent as the new profile: the session stamps each request with the identity it started under, and a profile change moves it (2.2).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_profile_switch_test.dart` (new, 3 tests): another profile reads its own libraries, as itself (the cached list isn't reused); the same login stays (same token pair, no sign-in or refresh), with the new profile's proof on the request; picking a first profile forgets nothing.
- The switch itself (`switchCurrentSession`) has no new test: its success path needs the app's whole service graph. 18.4's tests cover what `restore` puts on the client.

**Manual test plan**

With the batch:

- a. As Brady, open the account switcher and pick Kid: Home reloads with Kid's rows (Kid's Continue Watching, Kid's libraries if they differ), no password.
- b. Mark something watched as Kid; switch back to Brady: Brady's state is unchanged.
- c. Switch to Teen: the PIN is asked the first time only (18.4).
- d. Silo web's sessions page shows one Moonfin session throughout (no new sign-ins).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace, Flutter 3.47.7) | — | Pass | profile switch 3/3 (new), `server_silo` 680/680; analyzer: no issues |
| | | | | |

---

<a id="step-18-6"></a>
## 18.6 Sign out of one profile vs the account

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Removing a profile only calls `logout` when it was the account's last profile on the device; add "Sign out of account" to remove all of them.

**Silo v2 endpoints**

- `POST /auth/logout`

**Where in Moonfin**

- `lib/auth/repositories/session_repository.dart`: `destroyCurrentSession` keeps the login while other profiles of the account are stored; `signOutSiloAccount`; `activeUserHasSiloSiblings`; a refused refresh removes all the account's profiles
- `lib/ui/widgets/user_menu_dialog.dart`: "Sign out of the Silo account"
- `lib/l10n/app_en.arb`: 1 string (`siloSignOutAccount`)

**Earlier work to port:** stash (account sign-out was a known gap; written fresh)

### How it works

`POST /auth/logout` ends the **login**, and on Silo the login is the account's, shared by every profile stored from it (18.2). Before, "Sign out" always called it: signing Kid out would have signed Brady and Teen out with it, while Moonfin still listed them.

- **Sign out** (the account menu's existing button) now signs out the **profile**: the user is removed from this device; `logout` is called, and the account's tokens forgotten, only when no other profile of the account is stored. The tokens already went with the account's last user (`AuthenticationStore.removeUser`); the logout now follows the same rule. Jellyfin and Emby users have no `siloAccountId` and sign out exactly as before.
- **Sign out of the Silo account** (new, in the account menu, shown only when the active user is a Silo profile with other profiles of its account stored): removes every profile of the account, then signs out as above, which is now the last profile, so the login ends on Silo. Other accounts on the same server and other servers are untouched (the existing "Sign out all users" still removes everything).
- **A login that ends on its own** (Silo refuses the refresh: revoked on Silo's sessions page, or expired, 3.5) ended for every profile, so all of the account's profiles are removed with it, not only the active one, and the sign-in screen opens as before.

### Testing

**Automated tests**

- `test/auth/session_silo_profiles_test.dart` (new, 5 tests, with a real `AuthenticationStore`): signing out one profile keeps its siblings, the account's tokens and the login (no `logout`); the last profile ends the login and the tokens go; signing out of the account removes every profile of it, ends the login once, and leaves another account's profile and tokens; another account on the server is not a sibling. Also 18.4's guard: a locked profile without its PIN isn't switched to (nothing acts as it).
- Not unit-tested: the refused-refresh path removing siblings (it needs a live Silo session in the session repository).

**Manual test plan**

With the batch, signed in as Brady with Kid and Teen stored:

- a. The account menu shows "Sign out of the Silo account" under Sign out; it doesn't for an Emby user, nor for a Silo account with one profile.
- b. As Kid, Sign out: back to the server list; Brady and Teen are still in the server's grid and open without a password. Silo web's sessions page still shows Moonfin's session.
- c. As Brady, "Sign out of the Silo account": the server's grid has no Silo profiles left (sign-in screen), and Moonfin's session is gone from Silo web's sessions page.
- d. Revoke Moonfin's session on Silo web while signed in as Kid: once the token is due (at most an hour, or restart), Moonfin goes to sign-in, and none of the account's profiles stays in the grid.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace, Flutter 3.47.7) | — | Pass | session profiles 5/5 (new); `test/auth` pass; analyzer: no new issues |
| | | | | |

---

<a id="step-18-7"></a>
## 18.7 Which profile feeds cross-server rows

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** In the multi-server repository, use the active profile for the active server and the most recent unlocked profile for other Silo servers.

**Where in Moonfin**

- `lib/data/repositories/multi_server_repository.dart`: `getLoggedInServers` picks another Silo server's profile with `SiloHousehold.profileForOtherServer`
- `lib/auth/services/silo_household.dart`: `profileForOtherServer`
- `lib/auth/repositories/session_repository.dart`: switching to a Silo profile records when it was used

**Earlier work to port:** stash (gone: written fresh)

### How it works

With more than one server signed in, Home, search and the library list can merge every server (`MultiServerRepository`): one `ServerUserSession` per server, read as one of its users. For the active server that is the active user, as before. For each other server Moonfin took the first stored user with a token, which on a Silo server with a household would be whichever profile happened to be stored first, possibly a child's or a locked one.

Now, for another **Silo** server, it is the **most recently used profile that can act without asking for a PIN** (unlocked, or locked with a live proof, 18.4): the household member who last used Moonfin with that server. A server whose profiles are all locked without a proof is left out of the merged rows rather than read as a locked profile (whose every request Silo would refuse). Profiles of one household are never merged into one row: they are the same library with different watch state and limits (design note §4.2.1). Jellyfin and Emby servers are chosen as before.

"Most recently used" needs the time to move: before, a user's `lastUsed` was only set at sign-in. Switching to a Silo profile now stamps it (Jellyfin and Emby users keep the old behaviour). The account switcher, which sorts by it, then also lists the household in the order it was used.

### Testing

**Automated tests**

- `test/auth/silo_household_test.dart` (new, 4 tests): the most recently used profile, not the first stored; a locked profile without its proof is skipped; a locked profile with a live proof counts; none when every profile is locked.
- `test/ui/screens/settings/other_server_collections_test.dart`, `test/ui/screens/home/other_server_collection_row_test.dart` (the existing multi-server tests): pass.

**Manual test plan**

Needs two signed-in servers, one of them Silo with Brady and Kid (Emby as the second):

- a. Use Kid on Silo, then switch to the Emby user. Home's merged rows (Continue Watching across servers, if the merged mode is on) show Silo items as Kid, not Brady.
- b. Switch to Brady on Silo, then back to Emby: Silo's items now come as Brady.
- c. With Teen (locked) the last used and its proof gone (sign the account in again), Silo's rows come from the most recent unlocked profile instead.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace, Flutter 3.47.7) | — | Pass | household 4/4 (new), multi-server tests pass; analyzer: no new issues |
| | | | | |

---
<a id="step-18-8"></a>
## 18.8 Turn on `supportsProfiles` for Silo

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Flip the flag added in 1.2 so profile-only UI (avatars, the switcher entry) appears for Silo, and recheck every screen that reads it.

**Where in Moonfin**

- `packages/server_core/lib/src/feature/feature_detector.dart`: `supportsProfiles` is true for Silo
- `README.md`, `docs/silo/wiki/Silo.md`: profiles are supported; `docs/silo/DECISIONS.md`: D1 and D9 say what was built

### How it works

Phase 18's sign-in, start-up and session code ask `FeatureDetector.supportsProfiles` whether a Silo account's profiles are users (`AuthRepository` and `SessionRepository` read it when they are made; their tests choose with `siloProfiles:`). It was false, so 18.2–18.7 changed nothing for a person until now; this step turns it on for Silo (`_isSilo`). Jellyfin and Emby stay false: their users are their own logins.

**Which screens read it.** When 1.2 added the flag it was meant for profile-only UI, but no screen ever read it: the account switcher, the server's user grid and the avatars already work for any stored users, and phase 18 reused them rather than adding profile-only screens. So the flag decides exactly what phase 18 added: storing the household at sign-in and at start (18.2), and through that everything after it (the grid as picker, PIN entry, switching, the account sign-out, the cross-server choice). With it off, Silo is back to the main profile alone (D9): that path stays and keeps its tests.

**Moving from the main profile.** Nothing to migrate: the main profile's user id was already its profile id (D9), so it stays the same user, with its settings and downloads. Its siblings appear at the next start (`_syncSiloHousehold`, 18.2).

**Docs.** The README's Silo section and the wiki draft (17.6) said profiles weren't supported; they now say how picking, PINs, switching and the two sign-outs work. D1 and D9 note that phase 18 was built.

### Testing

**Automated tests**

- `packages/server_core/test/feature_detector_test.dart`: `supportsProfiles` true for Silo (with the steps' other flags), still false for Jellyfin and Emby; `supportsClientLog`'s test now says 13.5 was declined rather than "not implemented yet" (HANDOFF's small item 8). 107/107.
- `test/auth/auth_repository_silo_test.dart`: the main-profile tests now ask for profiles off explicitly.
- The phase's app suites: `test/auth`, `test/ui/screens/auth`, `test/ui/widgets`, `test/data`, `test/l10n`, the multi-server tests: pass.

**Manual test plan**

The whole phase, on the Mac, with Brady's account given a "Kid" profile and a "Teen" profile with a PIN on Silo's web app (tests 18.2 a–c, 18.3 a–c, 18.4 a–f, 18.5 a–d, 18.6 a–d, 18.7 a–c), then:

- a. Emby: sign in, the switcher and the grid look as before; nothing asks for a Silo PIN.
- b. A Silo account with only one profile: sign-in goes straight Home, the account menu has no "Sign out of the Silo account".
- c. Upgrading: with the current build signed in as Brady (main profile only), install this build and start: Brady is still signed in; Kid and Teen appear in the switcher.
- d. Full suite (`flutter test` at the repo root).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace, Flutter 3.47.7) | — | Pass | feature detector 107/107; `server_silo` 680/680; `test/auth`, `test/ui/screens/auth`, `test/ui/widgets`, `test/data`, `test/l10n`, `test/offline`, `test/util`, the add-server dialog and the multi-server tests 2442/2442; analyzer on every file the phase changed: no new issues (the 3 left are upstream's) |
| | | | | |

---

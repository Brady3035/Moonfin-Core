# Phase 3: Sign-in and household profiles in the app

[← Roadmap](../ROADMAP.md)

Each Silo household profile is its own Moonfin user (decided Oct 8; see design reference §4.2.1). One account login = one token pair shared by its profiles.

**Phase done when:** You can sign in, pick a profile (with PIN if locked), switch profiles without re-entering the password, restart the app and stay signed in. Home is still empty until phase 5.

---

<a id="step-3-1"></a>
## 3.1 Silo fields on the stored user

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `PrivateUser` gains `siloAccountId` and PIN state, with backward-compatible JSON.

**Where in Moonfin**

- `lib/auth/models/user.dart`

**Earlier work to port:** stash `Add_silo`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- old JSON still loads; Silo fields round-trip

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-3-2"></a>
## 3.2 One token record per Silo account

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Store the token pair keyed by (server, account), shared by its profiles, and save refreshed tokens through a callback.

**Where in Moonfin**

- `lib/auth/store/authentication_store.dart`

**Earlier work to port:** silo-1/stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- two accounts on one server don't overwrite each other; refresh updates every sibling profile

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-3-3"></a>
## 3.3 Password sign-in from the login screen

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** The auth repository's Silo branch: sign in, store tokens, set the client's profile.

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
## 3.4 Store the household as users

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** After sign-in, save every profile as a user, and continue straight in when there is only one unlocked profile.

**Where in Moonfin**

- `lib/auth/services/silo_account_service.dart`

**Earlier work to port:** stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- An account with one profile goes straight in.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-3-5"></a>
## 3.5 "Who's watching" picker

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

<a id="step-3-6"></a>
## 3.6 PIN entry for locked profiles

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Free-text PIN dialog (Silo PINs are 1–72 characters), TV-focusable, showing the lockout time.

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

<a id="step-3-7"></a>
## 3.7 Switch profile without signing in again

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

<a id="step-3-8"></a>
## 3.8 Sign out of one profile vs the account

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

<a id="step-3-9"></a>
## 3.9 Restore the session on app start

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Set token and profile on the client, refreshing first when the access token has expired; auto-login only into profiles without a PIN or with an unexpired profile token.

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

<a id="step-3-10"></a>
## 3.10 Refused refresh → back to sign-in

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** When Silo refuses the refresh token, forget that account's household and route to the login screen.

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

<a id="step-3-11"></a>
## 3.11 Password change required

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

<a id="step-3-12"></a>
## 3.12 Which profile feeds cross-server rows

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

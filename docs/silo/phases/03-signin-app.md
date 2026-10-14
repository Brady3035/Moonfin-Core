# Phase 3: Sign-in in the app

[← Roadmap](../ROADMAP.md)

Moonfin signs in to the Silo account and acts as its main profile (decision D9). One Silo login is one Moonfin user. Choosing between household profiles, PINs and profile switching are the optional phase 18.

**Phase done when:** You can sign in, restart the app and stay signed in, and a refused login sends you back to sign-in. Home is still empty until phase 5.

---

<a id="step-3-1"></a>
## 3.1 Silo fields on the stored user

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `PrivateUser` gains `siloAccountId`, with backward-compatible JSON.

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
## 3.2 Store the Silo token pair

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Store the token pair with the user, keyed by (server, account), and save refreshed tokens through the session callback.

**Where in Moonfin**

- `lib/auth/store/authentication_store.dart`

**Earlier work to port:** silo-1/stash

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- two accounts on one server don't overwrite each other; a refresh saves the rotated pair

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


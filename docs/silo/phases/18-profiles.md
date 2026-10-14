# Phase 18: Household profiles (optional)

[← Roadmap](../ROADMAP.md)

Silo accounts can hold several household profiles, each with its own progress, favourites and settings, optionally locked with a PIN. Until this phase Moonfin acts as the account's main profile (decision D9). This phase makes each profile its own Moonfin user (decision D1), so the existing user switcher, per-user settings and offline data work per household member. Profiles of one account share one token pair. Optional: everything before it works without it. Moved here from phases 2 and 3 on 2026-10-13.

**Phase done when:** You can pick a profile (with PIN if locked), switch profiles without re-entering the password, and sign out of one profile or the whole account.

---

<a id="step-18-1"></a>
## 18.1 Profile PIN check

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

<a id="step-18-3"></a>
## 18.3 "Who's watching" picker

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** After sign-in, save every profile as a user (the main profile is already one, 3.3), share the account's token record between them, and continue straight in when there is only one unlocked profile.

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


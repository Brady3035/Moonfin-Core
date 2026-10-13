# Phase 14: Sign in with a code (QuickConnect equivalent)

[← Roadmap](../ROADMAP.md)

Silo's device sign-in maps onto Moonfin's QuickConnect calls.

**Phase done when:** A TV can sign in by approving a code from a phone, and the phone can approve another device.

---

<a id="step-14-1"></a>
## 14.1 Sign in on a TV with a code

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Start, poll (`poll_after`), sign in with the approved profile; show the verification URL and a QR code; Silo wording instead of "QuickConnect".

**Silo v2 endpoints**

- `GET /auth/device/capability`
- `POST /auth/device/start`
- `POST /auth/device/poll`

**Where in Moonfin**

- `silo_auth_api.dart`
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

<a id="step-14-2"></a>
## 14.2 Approve another device

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** From a signed-in phone.

**Silo v2 endpoints**

- `POST /auth/device/approve`

**Where in Moonfin**

- `silo_auth_api.dart`

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

<a id="step-14-3"></a>
## 14.3 Enable the entry points

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Turn on `supportsQuickConnect` for Silo and the bottom-nav entry.

**Where in Moonfin**

- `feature_detector.dart`
- `lib/ui/widgets/bottom_nav/bottom_nav_controller.dart`

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

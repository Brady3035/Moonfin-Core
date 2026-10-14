# Phase 17: Polish and launch

[← Roadmap](../ROADMAP.md)

Finish the fork's Silo support and prepare it for the upstream proposal.

**Phase done when:** Silo appears in the README's supported-server table and passes the full regression run.

---

<a id="step-17-1"></a>
## 17.1 Native port hint

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** When a bare host answers as Jellyfin on 8096 but `/api/v2/system/identity` answers on 8090, offer "This looks like a Silo server, use native mode?".

**Where in Moonfin**

- `lib/auth/repositories/server_repository.dart`

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

<a id="step-17-2"></a>
## 17.2 Local network discovery

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** mDNS `_silo._tcp`, verified with `/system/identity`.

**Where in Moonfin**

- `lib/auth/services/server_discovery_service_io.dart`

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

<a id="step-17-3"></a>
## 17.3 Error and update messages

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `426` → "server or app update required"; Retry-After texts.

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

<a id="step-17-4"></a>
## 17.4 Translations

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** New strings in `app_en.arb` and `flutter gen-l10n`.

**Where in Moonfin**

- `lib/l10n/app_en.arb`

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

<a id="step-17-5"></a>
## 17.5 Full regression pass

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Run the whole checklist on each platform against Silo and Emby; record results in each step.

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- _Write the checks before testing._

**Deferred platform checks.** Checks that need a device other than the Mac are collected here and run in this pass (Brady's rule, 2026-10-14). Each step's own Results row says which test was deferred.

| From | Platform | Check |
|---|---|---|
| 3.6 test 5 | Android TV (and other TVs) | Sign in to Silo with a temporary password and change it with the remote: select opens the on-screen keyboard on each field of the dialog; down moves to the next field, then to "Change password". |
| 4.1 test 3 | iOS or Android phone | With only Silo signed in, the bottom navbar tab picker doesn't offer Live TV; with Emby also signed in, it does. |

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-17-6"></a>
## 17.6 README and wiki

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Add Silo to Supported Servers with its minimum `api_major`, and list what isn't supported.

**Where in Moonfin**

- `README.md`

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

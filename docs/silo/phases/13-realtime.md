# Phase 13: Realtime events and app services

[← Roadmap](../ROADMAP.md)

Live updates and background services.

**Phase done when:** Watching on Silo web updates Moonfin's rows within seconds, and a server restart is handled.

---

<a id="step-13-1"></a>
## 13.1 Connectivity ping through the API

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Replace the hard-coded `/System/Ping` with `systemApi.ping()`.

**Where in Moonfin**

- `lib/data/services/connectivity_service.dart`

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

<a id="step-13-2"></a>
## 13.2 Events socket: connect and reconnect

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Ticket, subprotocols, reconnect before the 5-minute limit with a fresh ticket.

**Silo v2 endpoints**

- `POST /events/ws-ticket`
- `GET /events/ws`
- `GET /events/capabilities`

**Where in Moonfin**

- `lib/data/services/silo_events_socket_client.dart`

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

<a id="step-13-3"></a>
## 13.3 Events → user data and library changes

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Translate Silo events into the existing `UserDataChanged`/`LibraryChanged` messages.

**Where in Moonfin**

- `lib/data/services/websocket_message_parser.dart`

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

<a id="step-13-4"></a>
## 13.4 Access changed

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Re-fetch the user and profile, or sign out, when Silo says access changed.

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

<a id="step-13-5"></a>
## 13.5 Client log upload *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Send Moonfin's diagnostic log as a Silo diagnostics report.

**Silo v2 endpoints**

- `GET /diagnostics/capabilities`
- `POST /diagnostics/reports`

**Where in Moonfin**

- `silo_client_log_api.dart`

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

<a id="step-13-6"></a>
## 13.6 Household now playing *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Read-only list of what other profiles are watching.

**Silo v2 endpoints**

- `GET /profiles/household/sessions`

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

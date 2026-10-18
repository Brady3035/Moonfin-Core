# Phase 13: Realtime events and app services

[← Roadmap](../ROADMAP.md)

Live updates and background services.

**Phase done when:** Watching on Silo web updates Moonfin's rows within seconds, and a server restart is handled.

---

<a id="step-13-1"></a>
## 13.1 Connectivity ping through the API

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Replace the hard-coded `/System/Ping` with `systemApi.ping()`.

**Silo v2 endpoints**

- `GET /system/identity` (public; Silo has no ping route)

**Where in Moonfin**

- `lib/data/services/connectivity_service.dart`: the probe asks `client.systemApi.ping()`; its own Dio is gone
- `packages/server_core/lib/src/api/system_api.dart`: what a ping answers (`SystemApi.ping`'s contract), `SystemApi.pingTimeout`, `pingAnsweredDespite`
- `packages/server_jellyfin/lib/src/api/jellyfin_system_api.dart`, `packages/server_emby/lib/src/api/emby_system_api.dart`, `packages/server_silo/lib/src/api/silo_system_api.dart`: each `ping()` follows it

**Also in this commit: the phase 12 bookkeeping.** The 7 phase 12 hashes are filled in. 12.7 has Brady's macOS Pass row (2026-10-18) and is ticked in the roadmap. Brady deferred the web build (12.3): its checks a–d join the deferred table in 17.5, next to the device checks of 12.1, 12.2 and 12.4–12.6, which stay open there.

### How it works

`ConnectivityService` decides whether the server can be reached; an unreachable verdict sends every browse call to the downloads catalog. It used to ask with its own Dio, always for `<baseUrl>/System/Ping`. Silo has no such route: its native API answers `/api/v2/system/identity`, a public, tiny read every API node serves, and `SiloSystemApi.ping()` already used it (1.6). The probe now asks the client's own `systemApi.ping()`, so each server type pings its own route.

Asking the client instead of a bare request changes three things, and each is handled so the verdict stays what it was:

- **What counts as an answer.** The old probe counted a `401` as reachable: it sent no token, and Emby turns a token-less ping from outside its own network down with a `401`, which still came from the server. The clients' pings returned false for any error. `SystemApi.ping()` now documents the rule the probe needs, and all three implementations follow it through `pingAnsweredDespite`: a `401` is an answer; any other refusal (`404`: an address that isn't the server any more; `502`: a proxy with nothing behind it) and any network failure count as down. With the client's token the ping is normally a `200`; the `401` rule keeps a revoked token from sending the app offline, where signing in again would never be offered.
- **How long it waits.** The client Dios wait up to three minutes for an answer (Emby, Silo) or 30 seconds (Jellyfin). Each `ping()` now passes `receiveTimeout: SystemApi.pingTimeout` (5 s, the old probe's), so a server that takes the connection and then hangs is still judged in seconds. The connect timeout is the client's own, 8 s instead of 5 s.
- **Plain text.** Jellyfin and Emby ask for `/System/Ping` as plain text, as before, since a proxy can label the body as json.

The rest is unchanged: two attempts per probe (a pooled connection the server dropped fails like a server that went away), overlapping probes share one, the retry on a growing delay while the verdict stands. The probe now also carries the client's headers and goes through its interceptors: the request and its failures show in the network log like any other call, and on Silo a probe can refresh a token that is due.

### Testing

**Automated tests**

- `test/data/services/connectivity_service_test.dart`: the mock client's `systemApi` is now a real `EmbySystemApi` over the loopback server, so the existing cases (a lost probe, overlapping probes, a `401`, a plain text body labelled json, `404`/`502` down, the device offline) run through the client's ping. 1 new: the probe asks `/System/Ping` on Emby and `/api/v2/system/identity` on Silo. 8/8.
- `test/offline/offline_progress_sync_test.dart`: its fake client pings the same way. 22/22.
- `packages/server_emby/test/emby_system_api_test.dart` (new, 3 tests): `/System/Ping` as plain text within the timeout; a `401` counts; `404` and `502` don't.
- `packages/server_silo/test/silo_system_api_test.dart` (2 new): a `401` counts; the ping waits no longer than `pingTimeout`. `server_silo` 575/575, `server_core` 100/100, `server_emby` and `server_jellyfin` pass.

**Manual test plan**

On the Mac, with Silo signed in:

- a. Moonfin starts and browses normally (the probe at start says reachable). The network log shows `→ GET …/api/v2/system/identity` at start, and no `/System/Ping` request to Silo.
- b. Stop Silo (or block it): within a few seconds of a network change or the next retry, Moonfin switches to the downloads catalog (offline Home). Start Silo again: within 30 seconds Home comes back with live rows.
- c. Regression on Emby (`emby.snowystreams.com`): the same start and the same switch both ways; the log shows `/System/Ping` with a `200`.
- d. Full suite (`flutter test` at the repo root).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | connectivity 8/8, offline progress sync 22/22, Emby ping 3/3, `server_silo` 575/575, `server_core` 100/100; analyzer: no new issues in the changed files |
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

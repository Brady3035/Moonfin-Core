# Phase 13: Realtime events and app services

[← Roadmap](../ROADMAP.md)

Live updates and background services.

**Phase done when:** Watching on Silo web updates Moonfin's rows within seconds, and a server restart is handled.

---

<a id="step-13-1"></a>
## 13.1 Connectivity ping through the API

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

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
| ◐ Ready for testing | — | previous step |

**Goal.** Ticket, subprotocols, reconnect before the 5-minute limit with a fresh ticket.

**Silo v2 endpoints**

- `POST /events/ws-ticket`
- `GET /events/ws`
- `GET /events/capabilities`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_events_api.dart` (new): `SiloEventsApi` (capability, ticket, socket URL), `SiloEventsTicket`, `SiloEventsCapabilities`, `SiloEventFrame`; `SiloMediaServerClient.eventsApi`
- `lib/data/services/silo_events_socket_client.dart` (new, a part of `socket_handler.dart`): `SiloEventsSocketClient`, which replaces the idle `SiloWebSocketClient`
- `lib/data/services/socket_handler.dart`: the shared reconnecting client gains an `openChannel()` hook (Jellyfin and Emby open their URL as before) and calls off a connect that a disconnect overtook

### How it works

Moonfin keeps one socket per signed-in server (`SocketHandler`, opened by the session repository, dropped when the app idles in the background, retried when the network or the app comes back). Jellyfin and Emby put the token on the socket's URL. Until now Silo got an idle client that never connected. `SiloEventsSocketClient` now connects it, on the same reconnect, backoff, close and logging code as the other two (`_ReconnectingWebSocketClient`); only the opening and the connection's life differ.

**Opening** (`openChannel`, a new hook in the shared client whose default opens `buildUri()`, so Jellyfin and Emby are unchanged):

1. `GET /api/v2/events/capabilities`, once per client. Unless it says `state: available` and `allowed: true`, nothing is opened and nothing is retried; the next connect (app resume, network back) asks again. A server without the realtime service answers `not_configured` here.
2. `POST /api/v2/events/ws-ticket` through the Silo client, so it carries the login and the main profile (`X-Profile-Id`) and goes through the session interceptor: a token that is due is refreshed first, and a `401` (`token_refresh_required` after a role change) is refreshed and sent again. The route is `natural_idempotent`, so sending it twice is harmless. The ticket is single use and expires within 30 s; a new one is asked for on every connect.
3. The socket: `ws(s)://<server>/api/v2/events/ws?channels=user_state,catalog`, offering the subprotocols `silo.events.v2` then `silo.ticket.<ticket>`. Silo selects only the first. The ticket never goes in the URL or the log. Declaring the channels on the URL means no subscribe frame is owed; if Silo's `hello` still says `required_action: subscribe` (a declaration that took nothing), the client sends one for the same channels, since Silo closes a connection that subscribes to nothing within five seconds. Native platforms send no `Origin`, which Silo accepts.

**The connection's life.** Silo ends every connection after `max_connection_seconds` (300) or at the access token's expiry, whichever is first; tickets are minted with the token refreshed when less than a fifth of its hour is left, so the five minutes decide. The client renews 15 s before that: a connect closes the old socket and opens a new one with a fresh ticket. Renewals don't log "connected" every five minutes; failures still log. If the app was asleep past the limit, Silo's close comes first and the usual reconnect follows (about a second for the first try).

**A server restart.** The socket closes and the client keeps trying on the shared backoff (1 s doubling to 30 s, with jitter); each try mints a new ticket, which fails while the server is down. When the connectivity check sees the server again (13.1), it nudges the socket, which reconnects at once.

**A disconnect while opening.** Opening now takes a request before the socket exists, so a disconnect (app backgrounded, sign-out) can land in between. The shared client counts disconnects: a connect that was overtaken closes what it opened, and Silo's opening stops before the socket if the ticket came back too late. This also covers Jellyfin and Emby, where the window was the handshake alone.

Frames are parsed (`SiloEventFrame`) and the handshake ones handled (`hello`, `subscribed` refusals logged, `error` logged). What `event` and `snapshot` frames mean for the app is 13.3; `access_changed` is 13.4. `send()` drops everything: Jellyfin's and Emby's feeds (`SessionsStart`) mean nothing to Silo.

**Open:** a renewal leaves the server without a connection for the time a ticket and a handshake take (well under a second on the test server). An event in that gap is missed; the snapshot frames of the new connection are how 13.3 catches up.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_events_api_test.dart` (new, 11 tests): the captured capability document; a server without the service is not available; the ticket is a `POST` with the login and the profile, read from a fixture made from Silo's own contract fixture (`silo/events_ws_ticket.json`), offering the protocol first and the ticket second; a refusal reaches the caller; the socket URL (`wss` for `https`, a path prefix, the declared channels, no credential); frame parsing (`hello`, `subscribed` with a refusal, `event`, a null snapshot, not a frame).
- `test/data/services/silo_events_socket_client_test.dart` (replaces `silo_web_socket_client_test.dart`, 8 tests against a loopback Silo): Silo gets this client; it connects with the ticket in the subprotocols and the channels on the URL; it renews before the limit with a second ticket and closes the first socket (capability read once); a socket Silo closes comes back with a fresh ticket; a server with the socket off gets no ticket until it turns it on; a subscribe frame goes out when `hello` asks for one; a disconnect while the ticket is on its way opens nothing; no login, no request.
- `test/data/services/socket_handler_test.dart` 11/11 (Jellyfin's real-socket cases go through the new hook).

**Manual test plan**

On the Mac, with Silo signed in. The network log is in Moonfin's logs (or the console).

- a. After start: `GET /api/v2/events/capabilities`, `POST /api/v2/events/ws-ticket`, then "Silo WebSocket connected". No ticket text appears in the log.
- b. Leave Moonfin open for 15 minutes: a new `POST …/events/ws-ticket` about every 4¾ minutes, and no "Silo WebSocket closed, reconnecting" lines between them.
- c. Restart Silo (container restart) while Moonfin is open: "closed, reconnecting", then a few failed tickets, then "connected" again within about 30 s of Silo being back.
- d. Sign out of Silo, and switch to Emby: no Silo ticket requests after that. On Emby the socket connects as before (remote control from Emby's dashboard still reaches Moonfin, or the log shows "Emby WebSocket connected").
- e. Deferred to 17.5: on Android TV and iOS, background the app past the idle grace and come back: the socket reconnects with a new ticket.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | events API 11/11, socket client 8/8, socket handler 11/11, `server_silo` 586/586; analyzer: no new issues in the changed files |
| 2026-10-18 | Android TV, iOS | — | Deferred | check e in 17.5 |
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

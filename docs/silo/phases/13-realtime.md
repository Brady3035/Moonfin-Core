# Phase 13: Realtime events and app services

[← Roadmap](../ROADMAP.md)

Live updates and background services.

**Phase done when:** Watching on Silo web updates Moonfin's rows within seconds, and a server restart is handled.

---

<a id="step-13-1"></a>
## 13.1 Connectivity ping through the API

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `dfe202ff1` | previous step |

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
| 2026-10-18 | macOS | `bd9d59ea` | Pass | Brady: "the connectivity ping was good"; the full suite passes |
| | | | | |

---

<a id="step-13-2"></a>
## 13.2 Events socket: connect and reconnect

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `95c9cdd47`, fix `681e671b7` | previous step |

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

**Fix (2026-10-18): the socket's port.** Brady's first run on the Mac failed every connect with `Connection failed (… errno = 49), address = silo.snowystreams.com, port = 0`. Dart's `Uri` knows default ports only for `http` and `https`, so `wss://silo.snowystreams.com/…` reports port 0, and `dart:io`'s WebSocket connects to exactly that. The loopback tests always had an explicit port, so they passed. `socketUri()` now writes the port out (`wss://…:443/…`, `ws://…:80/…`, or the server's own).

**Open:** a renewal leaves the server without a connection for the time a ticket and a handshake take (well under a second on the test server). An event in that gap is missed; the snapshot frames of the new connection are how 13.3 catches up.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_events_api_test.dart` (new, 12 tests with the fix): the captured capability document; a server without the service is not available; the ticket is a `POST` with the login and the profile, read from a fixture made from Silo's own contract fixture (`silo/events_ws_ticket.json`), offering the protocol first and the ticket second; a refusal reaches the caller; the socket URL (`wss` for `https`, a path prefix, the declared channels, no credential); frame parsing (`hello`, `subscribed` with a refusal, `event`, a null snapshot, not a frame).
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
| 2026-10-18 | macOS | `bd9d59ea` | Fail | Brady: every connect failed with `port = 0` (`errno = 49`, "Can't assign requested address"); the socket URL had no port |
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | fix: the port written out; events API 12/12 (1 new) |
| 2026-10-18 | macOS | `bd9d59ea` | Pass | Brady, after the fix (`681e671b7`): passes; the full suite passes. Emby's socket had the same `port = 0` failure: fixed upstream instead (branch `fix-websocket-port`, a PR to Moonfin-Client), not on this branch |
| | | | | |

---

<a id="step-13-3"></a>
## 13.3 Events → user data and library changes

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `6a97dff79`, fix 13.3a | previous step |

**Goal.** Translate Silo events into the existing `UserDataChanged`/`LibraryChanged` messages.

**Silo v2 endpoints**

- `GET /events/ws` channels `user_state` (`user_state.changed`) and `catalog` (`catalog.item.changed`, `catalog.library.changed`)
- `GET /catalog/items/{id}` (to read back a changed item's user data)

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_events_translator.dart` (new): `SiloEventsTranslator`
- `packages/server_silo/lib/src/api/silo_items_api.dart`: `noteCatalogChanged()`; `noteUserDataChanged` uses it
- `lib/data/services/silo_events_socket_client.dart`: gathers event and snapshot frames for 300 ms and emits what the translator returns
- (`lib/data/services/websocket_message_parser.dart`, which the roadmap named: unchanged. Silo's frames aren't Jellyfin's, so they are translated next to the Silo client, where the read-back and the caches are.)

### How it works

On Jellyfin and Emby the socket sends `UserDataChanged` with each changed item's whole user data, and `UserDataSync` patches the cards every screen holds (Home, grids, details). `LibraryChanged` names the added, updated and removed items; the auto-download check and the admin screens follow it. Silo's events are different: they say *what* changed, not the new values. A `user_state.changed` event carries `profile_id`, `content_id`, `change` and only sometimes the new flag (`played`, `is_favorite`). Silo also sends it to every socket of the account, whichever profile changed.

`SiloEventsTranslator.translate(frames)` turns a batch of frames into Moonfin's messages:

- **`user_state.changed`** for the profile Moonfin acts as (others are dropped). Every change is noted on the Silo client (`noteUserDataChanged`): its home sections, lists and pages are read again on the next load, and the item counts as changed for the 9.4 refresh scope, so a screen's own refresh reads it. For `watched`, `favorite`, `progress` and `history`, the item is read back from Silo (`getItems(ids:)`, the item's detail) and its whole `UserData` (played, favourite, resume point, unplayed count for a show or season) goes out in one `UserDataChanged` for the signed-in user, as Jellyfin would send it. A read that fails passes on what the event said. A batch reads at most 25 items; the rest pass on the event's flags. `watchlist`, `home_dismissal` and `not_interested` change nothing a card shows in Moonfin, so they are only noted.
- **`catalog.item.changed`** (an item's metadata): the Silo lists are read again, and `LibraryChanged` with the item in `itemsUpdated`.
- **`catalog.library.changed`** (a scan): the Silo lists are read again. Silo names counts, not items, so there is no `LibraryChanged` to send. The legacy names Silo sends alongside (`library.changed`, `library.item_added`, `metadata.updated`) repeat these and are ignored.
- **Snapshots**, sent for each channel on every connect: changes may have been missed while the socket was down or renewing, so the Silo lists are read again. Nothing is passed on.

The socket client gathers frames for 300 ms before translating, so a burst (a season marked watched sends one event per episode) reads each item once.

**Not implemented (Brady, 2026-10-18): live resume points from playback elsewhere.** Silo publishes no event when playback saves progress or stops (v2 `persistProgress` and `persistStopAndHistory`, and the Jellyfin-compat path); only the writes above do. So watching on Silo web doesn't move Moonfin's resume bars until a reload. Brady: not important. The fix would be on Silo's side (publish `user_state.changed` `progress` from those paths); this translator would pass it on unchanged.

**Fix 13.3a, this client's own playback (Brady, 2026-10-20: a finished episode stayed unwatched in the season list).** The same gap covers Moonfin's own playback: Silo publishes nothing when a session stops, and the Jellyfin and Emby path relies on their socket's `UserDataChanged` after a stop, so no screen heard the episode was finished. Now `SiloPlaySessionService` calls `SiloMediaServerClient.notePlaybackEnded(itemId)` once Silo has the stop (or had already ended the session). That notes the item for the 9.4 scope and adds it to `ownUserDataChanges`; the events socket client passes each one to the translator as the `user_state.changed` `progress` Silo would have sent, so the item is read back and goes out as `UserDataChanged`, connected or not. The season list then shows the tick, and the series and season pages refresh their counts on return (`syncUserDataIfStale`). A refused stop notes nothing. Playback on other devices is still the known gap above.

### Testing

**Automated tests**

- (13.3a) `packages/playback_silo/test/silo_stop_test.dart` (3 new, 9/9): the client hears the item changed once Silo has the stop, and when the session had already ended; not when the stop was refused. `test/data/services/silo_events_socket_client_test.dart` (2 new, 16/16): an own finished playback comes out as `UserDataChanged` with what Silo holds, with no socket connected; a disposed socket passes nothing on.
- `packages/server_silo/test/silo_events_translator_test.dart` (new, 9 tests): a change on the web passes on the item's user data as Silo holds it (resume point, favourite); two events for one item read it once; another profile's change is dropped; an unreadable item passes on the event's flag; `watchlist`, `home_dismissal` and `not_interested` only note the item (it is in the 9.4 scope); a burst reads back at most 25; `catalog.item.changed` gives `LibraryChanged` once despite the legacy duplicate; a scan and a snapshot pass nothing on.
- `test/data/services/silo_events_socket_client_test.dart` (1 new, 9/9): events from the loopback socket come out as one `UserDataChanged` (only this profile's, read back) and one `LibraryChanged`.

**Manual test plan**

On the Mac, with Moonfin open on Home and Silo web open in a browser as the same main profile:

- a. On the web, mark a film Moonfin shows on Home (or in a library grid) watched: within a couple of seconds its card in Moonfin shows the watched tick, without a reload. Mark it unwatched again: the tick goes.
- b. On the web, favourite a film: Moonfin's detail page of that film (left open) shows it as a favourite within seconds.
- c. Mark a whole season watched on the web while Moonfin shows that season's episodes: the episodes show watched (the read-backs show in the network log, one per episode up to 25).
- d. A change from another profile on the web (if the account has one) changes nothing in Moonfin.
- e. Known, not implemented: playing something on the web doesn't move its resume bar in Moonfin until a reload.
- f. (13.3a) Open a season, play an episode in Moonfin to the end (or past the watched threshold) and go back: the episode shows watched in the season list, and the season's and the show's unwatched counts drop. Stop another one part way: its resume bar shows.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | translator 9/9, socket client 9/9; analyzer: no new issues in the changed files |
| 2026-10-18 | macOS | `bd9d59ea` | Pass | Brady: "tests are good" |
| | | | | |

---

<a id="step-13-4"></a>
## 13.4 Access changed

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `73418891f` | previous step |

**Goal.** Re-fetch the user and profile, or sign out, when Silo says access changed.

**Silo v2 endpoints**

- `GET /events/ws`: the `access_changed` frame and close code `4001`
- `POST /events/ws-ticket` (the reconnect; `403 profile_verification_required`)
- `GET /account/me`, `GET /profiles` (the user, read again through `getCurrentUser`)

**Where in Moonfin**

- `lib/data/services/silo_events_socket_client.dart`: `onServerClosed`, the `access_changed` frame, the PIN refusal
- `lib/data/services/socket_handler.dart`: the shared client's `onServerClosed(closeCode)` hook; true reconnects at once
- `packages/server_silo/lib/src/api/silo_events_api.dart`: `siloEventsAccessChangedCloseCode`, `siloAccessChangedEvent`
- `lib/auth/repositories/session_repository.dart`: `_onSiloAccessChanged`; the user refresh of `_postLoginSync` moved into `_refreshServerUser`, which both use

### How it works

Silo rechecks every connection's login every 15 s. When the login is still good but what it may see has changed, it sends `{"type":"access_changed"}` and closes with `4001` (`access_changed`). That covers a change of the account's role or group, its libraries, rating or quality limits, the profile's hidden libraries or metadata language, and the server's unrated-content setting (Silo's `docs/realtime-api.md`, "Access changes"). A revoked login, a disabled account or a deleted one closes without the frame; the next request is refused and the session ends as before (3.5).

On the frame or the close code (either is enough):

1. **The Silo client forgets what the old access decided:** the library list (`userViewsApi.invalidateCache()`), and the home sections, lists and pages (`noteCatalogChanged()`).
2. **The app is told:** the socket emits `ServerEventMessage(type: 'SiloAccessChanged')`. The session repository reads the user again (`getCurrentUser`: the account and the main profile, so `isAdministrator`, downloads, collections and the language preferences follow), stores what changed, and asks Home to reload. That is the code `_postLoginSync` already ran after sign-in, now in `_refreshServerUser`, so a `401` there ends the session and goes to sign-in, as at start. Screens opened later read the new access themselves; a screen already open keeps what it shows until it reloads.
3. **The socket reconnects at once** with a new ticket, without the backoff (the shared client's new `onServerClosed` hook answers true). After a role change the old token was minted under the old role, so the ticket answers `401 token_refresh_required`; the session interceptor refreshes and sends the ticket again (2.2), and the new ticket carries the new access, so the socket doesn't close again for the same change.

**A profile that needs its PIN again.** If the main profile gains a PIN (or its PIN changes) after sign-in, its PIN proof stops verifying, and the ticket answers `403 profile_verification_required`. Every ticket would be refused the same way, so the socket stops and logs it, rather than asking every 30 s. What the app should do then (sign out, or ask for the PIN) is the open 3.7 question, so it isn't decided here; the rest of the app meets the same refusal on its next request.

### Testing

**Automated tests**

- `test/data/services/silo_events_socket_client_test.dart` (5 new, 14/14): an `access_changed` frame with close `4001` reaches the app as `SiloAccessChanged` and reconnects in well under the backoff's second, with a second ticket; the close code alone is enough; an ordinary close is not an access change; a ticket refused with `profile_verification_required` isn't retried; another refused ticket is.
- `test/data/services/socket_handler_test.dart` 11/11; `test/auth` 135/135 (the session repository's sign-in paths).

**Manual test plan**

On the Mac, with Moonfin open on Home and Silo web open as the same account:

- a. In Silo web, hide a library in the profile's settings (or change the profile's metadata language). Within about 15 s Moonfin's log shows "Silo says this login's access changed", a new `POST …/events/ws-ticket` follows at once, and Home reloads without the hidden library. Show it again: it comes back the same way.
- b. As the admin, change the account's access in Silo's admin (another account, if Brady has a test user: remove a library from its group). That account's Moonfin drops the library within about 15 s.
- c. Regression: a sign-in on Silo and on Emby still lands on Home with the right permissions (the settings show the admin entry for an admin).
- d. Optional, if a spare profile setup allows: set a PIN on the main profile while Moonfin is open. The log shows "Silo events socket stopped: the profile needs its PIN" and no more ticket requests. (What Moonfin should do then is the open 3.7 question.)

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | socket client 14/14, socket handler 11/11, `test/auth` 135/135, `server_silo` 595/595; analyzer: no new issues in the changed files |
| 2026-10-18 | macOS | `bd9d59ea` | Pass | Brady: "works" |
| | | | | |

---

<a id="step-13-5"></a>
## 13.5 Client log upload *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ⊘ Declined (Brady, 2026-10-18) | — | previous step |

Not built: Brady declined it as not needed (2026-10-18).

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
| ⊘ Declined (Brady, 2026-10-18) | — | previous step |

Not built: Brady declined it as not needed (2026-10-18).

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

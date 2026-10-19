# Phase 17: Polish and launch

[← Roadmap](../ROADMAP.md)

Finish the fork's Silo support and prepare it for the upstream proposal.

**Phase done when:** Silo appears in the README's supported-server table and passes the full regression run.

---

<a id="step-17-1"></a>
## 17.1 Native port hint

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `dc0c3a060` | previous step |

**Goal.** When a bare host answers as Jellyfin on 8096 but Silo's native API answers on 8090, offer "This looks like a Silo server, use native mode?".

**Silo v2 endpoints**

- `GET /api/v2/system/info` (and the identity, branding and setup reads the probe already makes)
- Silo's Jellyfin-compatible `GET /Branding/Configuration` (not v2: the fingerprint)

**Where in Moonfin**

- `packages/server_core/lib/src/network/server_probe.dart`: `probeSiloServer` (the native half of `probeServerPublicInfo`, now public) and `looksLikeSiloJellyfinCompat`
- `lib/auth/repositories/server_repository.dart`: `addServer(…, offerSiloNative:)`, `_findSiloNative`, `siloNativePorts`
- `lib/auth/models/silo_native_offer.dart` (new): `SiloNativeOffer`, `SiloNativeOfferHandler`
- `lib/ui/widgets/silo_native_offer_dialog.dart` (new): `confirmSiloNativeServer`; `lib/ui/screens/auth/server_select_screen.dart`: the add-server dialog passes it
- `lib/l10n/app_en.arb`: 4 strings (`siloNativeOffer…`)

**Also in this commit:** the 10.7 second fix hash `b089477d2` in 10.7's status cell (still ◐ until Brady's Windows retest).

### How it works

Silo serves two APIs: its own (`/api/v2`) and a Jellyfin-compatible one for Jellyfin apps, normally on separate ports of the same host. Someone who already uses Silo with Jellyfin apps is likely to type the address they know, which is the compat one, and Moonfin then adds the server as Jellyfin: everything works, but through Jellyfin's API, without the Silo-only features of this branch.

**Recognising the compat service.** It answers `/System/Info/Public` as `"ProductName": "Jellyfin Server"`, like a real Jellyfin, and its id defaults to one fixed value on every install, so neither tells them apart. What does is `/Branding/Configuration`: Silo's disclaimer always reads "Silo provides Jellyfin-compatible app support. Silo is not affiliated with or endorsed by the Jellyfin project." (`internal/jellycompat/handlers_system.go`). `looksLikeSiloJellyfinCompat` checks that the disclaimer names Silo. It is only a hint, and never throws; a real Jellyfin costs this one extra request when it is added, nothing more.

**Finding the native API.** Only after the hint, `_findSiloNative` probes the same host on Silo's native ports, all at once with a 3-second connect timeout: 8090 (what Silo's `docker-compose.yml` publishes, `${PORT:-8090}:8080`) and 8080 (the listener's own default, `PORT`), on the compat address's scheme first and plain `http` after (Silo's listener speaks HTTP; HTTPS normally comes from a proxy in front). Each candidate goes through `probeSiloServer`, the same check that recognises a Silo address typed directly (`/api/v2/system/info` with `api_major` and `server_version`, then identity, branding and setup), so what is offered is a server Moonfin would add anyway. The first port in that order that answers wins.

**Offering it.** `addServer` takes an optional `offerSiloNative` handler. The add-server dialog passes one that asks: "Connect to Silo directly?", "This address is the Jellyfin-compatible service of the Silo server *Snowy Streams*. Moonfin can connect to Silo directly at *http://192.168.1.20:8090*, with Silo's own features." with **Use Silo** (focused, so a remote's select takes it) and **Keep Jellyfin**. Use Silo adds the native server (named and versioned from Silo's branding and system info, as a typed Silo address would be); Keep Jellyfin, or closing the dialog, adds the address as entered, as before. Nothing is remembered: adding the same compat address again asks again.

The other callers of `addServer` pass no handler and behave exactly as before: the web build's configured address, a discovered server (Jellyfin's UDP discovery; Silo doesn't answer it) and the self-signed retry.

**Why not on every Jellyfin address:** without the fingerprint, every Jellyfin server added would wait for probes on two more ports, up to the timeout on a firewalled host. With it, only Silo's compat service pays for them.

### Testing

**Automated tests**

- `packages/server_core/test/server_probe_test.dart` (4 new): the disclaimer that names Silo is recognised; a Jellyfin disclaimer, an HTML page and a `404` aren't; `probeSiloServer` finds a native host and answers null for a Jellyfin one.
- `test/auth/server_repository_silo_test.dart` (5 new, real local servers for the compat and the native API): Silo's compat service offers the native server with its address and name, and yes adds it as Silo; no adds the compat address as Jellyfin; a real Jellyfin offers nothing; nothing is offered when no native Silo answers; without a handler the compat address is added as before.

**Manual test plan**

Brady's Silo serves the compat API on 8096 and the native API on 8090 on the same machine (adjust the host to his LAN address).

- a. Add server `http://<silo host>:8096`: "Connect to Silo directly?" names the server and `http://<silo host>:8090`. Use Silo: the server is added with Silo's icon, and signing in goes to Silo's sign-in (code view).
- b. Remove it, add `http://<silo host>:8096` again, Keep Jellyfin: added as a Jellyfin server, as before this step.
- c. Add `<silo host>` with no scheme or port: Moonfin tries its usual candidates; if it lands on 8096 (compat), the same question appears.
- d. Add the public `https://silo.snowystreams.com`: it is the native address already, so no question, added as Silo.
- e. Add Emby (`https://emby.snowystreams.com`): no question, no delay.
- f. On a TV (deferred to the 17.5 table): the remote's select takes Use Silo, back keeps Jellyfin.
- g. Full suite (`flutter test` at the repo root).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace) | — | Not run | this session's network refused pub.dev and storage.googleapis.com: no Flutter, so Claude neither compiled nor tested the batch; Brady ran the analyzer and tests |
| 2026-10-19 | macOS | `bd9d59ea` | Pass | Brady: a–e pass, tests good |
| 2026-10-19 | Android TV, Apple TV | — | Deferred | check f in the table below |
| | | | | |

---

<a id="step-17-2"></a>
## 17.2 Local network discovery

| Status | Commit | Depends on |
|---|---|---|
| ◐ Device checks in 17.5 | `653b75423` | previous step |

**Goal.** mDNS `_silo._tcp`, verified with `/system/identity`.

**Silo v2 endpoints**

- DNS-SD over multicast DNS: `_silo._tcp.local` (PTR, SRV, TXT `v`/`id`, A/AAAA), Silo's `internal/landiscovery`, described in its `docs/architecture/server-discovery.md`
- `GET /api/v2/system/info`, `GET /api/v2/system/identity`, `GET /api/v2/theme/branding` (through `probeSiloServer`, 17.1)

**Where in Moonfin**

- `lib/auth/services/silo_lan_discovery.dart` (new): `buildSiloBrowseQuery`, `SiloMdnsRecords` (a small DNS message reader), `SiloLanAdvert`, `SiloLanBrowser`
- `lib/auth/services/server_discovery_service_io.dart`: the Silo browse runs next to the Jellyfin/Emby UDP broadcast; `_discoverSilo`, `_confirmSilo`
- `android/app/src/main/kotlin/org/moonfin/androidtv/MainActivity.kt`: `acquireMulticastLock` / `releaseMulticastLock` on the platform channel
- `ios/Runner/Info.plist`, `macos/Runner/Info.plist`: `_silo._tcp` in `NSBonjourServices`; the local-network text names Silo
- `test/fixtures/silo_mdns.json` (new): packets made by Silo's own record builder

### How it works

The server list's "Discovered servers" comes from Jellyfin's UDP broadcast ("who is JellyfinServer?" on 7359), which Jellyfin and Emby answer. Silo doesn't answer it on purpose (its compat id is the same on every install, so every Silo would look like one server); instead every Silo API process advertises itself with DNS-SD over multicast DNS, as `_silo._tcp.local`. The instance name is the server's name, SRV gives its host and port (plain HTTP), A/AAAA its addresses, and TXT `id=` the server id that `GET /api/v2/system/identity` answers.

**No new dependency.** Brady's choice (2026-10-19): rather than `multicast_dns` or `bonsoir`, a small browser of our own, as Silo wrote its own small responder. It needs to read five record types and send one question, about 300 lines with the socket code.

- **The question.** `buildSiloBrowseQuery`: one PTR question for `_silo._tcp.local`, id 0, asking for multicast answers. Silo answers on the link by multicast, never to the sender, and **only answers queries sent from port 5353** (so its listener can't be used to reflect traffic). `SiloLanBrowser` therefore binds UDP 5353 with address and port reuse (shared with the system's mDNSResponder or avahi; `reusePort` isn't available on Windows), joins `224.0.0.251` on every IPv4 interface, and sends the question out of each interface (`IP_MULTICAST_IF`), twice, a second apart. It listens for 2.5 s, as the UDP broadcast does.
- **The answers.** `SiloMdnsRecords` reads every packet heard: queries (its own looping back, other browsers') are skipped; PTR names the instance, SRV its port and host, TXT its `id`, A and AAAA the host's addresses. Names may be compressed; a pointer loop or a truncated packet stops the read of that packet only. A record with TTL 0 is a goodbye and removes what it names. Link-local IPv6 is skipped (a URL can't carry its scope; Silo doesn't send it anyway). An instance name can contain dots ("Brady's Silo v2.0" is one label), which is why instances are recognised by the suffix `._silo._tcp.local`.
- **Trust.** An advert is a hint: anyone on the network can send one. Adverts are grouped by `id` (one deployment is heard once per API process and per interface), and for each, Moonfin probes `http://<address>:<port>` (IPv4 first, IPv6 in brackets) with `probeSiloServer`; the server is listed only when the identity's `server_id` equals the advertised `id`, under the address that answered, named from Silo's branding (as Silo's guide asks: instance names aren't unique, "Silo (2)"). An advert without an `id` is ignored. Choosing it is then the same as typing that address.
- **Android** drops multicast on Wi-Fi unless the app holds a multicast lock (the manifest already has `CHANGE_WIFI_MULTICAST_STATE`, used by DLNA discovery). The browse asks the platform channel for one and releases it as soon as listening ends.
- **Apple:** iOS already has the multicast entitlement (`com.apple.developer.networking.multicast`) that raw mDNS needs; `_silo._tcp` is added to `NSBonjourServices` next to `_jellyfin._tcp` and `_emby._tcp`. macOS's sandbox already allows a listening socket.
- **Both at once.** `discoverLocalServers` runs the Silo browse alongside the broadcast and closes the list when both are done (the Silo side can take a little longer, for its identity checks). A failed Silo browse (port 5353 refused, say) is logged and leaves the broadcast's results; a failed broadcast no longer hides Silo's.

**Not done here:**

- The web build can't do mDNS. Its discovery probes ports 8096 and 8920 on nearby addresses; adding 8090 there would find Silo on the web too. Brady (2026-10-19): no, leave it.
- A Silo saved under another address (Brady's public `https://silo.snowystreams.com`) also shows under Discovered with its LAN address, because the list hides saved servers by address only (as for Jellyfin). `Server` doesn't store the server id it was added with; storing it would let the list hide by id. Brady (2026-10-19): leave it for now.
- Overlay networks (Tailscale's `http://silo/`) don't carry multicast; Silo's guide describes a separate probe of the bare name. Not in the roadmap.

### Testing

**Automated tests**

- `test/auth/silo_lan_discovery_test.dart` (new, 18 tests). The packets in `test/fixtures/silo_mdns.json` were made by Silo's own record builder (`internal/landiscovery/records.go` at `365e3d4`, run in Claude's workspace): its reply to Moonfin's exact query bytes (which its `asksAbout` accepted), its start announcement and its goodbye, each also with name compression. The query's bytes; Silo's answer read with name, id, port and addresses (IPv4 first, no link-local), plain and compressed; the announcement; a goodbye withdraws the server; a dotted instance name stays whole; two servers; queries ignored; a truncated packet keeps what came before it; a pointer loop is dropped. The discovery service with a fake browser and probe: a matching identity is listed under the address that answered and named from branding; another identity isn't; a dead address moves on to the next; one deployment heard twice is listed once; an advert without an id is ignored; a failed browse ends the list quietly.

**Manual test plan**

On the Mac, on the same network as Brady's Silo (Silo logs "advertising Silo on the local network" at start; `server.lan_discovery` is on by default):

- a. Optional: `dns-sd -B _silo._tcp` in Terminal lists the server.
- b. Open the server list (sign out of Silo, or Add server): Discovered servers shows the Silo server with Silo's icon, named as in Silo's branding, with its LAN address (`http://<ip>:8080`, or the port Silo listens on: inside Docker the advert carries the container's port, see below). Jellyfin/Emby servers on the network still show.
- c. Choose it: the add goes straight to Silo's sign-in.
- d. Rename the server in Silo's admin settings, wait 30 s, search again: the new name shows.
- e. Stop Silo (or turn off `server.lan_discovery`): within a search it is gone.
- f. Deferred to 17.5: Android TV and an Android phone on Wi-Fi (the multicast lock), iPhone (the local-network permission prompt names Silo), Windows and Linux.

**Docker:** Silo advertises the port its process listens on, not the one Docker publishes (`8090:8080`), and only on networks the container is attached to. With the default bridge network nothing reaches the LAN, so discovery finds nothing; with `network_mode: host` it advertises 8080. Silo's guide covers this with `server.local_url`, which needs a signed-in client. Worth checking how Brady's server runs before testing.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace) | — | Not run | this session's network refused pub.dev and storage.googleapis.com: no Flutter, so Claude neither compiled nor tested the batch; Brady ran the analyzer and tests |
| 2026-10-19 | macOS | `bd9d59ea` | Deferred | Brady's Silo runs in Docker, so it can't advertise on the LAN unless the container uses host networking; a–e deferred to 17.5 (row 17.2 f) |
| | | | | |

---

<a id="step-17-3"></a>
## 17.3 Error and update messages

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `5a636ab6e` | previous step |

**Goal.** `426` → "server or app update required"; Retry-After texts.

**Silo v2 endpoints**

- `GET /api/v2/system/info` (`api_major`)
- Any route: `410 client_upgrade_required` (a retired API), `426 client_upgrade_required` (playback start), `429 rate_limited` and `503` with `Retry-After`

**Where in Moonfin**

- `packages/server_core/lib/src/network/silo_public_info.dart`: `siloSupportedApiMajor` (2), `SiloApiUnsupported`, `isSiloClientUpgradeRequired`; `server_probe.dart`: the probe reports the tombstone
- `lib/util/silo_failure_message.dart` (new): `SiloFailure` (`SiloUpdateRequired`, `SiloTryAgainLater`) and its texts
- `lib/auth/repositories/server_repository.dart`, `lib/auth/models/server_addition_state.dart` (`unsupportedSilo`), `lib/ui/screens/auth/server_select_screen.dart`: adding a server
- `lib/auth/repositories/auth_repository.dart`, `lib/auth/models/login_state.dart` (`SiloRequestRefused`), `lib/ui/screens/auth/login_screen.dart`: signing in, with a password or a code
- `lib/ui/widgets/user_menu_dialog.dart`: approving a code (14.2)
- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart`: the start's refusal also on `410`
- `lib/l10n/app_en.arb`: 8 strings

### How it works

**"426" is really "410".** The roadmap was written against Silo's v1 notes. Silo's v2 contract keeps `426 Upgrade Required` for one case only, a playback start in an older protocol body (RFC 9110 reserves 426 for protocol upgrades); a retired API namespace answers **`410 Gone` with the `client_upgrade_required` problem** (Silo's `docs/architecture/api-contract.md`: that is how `/api/v1` was retired at 1.0, and how `/api/v2` will be when a v3 replaces it). Both mean the same thing to the person: this Moonfin is too old for the server. Version compatibility is decided by `api_major` (the server's version string is a git hash, never compared).

**Adding a server.** The probe reads `api_major`. A Silo whose major isn't the one this build speaks (`siloSupportedApiMajor`, 2) is not added: newer says "This Silo server needs a newer version of Moonfin. Update Moonfin to use it.", older "This Silo server is too old for this version of Moonfin. Update Silo to use it." A server whose `/api/v2/system/info` is the `410` tombstone (it has moved on to v3) gets the first message too, instead of the probe going on to try the address as Jellyfin and ending in "Unable to connect". Once a Silo answers, no other scheme or port is tried.

**Waiting.** Silo answers `429 rate_limited` when an address or account makes too many attempts (sign-in, codes, approvals have their own budgets) and `503` when it is starting or a service it needs is down, and sends `Retry-After` with both (seconds, or an HTTP date; `SiloProblem.retryAfter` already read both). The texts: "Too many attempts. Try again in 42 seconds." and "The server is busy or still starting. Try again in 2 minutes." (seconds up to a minute and a half, whole minutes after), or "… Try again later." without a header.

**`SiloFailure`.** One place turns a failed request into one of those: `SiloFailure.of(DioException)` answers `SiloUpdateRequired` or `SiloTryAgainLater` (with the wait), or null for anything else, and `.message(l10n)` gives the sentence. Only answers carrying Silo's problem body count (Silo sends one with every error), so a Jellyfin or Emby `429` keeps the handling it had; a `426` counts on its own (only Silo's playback start sends one). It is used where the person is waiting on the answer:

- **Sign-in** (password and code): `AuthRepository` turns it into the new `LoginState` `SiloRequestRefused`, which the login screen shows. Before, a `429` read "Connection failed (badResponse): HTTP 429". A `503` while opening the profile after the password, which used to read "Connection failed …: HTTP 503", now says the server is busy (that test changed with it).
- **Getting a code** on the login screen (`initiateQuickConnect`): before, "Quick Connect unavailable (429, badResponse): …".
- **Approving a code** (14.2's dialog): `429` used to give the generic failure.
- **Playback** already refused a `426` start with "This Silo server needs a newer version of Moonfin to play."; a `410 client_upgrade_required` start does the same now. That text stays in `playback_silo`, untranslated, like the player's other Silo refusals (17.4).

**Not done here:** requests after sign-in (Home, browsing, downloads) keep their own error handling. A server that retires `/api/v2` while Moonfin is signed in would show failing screens until the person signs out and adds it again, which then says what to do. A message there needs a central place for "the server is gone" that Moonfin doesn't have for any server; not in this step.

### Testing

**Automated tests**

- `test/util/silo_failure_message_test.dart` (new, 10 tests): a `429` with `Retry-After: 42`, and as an HTTP date (5 minutes); a `503` with and without the header (1 second, later); `410`/`426 client_upgrade_required` and a bare `426`; a `429` without Silo's body is left alone; `401`, a `410 session_expired` and a `500` are left to their callers; an older Silo asks to update Silo; the wait's wording.
- `packages/server_core/test/server_probe_test.dart` (3 new): the `410` tombstone throws `SiloApiUnsupported` (newer); another `410` isn't one; newer and older by `api_major`.
- `test/auth/server_repository_silo_test.dart` (1 new): a Silo with `api_major` 3 isn't added, and nothing more is tried.
- `test/auth/auth_repository_silo_test.dart` (1 new, 1 changed): a sign-in refused with `429` and `Retry-After: 42` is `SiloRequestRefused` with the wait; a `503` after the password is "busy" now.
- `packages/playback_silo/test/silo_start_test.dart` (1 new): a `410 client_upgrade_required` start is refused with the update message.

**Manual test plan**

Silo's limits are hard to reach by hand; these are the ones that can be:

- a. Sign-in limit: on the Mac, sign out of Silo and enter a wrong password repeatedly (Silo's login budget is per address and account; it may take a dozen or more tries). Once Silo refuses, Moonfin says "Too many attempts. Try again in N seconds." (or minutes) instead of "Connection failed … HTTP 429". After the wait, the right password signs in.
- b. Approval limit (optional, 60 lookups a minute per address): approving wrong codes quickly from the hub until refused shows the same sentence.
- c. Busy: restart Silo and sign in while it is starting (if it answers `503` then): "The server is busy or still starting…".
- d. Wrong passwords before the limit still say "Invalid username or password"; Emby sign-in errors are unchanged.
- e. Update required can't be produced against a real server yet; the unit tests cover it.
- f. Full suite.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace) | — | Not run | this session's network refused pub.dev and storage.googleapis.com: no Flutter, so Claude neither compiled nor tested the batch; Brady ran the analyzer and tests |
| 2026-10-19 | macOS | `bd9d59ea` | Pass | Brady: all good |
| | | | | |

---

<a id="step-17-4"></a>
## 17.4 Translations

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `c7f3b36ed` | previous step |

**Goal.** New strings in `app_en.arb` and `flutter gen-l10n`.

**Where in Moonfin**

- `lib/l10n/app_en.arb`: 3 strings (`siloPlayback…`); the audit below
- `lib/ui/screens/playback/video_player_screen.dart`: the player shows Silo's fixed refusals in the person's language
- `test/l10n/silo_strings_test.dart` (new)

### How it works

**Who translates.** Moonfin's translations live in Weblate ([translate.moonfin.io](https://translate.moonfin.io/engage/moonfin-core/)); `CONTRIBUTING.md` asks contributors to add English strings to `app_en.arb` only and never edit the other `app_*.arb` files, which Weblate overwrites on its next sync. So this step doesn't translate anything itself: it makes sure every Silo string reaches Weblate in a shape a translator can work with, and that nothing a person reads is left out of `app_en.arb`. Until a language is translated, it shows the English text (`gen-l10n` falls back to the template). The generated `lib/l10n/app_localizations*.dart` files are committed with each step that adds strings, as before (rule 7).

**The audit (2026-10-19).**

- The branch adds 42 strings to `app_en.arb` (all named `silo…`; none of upstream's strings changed). Each has a description saying where it appears, and every placeholder is declared with its type; the counts use ICU plurals (`siloWaitSeconds`, `siloWaitMinutes`). A test keeps it that way.
- Hard-coded English shown to a person, in the code this branch added: three fixed playback refusals from `playback_silo` ("Playback isn't available on this Silo server.", "This Silo server needs a newer version of Moonfin to play.", "Playback was ended on the Silo server."). The package has no access to the app's translations, so it keeps the English text, and the player, which already recognises the manager's own fixed errors (`liveStreamLostError`, `unsupportedVideoError`) and shows a translated string instead, now does the same for these three. A test checks the English strings and the package's texts stay identical.
- Left in English, on purpose:
  - **Silo's own words.** A Silo problem's `detail` and a playback refusal's `terminal.message` are the server's text (in the server's language, which Moonfin can't know). Where the code has its own sentence for a case (17.3, 14.x, 3.x), it uses that instead.
  - **Download errors.** Silo's download refusals ("Downloads are switched off on this server.") go through `DownloadService`'s error stream, which carries plain English text for every server (upstream's "Download failed: …" too). Translating them belongs to that service as a whole, upstream.
  - **"Silo can't play this item (reason)."**, the fallback when Silo refuses playback without a message; it names Silo's reason code, which is the useful part for a report.
  - Log and diagnostic text, and `ApiClientError('Invalid auth response')` (the same as upstream's Jellyfin path).

### Testing

**Automated tests**

- `test/l10n/silo_strings_test.dart` (new, 4 tests): there are Silo strings; each has a description; each placeholder a Silo string uses is declared; the player's three Silo refusals equal their English strings.

**Manual test plan**

- a. In Moonfin's settings switch the language to German (or any other), restart if asked: the Silo strings show in English (no translation yet), nothing is blank and no key name shows, e.g. on the add-server dialog and on Silo's code sign-in.
- b. Switch back to English.
- c. After the branch is merged upstream: the `silo…` strings appear in Weblate with their descriptions (Brady, later).
- d. Full suite.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | Linux (Claude workspace) | — | Not run | this session's network refused pub.dev and storage.googleapis.com: no Flutter, so Claude neither compiled nor tested the batch; Brady ran the analyzer and tests |
| 2026-10-19 | macOS | `bd9d59ea` | Pass | Brady: good |
| | | | | |

---

<a id="step-17-5"></a>
## 17.5 Full regression pass

| Status | Commit | Depends on |
|---|---|---|
| ◐ Run pending | `c8a5213b3` | previous step |

**Goal.** Run the whole checklist on each platform against Silo and Emby; record results in each step.

### How it works

No code: this step is the run itself. Each phase's own test plan was run on the Mac when the phase was built; this pass runs the whole app once more, on the finished branch, on **every platform at hand, against Silo and Emby side by side**, so a later step can't have quietly broken an earlier one, and so the device checks that had to wait (the table below) are finally run.

**How to record.** One Results row per platform below, with the Silo build. A failure gets a row in the step it belongs to (as for any test) and a fix commit under that step; the row here links to it. A device check from the table is marked in its own step's Results too ("Pass in 17.5").

**Platforms.** macOS (Brady's main machine), Windows, then whatever devices are at hand: Android TV or Fire TV, an Android phone, iPhone/iPad, Apple TV, Linux, web. Brady (2026-10-17): no Android, iOS, Apple TV or cast devices at hand for now; the run on those happens when they are.

### Testing

**Automated tests**

- The full suite at the repo root (`flutter test`), plus the packages: `packages/server_core`, `server_silo`, `playback_silo` (`flutter test` in each). Brady runs them on the Mac (Claude's workspace can't run the app suite in reasonable time).
- `flutter analyze`: no errors, no new warnings against upstream.

**Manual test plan**

Run each line on Silo, then the same on Emby (`emby.snowystreams.com`), with the same account where both have it. "Like Emby" means the same screens and behaviour minus what Silo doesn't have (phase 4).

- R1. **Servers** (1, 17.1, 17.2): add Silo by its public address and by `host:8096` (offer to connect natively); discovered servers list Silo on the LAN; remove and re-add; Emby and a Jellyfin (if any) still add as before.
- R2. **Sign-in** (3, 14, 17.3): password sign-in, restart and stay signed in; sign out; code sign-in with a QR code from a phone; approve another device's code; a wrong password; a temporary password change (3.6); sign out of Silo while Emby stays signed in, and switch between them.
- R3. **Home** (8): Continue Watching, Next Up, Latest, Recently released, server-curated rows; hide an item from Continue Watching; the artwork right after sign-in (open from 14.1).
- R4. **Browsing** (5, 6): each library; a full grid scrolled to the end with artwork; sort by each option, including Random (reshuffles) and letter jump; filters; a film, a series, its seasons and episodes; cast and crew; collections; genres; studios; extras and trailers (the local trailer button, open from 10.6).
- R5. **Search** (7): titles, episodes and people.
- R6. **User actions** (9): favourite, watched and unwatched (a whole season), rating, add to and remove from a collection; each shows the same in Silo's web app.
- R7. **Playback** (10, 11): a remux, an MP4 and a transcode; pause, seek, resume, stop and the resume point in Silo afterwards; audio and subtitle switching, an ASS subtitle; change quality down and back (Windows: the 10.7 fix); a playback longer than 35 minutes with a seek near the end (token lifetime, 10.7); skip intro and credits; trickplay; chapters; up next at the end of an episode, and the end of a season on a show never watched (11.4, open); theme music when a title has one (11.5); shuffle.
- R8. **Realtime** (13): mark an episode watched in Silo's web app: Moonfin's rows follow within seconds; restart Silo: Moonfin reconnects.
- R9. **Downloads** (15): a film original and an episode, a converted quality (if converted downloads are on), play both offline (airplane mode), progress made offline reaches Silo; subtitles offline; delete a download; the dashboard shows the download completed (15.2, to confirm).
- R10. **Errors and languages** (17.3, 17.4): too many wrong passwords says how long to wait; another app language shows the Silo strings in English, nothing blank.
- R11. **Emby and Jellyfin unchanged:** the whole list above on Emby passes as on the release build; anything that differs is checked on upstream's build before it is called a regression.
- R12. **Device checks:** every row of the table below, on its device.

**Deferred platform checks.** Checks that need a device other than the Mac are collected here and run in this pass (Brady's rule, 2026-10-14). Each step's own Results row says which test was deferred.

| From | Platform | Check |
|---|---|---|
| 3.6 test 5 | Android TV (and other TVs) | Sign in to Silo with a temporary password and change it with the remote: select opens the on-screen keyboard on each field of the dialog; down moves to the next field, then to "Change password". |
| 4.1 test 3 | iOS or Android phone | With only Silo signed in, the bottom navbar tab picker doesn't offer Live TV; with Emby also signed in, it does. |
| 4.4 test 4 | iOS or Android phone | The bottom-nav hub has no Remote control tile with Silo active, and has it with Emby active. |
| 4.3 note | Android Auto / car | With Silo as the active server, the car media browser (Home, Music, Playlists tabs: all music) shows empty lists and no errors. |
| 6.11 | Android Auto / CarPlay | A Silo library's letter buckets in the car browser list the titles starting with that letter (`name_prefix`). |
| 10.7 f | Linux; Android TV with the libmpv engine | Play a film directly, then pick a lower quality: the transcode plays (mpv sends the stream's headers on the HLS segments; no `401` in Silo's log). |
| 12.1 a, d | Android TV (Media3, then libmpv) | xXx, Young Justice 1x01 and an HDR film start, seek and resume like on Emby; playback info shows Silo's play method. |
| 12.1 b | Android TV + HDR TV | An HDR10 or Dolby Vision original direct plays (no tone-mapping transcode). |
| 12.1 c | Android TV | An MKV's PGS subtitles show on the original file without a transcode. |
| 12.1 e | Fire TV | As 12.1 a. |
| 12.1 f | Android phone | As 12.1 a. |
| 12.2 a | iPhone / iPad | xXx, Young Justice 1x01 and an HDR film start, seek, resume and switch audio and subtitles as on the Mac. |
| 12.2 b | Apple TV | As 12.2 a with the remote, plus skip intro, Next Up and scrub previews. |
| 12.2 c | Apple TV + HDR TV | An HDR10 or Dolby Vision original direct plays. |
| 12.3 a–d | Web (Moonfin for the web on the Mac) | Deferred by Brady (2026-10-18): play a remux, an original MP4 and a transcode with `token=` on the media URLs and HLS segments; an SRT sidecar shows; no CORS errors on Silo's API or media; artwork carries no token. |
| 12.4 a–e | Android or iOS phone + Chromecast | Cast xXx (token in the URL, `tv` form factor), pause, seek and resume from the phone; the Silo session stays alive past a minute; stopping keeps the resume point; a transcode plays as HLS; an episode's queue casts the episode alone. |
| 12.4 f | Phone + Chromecast | A cast longer than an hour: does the token's expiry stop it (open in 12.4)? |
| 12.5 a–c | iPhone/iPad + Apple TV | AirPlay xXx: it plays with one `token=`; pause, seek and resume from the phone; the session stays alive and stopping keeps the resume point; a resumed film starts at its resume point. |
| 12.6 a–b | Phone + DLNA renderer | Cast an H.264/AAC MP4: it plays with `token=`; pause, seek and resume; the session stays alive and stopping keeps the resume point. |
| 12.7 c | Apple TV | The native scrubber's previews show on Silo and on Emby. |
| 13.2 e | Android TV, iOS | Background Moonfin past the socket's idle grace and come back: the Silo events socket reconnects with a new ticket (`POST /events/ws-ticket` in the log). |
| 14.1 j | Android TV, Apple TV | Silo's sign-in with a code: the code view fits the screen with the QR code beside the code; the remote reaches "Password", "Get a new code" and "Back"; scanning the TV's QR code with a phone opens Silo's approval page with the code filled in, and approving signs the TV in. |
| 14.2 f | iPhone or Android phone | Signed in to Silo, approve another device's eight-digit code from the bottom-nav hub's "Approve a sign-in" (14.3): "Approved. The other device is signing in.", and the device signs in. |
| 14.3 e | iPhone or Android phone | With the bottom bar, the hub shows "Approve a sign-in" with Silo active, "Quick Connect" with Jellyfin, neither with Emby. |
| 15.2 i | Web (Moonfin for the web on the Mac) | Download a Silo film: the browser downloads the original through a `…/api/v2/direct-download?dl=…` link (no token in the URL). |
| 17.1 f | Android TV, Apple TV | Add `http://<silo host>:8096`: "Connect to Silo directly?" opens with Use Silo focused; select adds the Silo server, back keeps the Jellyfin address. |
| 17.2 a–e, f | macOS, Android TV, Android phone (Wi-Fi), iPhone, Windows, Linux | With a Silo that advertises on the LAN (Docker with host networking, or Silo outside Docker) on the same network, the server list's Discovered servers shows Silo by its branding name and LAN address; choosing it opens Silo's sign-in. On iPhone the local-network prompt names Silo. |

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-17-6"></a>
## 17.6 README and wiki

| Status | Commit | Depends on |
|---|---|---|
| ◐ Fix ready for testing | `30b197ffb`, fix — | previous step |

**Goal.** Add Silo to Supported Servers with its minimum `api_major`, and list what isn't supported.

**Where in Moonfin**

- `README.md`: the intro names Silo; Supported Servers has a Silo row (API v2, `api_major` 2) and a short Silo section (connecting, what works, what's hidden, what isn't supported yet, the update message)
- `docs/silo/wiki/Silo.md` (new): a draft wiki page

### How it works

**README.** Silo's "minimum version" is its API major, not a release number: Silo's version string is a git hash, and compatibility is `api_major` (17.3 refuses any other major). The row says "API v2 (`api_major` 2)". The section below the table says what a person needs before they find out the hard way: add the native address (and that Moonfin offers to switch from 8096), what works, what is hidden because Silo has no such thing (phase 4), what isn't supported yet (household profiles, books and audiobooks, server-side download subscriptions), and that a newer Silo API asks to update Moonfin. The tagline under the logo names Silo too ("Premium Jellyfin, Emby & Silo client…"; the fix below).

**Fix (2026-10-19): the tagline.** Brady's review: the README read right, but the tagline under the logo still said "Premium Jellyfin & Emby client for mobile, tablet, desktop, TV, and web". It now says "Premium Jellyfin, Emby & Silo client for mobile, tablet, desktop, TV, and web". The footer ("not affiliated with the Jellyfin or Emby projects") is left as it is.

**Wiki.** Moonfin's wiki is a separate GitHub wiki that only maintainers edit, and the README links its pages for the details. `docs/silo/wiki/Silo.md` is the page to copy there once the work is merged: connecting (native address, the 8096 offer, discovery and Docker), the main-profile rule, what differs from Jellyfin and Emby (codes, stars, hiding, downloads), the messages a person may see and what to do, and where the developer docs are. Linking it from the README's Documentation table, and touching the existing wiki pages (Getting Started's Quick Connect section, Downloads), is for when it is copied.

### Testing

**Automated tests**

- None (documentation only).

**Manual test plan**

- a. Read the README on GitHub (the fork's `Silo-Support` branch): the table renders with the Silo row and its link, and the Silo section reads correctly.
- b. Read `docs/silo/wiki/Silo.md`: is anything wrong or missing for someone setting Moonfin up with Silo for the first time?

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-19 | GitHub | — | Fail | Brady: the README reads right, but the tagline under the logo still says "Premium Jellyfin & Emby client…"; it should name Silo |
| 2026-10-19 | — | — | Fix | tagline: "Premium Jellyfin, Emby & Silo client for mobile, tablet, desktop, TV, and web" |
| | | | | |

---

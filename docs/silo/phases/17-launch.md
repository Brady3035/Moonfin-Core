# Phase 17: Polish and launch

[← Roadmap](../ROADMAP.md)

Finish the fork's Silo support and prepare it for the upstream proposal.

**Phase done when:** Silo appears in the README's supported-server table and passes the full regression run.

---

<a id="step-17-1"></a>
## 17.1 Native port hint

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

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

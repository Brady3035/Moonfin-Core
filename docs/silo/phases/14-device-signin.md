# Phase 14: Sign in with a code (QuickConnect equivalent)

[← Roadmap](../ROADMAP.md)

Silo's device sign-in maps onto Moonfin's QuickConnect calls.

**Phase done when:** A TV can sign in by approving a code from a phone, and the phone can approve another device.

---

<a id="step-14-1"></a>
## 14.1 Sign in on a TV with a code

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `8e66277ee` | previous step |

**Goal.** Start, poll (`poll_after`), sign in with the approved profile; show the verification URL and a QR code; Silo wording instead of "QuickConnect".

**Silo v2 endpoints**

- `GET /auth/device/capability`
- `POST /auth/device/start`
- `POST /auth/device/poll`

**Where in Moonfin**

- `packages/server_core/lib/src/api/auth_api.dart`: what the Quick Connect calls answer, written down; `QuickConnectKeys` (optional extras a server may send with a code) and `QuickConnectUnavailableError`
- `packages/server_silo/lib/src/api/silo_auth_api.dart`: `initiateQuickConnect`, `checkQuickConnect`, `authenticateWithQuickConnect`; the token pair goes on the session through `_openLogin`, shared with the password sign-in
- `lib/auth/repositories/auth_repository.dart`: a code sign-in on Silo goes on like a password sign-in (`_handleSiloCodeSignIn` → `_finishSiloSignIn`); `lib/auth/models/login_state.dart`: `SiloCodeSignInPasswordChangeRequired`
- `lib/ui/screens/auth/login_screen.dart`: the code view (QR code, 4+4 code, the page to type it on, "opened", a new code when one runs out), Silo wording, polls on the server's interval
- `lib/l10n/app_en.arb`: 8 strings (`siloCodeSignIn…`)

**Also in this commit: the phase 13 bookkeeping.** 13.2's fix hash `681e671b7` is filled in; Brady's macOS Pass rows (2026-10-18, `bd9d59ea`) are added to 13.1, 13.2 (after the fix), 13.3 and 13.4, which are ticked in the roadmap. 13.5 and 13.6 are ⊘: Brady declined them as not needed.

### How it works

Moonfin's sign-in with a code is Jellyfin's Quick Connect: the login screen asks the server for a code (`initiateQuickConnect`: a `Code` to show and a `Secret` to ask with), asks every few seconds whether it was approved (`checkQuickConnect`), then signs in with the secret (`authenticateWithQuickConnect`). Silo's device sign-in is the same idea (RFC 8628's device flow), so it answers the same three calls.

**Starting.** `GET /auth/device/capability` first: unless its `state` is `available`, `initiateQuickConnect` throws `QuickConnectUnavailableError` and nothing is started. The login screen opens on the code view whenever the server supports codes, so a server with them switched off falls back to the password form (as Jellyfin's "Quick Connect is disabled" does). Then `POST /auth/device/start` with this device's name and platform (shown to the person approving; also sent as `X-Silo-Device-*`, which Silo records on the session it opens). Silo answers an eight-digit `user_code` (`4821-7730`), a secret `device_code`, the page to enter the code on (`verification_uri`, `<server>/activate`), the same with the code filled in (`verification_uri_complete`, `…/activate?code=48217730`), `expires_at` (15 minutes) and `interval` (3 s). Both are public: no bearer token (a token left over from another login must not ride along) and never replayed (`non_retryable`).

**What the screen shows.** The extras travel as optional keys of the Quick Connect answer (`QuickConnectKeys` in `server_core`; Jellyfin sends none, and the screen then looks as before). On Silo the toggle says "Sign in with a code"; the instruction names the page without `https://` ("go to silo.example/activate and enter this code"); next to the code a QR code holds `verification_uri_complete`, so a phone camera opens Silo's approval page with the code filled in; the code is grouped 4+4 (Jellyfin's six digits stay 3+3).

**Polling.** `POST /auth/device/poll` with the device code, after the wait Silo asks for (`poll_after`; Jellyfin: 5 s). Each check is scheduled when the previous one has answered, so a slow answer never overlaps the next (this also applies to Jellyfin, which ran on a fixed 5 s clock before). A failed check (no network) keeps the code and asks again.

- `pending`: keep asking. `opened: true` means someone has looked the code up to approve it; the screen then says "Code found. Approve the sign-in on your other device." A pending answer carries the request's current `expires_at`, which an approver's lookup can move later; the screen moves its deadline there.
- Past the deadline, or `expired`, `consumed`, `canceled`, or a `404` (Silo no longer knows the device code): that code is done, and a new one is shown.
- `denied`: polling stops, the screen says "This sign-in was declined." and offers "Get a new code".
- `approved`: carries the token pair, **exactly once** (the next poll answers `consumed`). `checkQuickConnect` keeps the pair, keyed by the device code, and answers `Authenticated: true`; `authenticateWithQuickConnect` takes it (once) and opens the login as a password sign-in does.

**Signing in.** From there it is the password path's second half (3.3): `AuthRepository` picks the main profile, stores the user and the token pair, and binds the pair so every refresh is saved (`_finishSiloSignIn`). A PIN-locked main profile ends the new login and says so (3.7). Two cases end the login instead of signing in:

- **A temporary password.** Replacing it (3.6) needs the password in use, which a code sign-in never had. The login is ended and the screen says "This account has a temporary password. Sign in with the password once to replace it." (Silo itself refuses Jellyfin Quick Connect for such accounts; its native device sign-in approves them.)
- Any other failure shows its message, and "Get a new code".

Before, a Quick Connect sign-in that didn't end in `Authenticated` left the screen without a word; it now shows the reason on every server.

**Not done (Brady, 2026-10-18): `POST /auth/device/cancel`.** Silo lets a device withdraw its own request so an abandoned code can't be approved later; Moonfin leaves it to expire (15 minutes, at most 30 if someone keeps looking it up), which Brady finds fine. Jellyfin has no such call either. The temporary-password message above is as Brady wants it.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_device_sign_in_test.dart` (new, 18 tests): the fixtures (`silo/device_login_start.json`, `device_login_poll_pending.json`, `device_login_poll_approved.json`, hand-built, and the captured `device_login_capability.json`) and the request bodies fit the pinned contract (`playback_silo`'s validator); the code without its dash, the secret, both links, the expiry and the interval; the start carries the device name and platform and no bearer token; `expires_in` when there's no `expires_at`; `disabled`, `not_configured` and `unsupported` start nothing; a pending poll's `opened` and moved expiry; `denied`, `expired`, `consumed`, `canceled` and a `404`; another failure is sent once; an approval signs in once with its pair; a temporary password is flagged; an approval without tokens and a code never approved sign nothing in.
- `packages/server_silo/test/silo_media_server_client_test.dart`: the placeholder check moves to `authorizeQuickConnect` (14.2).
- `test/auth/auth_repository_silo_test.dart` (3 new): a code sign-in lands on the main profile and stores the pair; a temporary password ends the login (`SiloCodeSignInPasswordChangeRequired`, nothing stored); a PIN-locked main profile says so.
- `test/ui/screens/auth/login_quick_connect_test.dart` (new, 4 tests): codes read 3+3 and 4+4; the page shown without its scheme.

**Manual test plan**

Test with the whole phase 14 batch applied: the login screen only offers codes on Silo once 14.3 turns `supportsQuickConnect` on.

On the Mac, signed out of Silo (or add the server again), with Silo web open on a phone or another browser, signed in:

- a. Open Silo's sign-in in Moonfin: it opens on "Sign in with a code", with a QR code, an eight-digit code shown `4821 7730`, and "go to silo.snowystreams.com/activate". The network log shows `GET …/auth/device/capability`, `POST …/auth/device/start`, then `POST …/auth/device/poll` about every 3 s.
- b. Scan the QR code with the phone: Silo's approval page opens with the code filled in. Moonfin switches to "Code found. Approve the sign-in on your other device." within a few seconds.
- c. Approve on the phone: Moonfin lands on Home as the main profile. Restart Moonfin: still signed in (the pair was stored). In Silo web's sessions, the new session shows Moonfin's device name.
- d. Sign out; start again, type the code on the web page instead of scanning it: same result.
- e. Start again and press Deny on the web page: "This sign-in was declined." and "Get a new code", which shows a fresh code.
- f. Leave a code unapproved for 15 minutes: a new code replaces it by itself.
- g. "Password" still signs in as before; switching back to the code shows a new code.
- h. Regression on Jellyfin, if one is at hand (Emby has no Quick Connect): its six-digit code still shows `123 456` and signs in.
- i. Full suite (`flutter test` at the repo root).
- j. Deferred to 17.5: on Android TV and Apple TV, the code view fits the screen with the QR code beside the code, the remote reaches "Get a new code", and a phone scanning the TV's QR code approves it.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | device sign-in 18/18, client 12/12, `server_silo` 614/614, `server_core` 100/100, `test/auth` 138/138, `test/ui/screens/auth` 8/8; analyzer: no new issues in the changed files |
| 2026-10-18 | Android TV, Apple TV | — | Deferred | check j in 17.5 |
| 2026-10-18 | macOS | `bd9d59ea` | Pass | Brady: a–h "all good". Note: right after signing in, the artwork on Continue Watching and Next Up isn't right; it is on the next Home load. Open, see below |
| | | | | |

**Open (found testing 14.1):** the Continue Watching and Next Up artwork right after sign-in. Not diagnosed yet: whether it also happens after a password sign-in (then it isn't phase 14's), and what is wrong (blank, another title's art, another image kind).

---

<a id="step-14-2"></a>
## 14.2 Approve another device

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `fc2f623be`, fix `8cc18adc0` | previous step |

**Goal.** From a signed-in phone.

**Silo v2 endpoints**

- `POST /auth/device/approve`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_auth_api.dart`: `authorizeQuickConnect`
- `lib/ui/widgets/user_menu_dialog.dart`: the code dialog (`showQuickConnectCodeDialog`) in Silo's words
- `lib/l10n/app_en.arb`: 5 strings (`siloApproveSignIn…`)

### How it works

Moonfin approves another device's Quick Connect code from the account menu (and, on phones, the bottom-nav hub: 14.3): a dialog takes the code, `authorizeQuickConnect(code, userId:)` sends it, and a snackbar says how it went. On Silo that is `POST /auth/device/approve` with `{"code": "48217730"}`: separators are dropped (Silo ignores them too; the field already takes digits only, up to eight).

- **Who approves.** The request goes through the main client, so it carries this login's bearer token, and a token that is due is refreshed first. Silo approves for the **account**, not a profile: the device that collects the approval gets a login of the account and picks its own profile (another Moonfin: the main one, D9). `userId` isn't sent. Only a login session can decide; an API key or an impersonation session gets `403 permission_denied`.
- **Retries.** The route is `domain_identity`: a second approval of the same code by the same account changes nothing. The client's only replay is the session interceptor's, after a `401` Silo answered before acting, so it is safe either way.
- **The answer.** `{"status": "approved"}` is true. No request waiting with that code is false, which the dialog shows as "No sign-in is waiting with that code. Check it, or get a new code on the other device.": an unknown code (`404`), one already used, declined or withdrawn by its device (`409`), or one that expired (`410`). Other refusals keep the dialog's existing messages: `403` "Your account cannot authorize this Quick Connect request", `429` (too many attempts; Silo's `device_lookup` budget, 60 a minute per address) the generic failure.
- **Wording.** On Silo the dialog is "Approve a sign-in", its field "Code shown on the other device", its button "Approve", and a success says "Approved. The other device is signing in." Jellyfin's wording is unchanged.

**Not done (Brady, 2026-10-18):**

- **Jellyfin apps' six-digit codes.** A Jellyfin app using Silo's Jellyfin-compatible API (Swiftfin, Jellyfin for Android TV, Moonfin in Jellyfin mode) shows a six-digit Quick Connect code. Silo approves those only through `POST /auth/device/approve-handoff`, for the caller's verified profile. `approve` answers `409` for them, so Moonfin says no sign-in is waiting. Brady: Moonfin approves Silo's own codes only; not wanted.
- **Seeing the request before approving it.** Silo's own approval page first looks the code up (`GET /auth/device?code=`) and shows the device and the server, with a Deny button. Brady: leave the dialog as it is, approving straight away as on Jellyfin.

**Fix (2026-10-18): the dialog's closing.** Brady's first run on the Mac showed a red error screen (`'_dependents.isEmpty': is not true`) after Approve, and after a wrong code; the approval itself went through. The dialog's text controller was disposed by the code that opened it as soon as the dialog returned the code, while the dialog was still animating closed: the closing frames rebuild the field, which then used a disposed controller ("A TextEditingController was used after being disposed"), and the failed build left the tree in the state the assertion reports. The dialog is now its own widget (`_QuickConnectCodeDialog`) that owns the controller and disposes it when the dialog is gone. Upstream's dialog has the same bug on Jellyfin (the new test fails there too without the fix): an upstream candidate.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_device_sign_in_test.dart` (7 new, 25/25): the approval is a `POST` with the code's digits and this login's bearer token, and the body and answer fit the contract; a decision other than `approved` is false; `404`, `409` and `410` are false and sent once; `403` and `429` reach the caller.
- `packages/server_silo/test/silo_media_server_client_test.dart`: no placeholder left in `AuthApi` (11/11).
- `test/ui/widgets/quick_connect_code_dialog_test.dart` (new with the fix, 3 tests): approving on Silo, a code no sign-in waits with, and Jellyfin's approval each close the dialog without an error and show their message. All 3 fail without the fix.

**Manual test plan**

On the Mac, signed in to Silo in Moonfin. You also need a second device that shows a Silo code: another Moonfin signed out of Silo (its "Sign in with a code", 14.1), or Silo's own TV app.

- a. On the second device, start a code sign-in. In Moonfin on the Mac: the account menu (avatar) → "Quick Connect" (on Silo after 14.3: "Approve a sign-in") opens a dialog titled "Approve a sign-in". Type the eight digits, Approve: "Approved. The other device is signing in.", and the second device signs in. The network log shows `POST …/auth/device/approve` with a `200`.
- b. Approve the same code again: "No sign-in is waiting with that code…".
- c. A made-up code (`12345678`): the same message.
- d. A code that has expired (wait 15 minutes, or one the device already replaced): the same message.
- e. Regression on Jellyfin, if one is at hand: approving a code still says "Quick Connect request authorized."
- f. Deferred to 17.5: the same from an iPhone or Android phone, through the bottom-nav hub (14.3).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | device sign-in 25/25, client 11/11, `server_silo` 620/620, `test/ui/widgets` 491/491; analyzer: no issues in the changed files |
| 2026-10-18 | iOS, Android phone | — | Deferred | check f in 17.5 |
| 2026-10-18 | macOS | `bd9d59ea` | Fail | Brady: Approve shows a red error screen (`'_dependents.isEmpty': is not true`), though the code is approved; the same after a wrong code |
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | fix: the dialog owns its controller; dialog 3/3 (new), `test/ui/widgets` 497/497; analyzer: no issues in the changed files |
| 2026-10-18 | macOS | `bd9d59ea` | Pass | Brady, after the fix (`8cc18adc0`): "14.2 was good" |
| | | | | |

---

<a id="step-14-3"></a>
## 14.3 Enable the entry points

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `1f9a3d065` | previous step |

**Goal.** Turn on `supportsQuickConnect` for Silo and the bottom-nav entry.

**Where in Moonfin**

- `packages/server_core/lib/src/feature/feature_detector.dart`: `supportsQuickConnect` is on for Jellyfin and Silo
- `lib/ui/widgets/bottom_nav/bottom_nav_controller.dart`: the hub's tile follows `supportsQuickConnect` instead of "is Jellyfin"; `activeServerIsSilo` for its label
- `lib/ui/widgets/bottom_nav/bottom_nav_destinations.dart`, `bottom_navbar_hub_sheet.dart`, `lib/ui/widgets/user_menu_dialog.dart`: the entries say "Approve a sign-in" on Silo

### How it works

`FeatureDetector.supportsQuickConnect` gates the two sides of sign-in with a code:

- **The login screen** (14.1) opens on the code view when the server supports it. On Silo it does now; a Silo server with device sign-in switched off falls back to the password form on its own (its capability isn't `available`).
- **The bottom-nav hub** (phones with the bar at the bottom) lists the approve tile. It used to ask "is the active server Jellyfin?"; it now asks the active server's `supportsQuickConnect`, which answers the same for Jellyfin and Emby and turns it on for Silo. Without an active server there is still no tile.

The account menu's button (desktop and tablets with the top bar) was already shown for every server; on Silo it reached the placeholder until 14.2. Its label, and the hub tile's, now say "Approve a sign-in" on Silo, the dialog's own title (14.2); Jellyfin keeps "Quick Connect". The menu button still shows on Emby, which has no Quick Connect (upstream's behaviour, unchanged).

### Testing

**Automated tests**

- `packages/server_core/test/feature_detector_test.dart`: Silo supports Quick Connect (moved from the "not yet" list to the switched-on list). `server_core` 100/100.
- `test/ui/widgets/bottom_nav/quick_connect_hub_test.dart` (new, 3 tests): the hub offers "Approve a sign-in" on Silo, "Quick Connect" on Jellyfin, neither on Emby. `test/ui/widgets/bottom_nav` 44/44.

**Manual test plan**

On the Mac:

- a. Silo's sign-in opens on "Sign in with a code" (the checks are 14.1's).
- b. Signed in to Silo, the account menu's button reads "Approve a sign-in" and opens 14.2's dialog. Switch to Emby: it reads "Quick Connect" again.
- c. Regression on Emby: its sign-in still opens on the password form, with no code toggle.
- d. Full suite (`flutter test` at the repo root).
- e. Deferred to 17.5: on a phone with the bottom bar, the hub has "Approve a sign-in" with Silo active, "Quick Connect" with Jellyfin, nothing with Emby (with 14.2 f).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | `server_core` 100/100, `test/ui/widgets/bottom_nav` 44/44; analyzer: no new issues in the changed files |
| 2026-10-18 | iOS, Android phone | — | Deferred | check e in 17.5 |
| 2026-10-18 | macOS | `bd9d59ea` | Pass | Brady: a–c "all good" |
| | | | | |

---

# Phase 2: Sign-in API (package only)

[← Roadmap](../ROADMAP.md)

Sessions, sign-in and profiles inside `server_silo`. Still no UI changes; everything is unit-tested against fixtures.

**Phase done when:** `server_silo` can sign in, refresh, list profiles, check a PIN and describe the current user, all covered by tests.

---

<a id="step-2-1"></a>
## 2.1 Token pair and single-flight refresh (`SiloSession`)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Hold the access/refresh token pair and expiry. Refresh once even when many requests ask at the same time. End the session only when Silo refuses the refresh token, never on a 503 or a network error.

**Silo v2 endpoints**

- `POST /auth/refresh`

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_session.dart`

**Earlier work to port:** silo-2

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- concurrent callers share one refresh; 401 `session_expired` ends; 503 keeps tokens

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-2"></a>
## 2.2 Session interceptor

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Refresh shortly before expiry, retry a 401 once after refreshing, and never replay login, refresh, device sign-in or PIN checks. Refreshes use a separate HTTP client so they can't deadlock.

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_session_interceptor.dart`

**Earlier work to port:** silo-2 (commits 34b9b9b, b40b956, 717c21d)

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- proactive refresh; one retry; non-replayable ops; identity-bound retries

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-3"></a>
## 2.3 Password sign-in

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `authenticateByName` → `POST /auth/login` with device headers, translated to the Jellyfin `AuthenticationResult` shape plus the Silo token data.

**Silo v2 endpoints**

- `POST /auth/login`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_auth_api.dart`

**Earlier work to port:** silo-2

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- success; wrong password → readable error; `password_change_required` flagged

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-4"></a>
## 2.4 Sign out

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `logout` → `POST /auth/logout`.

**Silo v2 endpoints**

- `POST /auth/logout`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_auth_api.dart`

**Earlier work to port:** silo-2

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

<a id="step-2-5"></a>
## 2.5 List household profiles

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `SiloProfilesApi.list()`.

**Silo v2 endpoints**

- `GET /profiles`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_profiles_api.dart`

**Earlier work to port:** silo-2

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- fixture `profiles.json` parsed; PIN flag read

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-6"></a>
## 2.6 Profile PIN check

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

<a id="step-2-7"></a>
## 2.7 Current user (account + profile → user)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `SiloUsersApi.getCurrentUser` and the user mapper: profile id as the Moonfin user id, admin/download permissions from the account.

**Silo v2 endpoints**

- `GET /account/me`
- `GET /profiles`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_users_api.dart`
- `packages/server_silo/lib/src/mappers/silo_user_mapper.dart`

**Earlier work to port:** silo-2

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: Compare the mapped user with Emby's `/Users/{id}` for the fields Moonfin reads (`Policy`, `Configuration`).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-2-8"></a>
## 2.8 User playback settings

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Read and save subtitle language/mode, audio language and autoplay-next through the profile; keep Jellyfin-only fields local.

**Silo v2 endpoints**

- `GET /settings/values/effective`
- `PATCH /profiles/{id}`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_users_api.dart`

**Earlier work to port:** silo-2

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

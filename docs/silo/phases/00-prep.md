# Phase 0: Preparation

[← Roadmap](../ROADMAP.md)

Pin the Silo contract we build against and set up the tooling. Nothing in the app changes.

**Phase done when:** The OpenAPI snapshot and fixtures match the server you run, and the probe script refreshes them.

---

<a id="step-0-1"></a>
## 0.1 Add the Silo support docs

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Commit this roadmap, the phase files, the decisions log and the Oct 8 design reference so every later commit can fill in its own section.

**Where in Moonfin**

- `docs/silo/**`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Open `docs/silo/README.md` on GitHub and check the links between the files work.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-0-2"></a>
## 0.2 Pin the Silo v2 contract for build 4b2e921c

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Replace the `4e371f4c` OpenAPI snapshot with the one from the server you run, and record the version, `api_major` and `contract_digest`.

**Silo v2 endpoints**

- `GET /api/v2/system/info`
- `GET /api/v2/openapi.json`

**Where in Moonfin**

- `packages/server_silo/test/fixtures/openapi-<build>.json.gz`
- `packages/server_silo/test/fixtures/README.md`

**Earlier work to port:** stash `Add_silo` (fixtures README, old snapshot)

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- `curl https://silo.snowystreams.com/api/v2/system/info` shows the same digest as the README.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-0-3"></a>
## 0.3 Probe script for refreshing fixtures

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** A script that signs in, lists profiles and saves scrubbed responses for each endpoint the plan uses, so fixtures can be refreshed after every Silo upgrade.

**Where in Moonfin**

- `scripts/silo_probe.sh`

**Earlier work to port:** silo-1 `scripts/silo_probe.sh`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Run it on the Mac against your server. Tokens, `sig`/`st` query values and file paths come out scrubbed.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-0-4"></a>
## 0.4 Capture Silo and Emby fixture pairs

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Save the same titles from both servers (a movie, a two-version movie, a series → season → episode, an episode with markers and trickplay, a PIN profile, the library list). The Emby side is the target shape the mappers must produce.

**Silo v2 endpoints**

- `/catalog/items/{id}`
- `/catalog/items/{id}/versions`
- `/catalog/series/{id}/seasons`
- `/catalog/items/{id}/episodes`
- `/watch/{id}`
- `/watch/{id}/trickplay`
- `/markers/items/{id}`
- `/profiles`
- `/user/libraries`
- `/home/layout`

**Where in Moonfin**

- `packages/server_silo/test/fixtures/silo/*.json`
- `packages/server_silo/test/fixtures/emby/*.json`

**Earlier work to port:** stash `Add_silo` fixtures (re-capture against 4b2e921c)

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- The Salt Path two-version sample is included (missing from the Oct 7 capture).
- Compare with Emby: `/Items/{id}`, `/Shows/{id}/Seasons`, `/Shows/{id}/Episodes`, `/Items/{id}/PlaybackInfo` for the same titles.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

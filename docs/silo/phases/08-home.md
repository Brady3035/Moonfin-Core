# Phase 8: Home screen

[← Roadmap](../ROADMAP.md)

Moonfin's own home rows, one row type per commit.

**Phase done when:** Home looks like it does on Emby for the same account, minus the rows Silo can't provide.

---

<a id="step-8-1"></a>
## 8.1 Continue Watching

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** From the `continue_watching` section, or `/progress?status=in_progress`.

**Silo v2 endpoints**

- `GET /home/sections`
- `GET /home/sections/{id}/items`
- `GET /progress`

**Where in Moonfin**

- `silo_items_api.dart (getResumeItems)`

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

<a id="step-8-2"></a>
## 8.2 Next Up

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Home `next_up` section (tolerate it being absent); per series via `play_content_id`.

**Where in Moonfin**

- `silo_items_api.dart (getNextUp)`

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

<a id="step-8-3"></a>
## 8.3 Latest per library

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Recently added per library.

**Silo v2 endpoints**

- `GET /recommendations/recently-added`
- `GET /catalog?sort=-added_at`

**Where in Moonfin**

- `silo_items_api.dart (getLatestItems)`

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

<a id="step-8-4"></a>
## 8.4 Recently released

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Sorted by release date.

**Where in Moonfin**

- `silo_items_api.dart`

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

<a id="step-8-5"></a>
## 8.5 Favorites row

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `source=favorites`.

**Silo v2 endpoints**

- `GET /favorites`

**Where in Moonfin**

- `silo_items_api.dart`

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

<a id="step-8-6"></a>
## 8.6 Collections and genre rows

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Check the remaining row types in `row_data_source.dart` and fix any hand-built URL.

**Where in Moonfin**

- `lib/data/services/row_data_source.dart`

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

<a id="step-8-7"></a>
## 8.7 Server-curated home sections *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** A new row kind that renders Silo's own home sections (recommended, trending…).

**Silo v2 endpoints**

- `GET /home/capabilities`
- `GET /home/layout`
- `GET /home/sections`

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

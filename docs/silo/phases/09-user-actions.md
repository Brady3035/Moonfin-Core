# Phase 9: User actions

[← Roadmap](../ROADMAP.md)

Things a user changes on an item. One action per commit.

**Phase done when:** Each action shows the same result in Silo's web UI.

---

<a id="step-9-1"></a>
## 9.1 Favorite / unfavorite

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Silo v2 endpoints**

- `PUT/DELETE /favorites/{id}`

**Where in Moonfin**

- `silo_user_library_api.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Toggle in Moonfin; check Silo web.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-9-2"></a>
## 9.2 Mark played / unplayed

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Items, seasons and series.

**Silo v2 endpoints**

- `POST/DELETE /watched/{id}`

**Where in Moonfin**

- `silo_user_library_api.dart`

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

<a id="step-9-3"></a>
## 9.3 Ratings

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Like and numeric ratings mapped onto Silo's rating scale.

**Silo v2 endpoints**

- `GET /capabilities/ratings`
- `PUT/DELETE /ratings/{id}`

**Where in Moonfin**

- `silo_user_library_api.dart`

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

<a id="step-9-4"></a>
## 9.4 Refresh rows after a change

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Publish a local user-data change so rows update without a reload.

**Where in Moonfin**

- `silo_user_library_api.dart`
- `lib/data/services/user_data_sync.dart`

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

<a id="step-9-5"></a>
## 9.5 Personal collections: create, add, remove

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Silo v2 endpoints**

- `POST /collections`
- `PUT/DELETE /collections/{id}/items/{item_id}`

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

<a id="step-9-6"></a>
## 9.6 Watchlist *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Silo's watchlist as a context action and row.

**Silo v2 endpoints**

- `PUT/DELETE /watchlist/{item_id}`
- `GET /watchlist`

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

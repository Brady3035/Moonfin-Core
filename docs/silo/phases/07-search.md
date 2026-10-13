# Phase 7: Search

[← Roadmap](../ROADMAP.md)

Search screens on Silo.

**Phase done when:** Search returns movies, series, episodes and people like it does on Emby.

---

<a id="step-7-1"></a>
## 7.1 Title search

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `searchTerm` → catalog `q`, honouring the search capabilities.

**Silo v2 endpoints**

- `GET /catalog?q=`
- `GET /catalog/search/capabilities`

**Where in Moonfin**

- `silo_items_api.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: Same query on Emby; compare result types.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-7-2"></a>
## 7.2 People search

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Person results.

**Silo v2 endpoints**

- `GET /catalog/people?q=`

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

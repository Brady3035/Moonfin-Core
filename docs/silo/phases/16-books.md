# Phase 16: Books and audiobooks (Silo beta)

[← Roadmap](../ROADMAP.md)

Only after video parity; Silo marks these beta.

**Phase done when:** An audiobook plays with chapters and resumes; an EPUB opens and keeps its place.

---

<a id="step-16-1"></a>
## 16.1 Audiobooks *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Playback with client-side progress persistence.

**Silo v2 endpoints**

- `/catalog/audiobook-groups`
- `POST /sync/progress`

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

<a id="step-16-2"></a>
## 16.2 Ebooks and comics *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Read file and progress.

**Silo v2 endpoints**

- `GET /ebooks/{id}/files/{file_id}/read`
- `GET/PUT /ebooks/{id}/progress`

**Where in Moonfin**

- `lib/data/services/book_reader_service.dart`

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

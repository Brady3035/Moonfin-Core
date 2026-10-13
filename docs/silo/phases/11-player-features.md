# Phase 11: Player features

[← Roadmap](../ROADMAP.md)

The extras around playback.

**Phase done when:** Skip intro, trickplay, chapters and up-next behave as they do on Emby/Jellyfin.

---

<a id="step-11-1"></a>
## 11.1 Skip intro, credits and recap

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Markers through `getMediaSegments`.

**Silo v2 endpoints**

- `GET /markers/items/{id}`
- `GET /markers/files/{file_id}`

**Where in Moonfin**

- `silo_items_api.dart`
- `lib/data/services/media_segment_service.dart`

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

<a id="step-11-2"></a>
## 11.2 Trickplay scrubbing

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Fetch the trickplay manifest when `trickplay_available` is true; refresh after `expires_at`.

**Silo v2 endpoints**

- `GET /watch/{id}/trickplay`

**Where in Moonfin**

- `silo_items_api.dart`
- `silo_image_api.dart`

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

<a id="step-11-3"></a>
## 11.3 Chapters and chapter images

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Where in Moonfin**

- `silo_image_api.dart`

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

<a id="step-11-4"></a>
## 11.4 Next episode and autoplay

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Queue from `getEpisodes`; Up Next card.

**Where in Moonfin**

- `playback queue`

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

<a id="step-11-5"></a>
## 11.5 Theme music

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Silo v2 endpoints**

- `GET /catalog/themes/capabilities`
- `GET /catalog/items/{id}/themes/{theme_id}/audio`

**Where in Moonfin**

- `lib/data/services/theme_music_service.dart`

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

<a id="step-11-6"></a>
## 11.6 Per-series audio and subtitle choice *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Sync Moonfin's per-series track choice with Silo's.

**Silo v2 endpoints**

- `/audio-prefs/{series_id}`
- `/subtitle-prefs/{series_id}`

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

<a id="step-11-7"></a>
## 11.7 Shuffle *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Silo's server-side shuffle for a series or library.

**Silo v2 endpoints**

- `POST /shuffles`

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

# Phase 6: Browsing

[← Roadmap](../ROADMAP.md)

Libraries, grids and detail pages. Each step replaces one placeholder method with the real call.

**Phase done when:** You can open each library, scroll a full grid with artwork, open a movie, a series, its seasons and episodes, and the detail screen looks like it does on Emby.

---

<a id="step-6-1"></a>
## 6.1 Image API on the registry

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `getPrimary/Backdrop/Logo/Thumb/BannerImageUrl` and user avatars from the registry; user menu avatar goes through `imageApi`.

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_image_api.dart`
- `lib/ui/widgets/user_menu_dialog.dart`

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

<a id="step-6-2"></a>
## 6.2 Image cache keyed by path

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Pass a path-only `cacheKey` so the signed query rotating every day doesn't re-download every image.

**Where in Moonfin**

- `packages/cached_network_image_fork/**`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Cold start the next day: artwork shows from cache.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-6-3"></a>
## 6.3 Image registry misses

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** When nothing is registered for an item (cold start, deep link), follow the decision in DECISIONS.md D2 (resolver image provider or placeholder).

**Where in Moonfin**

- `silo_image_api.dart`
- `cached_network_image_fork`

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

<a id="step-6-4"></a>
## 6.4 Libraries (`UserViewsApi`)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `GET /user/libraries` with caching and `invalidateCache()`.

**Silo v2 endpoints**

- `GET /user/libraries`

**Where in Moonfin**

- `silo_user_views_api.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: The library list and order match what Emby shows for the same libraries.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-6-5"></a>
## 6.5 Library grid (`getItems` for a library)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Library id → `library_id`, type filter, sort, page through the cursor pager.

**Silo v2 endpoints**

- `GET /catalog`

**Where in Moonfin**

- `silo_items_api.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Scroll to the end of the largest library; total count is right.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-6-6"></a>
## 6.6 Movie detail (`getItem`)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Item detail with its versions in one call when available.

**Silo v2 endpoints**

- `GET /catalog/items/{id}`
- `GET /catalog/items/{id}/versions`

**Where in Moonfin**

- `silo_items_api.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: Open the same movie on Emby: overview, cast, ratings, runtime, version badges.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-6-7"></a>
## 6.7 Series detail and seasons

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Series detail and `getSeasons`.

**Silo v2 endpoints**

- `GET /catalog/series/{id}/seasons`

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

<a id="step-6-8"></a>
## 6.8 Season episodes

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `getEpisodes(seasonId)` via `/catalog/items/{season_id}/episodes`; whole-series episodes when no season is given.

**Silo v2 endpoints**

- `GET /catalog/items/{id}/episodes`

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

<a id="step-6-9"></a>
## 6.9 Ancestors

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Synthesise episode → season → series → library for breadcrumbs and back navigation.

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

<a id="step-6-10"></a>
## 6.10 Library filters

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `getQueryFilters` and genre, year and rating filters in `getItems`.

**Silo v2 endpoints**

- `GET /catalog/filters`

**Where in Moonfin**

- `silo_items_api.dart`
- `silo_filters_mapper.dart`
- `lib/data/viewmodels/library_browse_view_model.dart`

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

<a id="step-6-11"></a>
## 6.11 Alphabet jump

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Letter index and `nameStartsWith` through the new letters endpoint.

**Silo v2 endpoints**

- `POST /catalog/letters`

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

<a id="step-6-12"></a>
## 6.12 Genres

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Genre list as synthetic Genre items, and the genre's items.

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

<a id="step-6-13"></a>
## 6.13 Studios and networks

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Same pattern as genres.

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

<a id="step-6-14"></a>
## 6.14 People

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Person detail and filmography.

**Silo v2 endpoints**

- `GET /catalog/people/{id}`
- `GET /catalog (source=person)`

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

<a id="step-6-15"></a>
## 6.15 Collections (browse)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Personal and library collections as BoxSets, and their items.

**Silo v2 endpoints**

- `GET /collections`
- `GET /collections/{id}/items`
- `GET /library/{id}/collections`

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

<a id="step-6-16"></a>
## 6.16 Similar items

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** "More like this".

**Silo v2 endpoints**

- `GET /recommendations/similar/{id}`

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

<a id="step-6-17"></a>
## 6.17 Trailers and extras

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Local trailers and special features from the item's extras.

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

<a id="step-6-18"></a>
## 6.18 Detail-screen media info without starting playback

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `getPlaybackInfo` built from the versions mapping. It must never call `/playback/start`.

**Where in Moonfin**

- `silo_playback_api.dart`
- `lib/util/detail_playback_info.dart`

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

<a id="step-6-19"></a>
## 6.19 Display preferences

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Per-library view settings, stored as decided in DECISIONS.md D3.

**Where in Moonfin**

- `silo_display_preferences_api.dart`

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

# Phase 8: Home screen

[← Roadmap](../ROADMAP.md)

Moonfin's own home rows, one row type per commit.

**Phase done when:** Home looks like it does on Emby for the same account, minus the rows Silo can't provide.

---

<a id="step-8-1"></a>
## 8.1 Continue Watching

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** From the `continue_watching` section, or `/progress?status=in_progress`.

**Silo v2 endpoints**

- `GET /home/layout`, `GET /home/sections/{id}/items`
- `GET /library/{id}/layout`, `GET /library/{id}/sections/{section_id}/items`
- `GET /progress?status=in_progress` (fallback)

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_home_sections.dart` (new): `SiloHomeSections`, the home and library page sections.
- `packages/server_silo/lib/src/api/silo_items_api.dart`: `getResumeItems`.
- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart`: a card's own resume point.
- `packages/server_silo/test/fixtures/silo/home_continue_watching.json` (new).

### How it works

Moonfin's Continue Watching row (`RowDataSource.loadResume`, and the per-library and multi-server versions) asks `ItemsApi.getResumeItems(mediaTypes: Video, limit: …)`; on Jellyfin and Emby that is `/Users/{id}/Items/Resume`. Until now Silo answered `SiloNotImplementedError`, so the row stayed empty.

**Where Silo keeps it.** Silo has no "resumable items" query. It builds Continue Watching per profile as a **section** of its home page: it walks the profile's resume points, drops what the profile dismissed from the row (Silo's "hide from Continue Watching", written by step 9.7) and episodes of shows it dropped, and by default adds each show's next episode, one card per show, newest first. The catalog can filter `in_progress` but would miss the dismissals, so the row reads the section:

- `SiloHomeSections` reads the page's layout (`GET /home/layout`, or `GET /library/{id}/layout` for a library `parentId`) and the cards of every section whose `section_type` is `continue_watching` (`GET /home/sections/{id}/items?image_size=medium`, or the library's). Usually there is one; with several (an admin's next to the built-in one) their cards are merged in layout order without repeats.
- Each card says why it is there in `item_source`: `in_progress`, or `next_up` for a show's next episode. Continue Watching keeps `in_progress` (and cards without the field); the `next_up` cards are Next Up's (8.2). This matches Emby, whose Continue Watching holds only what was started.
- Films and episodes only (`movie`, `episode`): audiobooks resume too on Silo but come with phase 16. `mediaTypes: Audio` (the Continue Listening row) answers empty without a request; `includeItemTypes` narrows the same way.
- `startIndex`/`limit` slice the list; `TotalRecordCount` is its length. Silo caps the section at its `item_limit` (20 unless the profile changed it), shared with the next-up cards.
- A `parentId` that isn't a library (a series, say) answers empty: Silo resumes titles, not folders.

**The resume point.** A Continue Watching card carries `position_seconds`, `duration_seconds` and `progress_updated_at` on the card itself, where a title's page has them under `user_data`. The item mapper (5.5) now reads either, so the card gets `PlaybackPositionTicks`, `PlayedPercentage` (the progress bar) and `LastPlayedDate`. Episode cards carry `series_id`, `series_title`, season and episode numbers like search results (7.1), so they show as "Series · S1:E2".

**No section.** A profile can remove Continue Watching from its Silo home. Then the row falls back to the resume points (`GET /progress?status=in_progress`, with `library_id` for a library, as many as the row asks for up to Silo's 200), reads each item from the catalog (six at a time, items Silo no longer has left out) and takes `UserData` from the entry (`siloProgressToUserData`, 5.5). That list knows nothing about dismissals.

**Sharing reads.** Continue Watching and Next Up (8.2) load together and read the same section, so `SiloHomeSections` keeps a layout for a minute and a section's cards for five seconds, and shares a read already on its way. Coming back to Home after that reads them again. A failed read isn't kept, and errors reach the row as before.

**Not covered here:** marking something played or dismissing a card refreshes the row only when Home reloads (9.4 and 9.7). Silo's own "hide watched items from Home" setting (`home.hide_watched_items`) doesn't touch Continue Watching.

The fixture `silo/home_continue_watching.json` is built by hand from captured cards (the 2026-10-13 capture was trimmed to three next-up cards): an in-progress film and Young Justice episode, and two next-up episodes. It should be replaced by a capture of the section with in-progress items (the probe saves the first home section as `home_section_items`).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_resume_test.dart` (new, 9 tests):
  - the home section: layout then the section's cards at `image_size=medium`; films and episodes in progress kept, next-up cards left out; position, percentage and last played; episode series fields;
  - types narrow the row; `mediaTypes: Audio` makes no request;
  - `startIndex`/`limit` slicing;
  - two rows loading together read the section once;
  - several Continue Watching sections merged, repeats and audiobooks dropped, other sections not read;
  - a library row reads the library page (`/library/5/layout`, `default-continue-watching`), sets `ParentId` and remembers the library; a non-library parent asks nothing;
  - no section: `/progress` with `status`, `library_id` and `limit`, items read from the catalog, `UserData` from the entry, a missing item left out;
  - errors reach the caller;
  - a card's top-level resume point maps on its own.
- `silo_items_api_library_test.dart`: the not-implemented check now uses `getNextUp` (8.2).
- `server_silo`: 458/458.

**Manual test plan**

Before testing, start a film and an episode on Silo (web app or Emby comparison account), stop part way, and leave a show whose last episode you finished.

1. **Home → Continue Watching** shows the film and the episode with progress bars at the right place, most recent first. The episode card names the series and S/E. Compare with Emby's Continue Watching for the same titles.
2. **No next episodes here**: the show you finished an episode of is not in Continue Watching (it belongs to Next Up, 8.2).
3. **Open a card**: the film or episode page opens (play is phase 10).
4. **Dismiss in Silo**: in Silo's web app, remove the film from Continue Watching; back in Moonfin, pull to refresh Home (or reopen it): the film is gone.
5. **Library page**: open the TV library's page in Moonfin; its Continue Watching row (if shown) holds only that library's episodes.
6. **Silo home without the section** (optional): hide Continue Watching on Silo's web home; Moonfin's row still lists what is in progress (from the resume points).
7. **Continue Listening** row (if enabled) stays empty with no error.
8. **Emby unchanged**.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | resume 9/9; `server_silo` 458/458; analyzer: no issues |

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

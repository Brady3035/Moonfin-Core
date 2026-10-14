# Phase 5: Translation layer

[← Roadmap](../ROADMAP.md)

Pure functions that turn Silo JSON into the Jellyfin/Emby `BaseItemDto` shape the whole app reads. Each mapper is tested against a Silo fixture and diffed against the same title's Emby fixture. No UI changes.

**Phase done when:** Every fixture maps to a BaseItemDto whose fields match the Emby fixture for the keys `AggregatedItem` reads.

---

<a id="step-5-1"></a>
## 5.1 Time, ID and type helpers

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Seconds ↔ ticks, opaque string IDs with synthetic `silo-genre:`/`silo-studio:` forms, and the Silo type → Jellyfin `Type`/`MediaType`/`IsFolder` table.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_ticks.dart`
- `silo_ids.dart`
- `silo_item_types.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- round-trips; every Silo type maps; reverse map for `includeItemTypes`

**Manual test plan**

- _Write the checks before testing._
- Carried from 4.2 and 4.3: a query for **only** types Silo doesn't have (`MusicArtist`, `MusicAlbum`, `Audio`, `Playlist`, `TvChannel`, `mediaTypes=Audio`) must answer empty, not drop the filter and return films. Check on Home with only Silo signed in: no Continue listening, artist, album or playlist row fills with films or episodes.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-5-2"></a>
## 5.2 Image URL registry

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** While mapping, record each artwork URL by item, image type and index, with a tag hashed from the URL **path** so the daily-rotating signature keeps the same tag. Relative URLs get the base URL; absolute (TMDB, TVDB, S3) pass through. Never append a token.

**Silo v2 endpoints**

- `GET /images/capabilities`

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_image_registry.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- tag stable across rotating query strings; size-bucket selection from the capability ladder

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-5-3"></a>
## 5.3 Item mapper: core fields

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Id, Name, SortName, Type, Overview, Genres, Studios, years and dates, OfficialRating, Community/Critic rating, RunTimeTicks, ProviderIds, DateCreated, Status; `backdrop_urls` → every `BackdropImageTags` entry; original payload kept under `_silo`.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: Golden test against `emby/item_movie_*.json`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-5-4"></a>
## 5.4 Item mapper: series, seasons and episodes

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** SeriesId/Name, SeasonId (both id forms), Index numbers, ChildCount, and the Parent*/Series* image fields filled from the series' slots. Since build `4b2e921c` movie and series detail carry `thumb_url` and `banner_url` (when `images/capabilities.extended_item_artwork` is true): use them, and fall back to the backdrop only when they're missing. Use `*_is_episode_still` so an episode still never becomes a series poster.

**Where in Moonfin**

- `silo_item_mapper.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: Golden test against the Young Justice series/season/episode fixtures.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-5-5"></a>
## 5.5 Item mapper: user data

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Favorite, Played, PlaybackPositionTicks, PlayedPercentage, UnplayedItemCount, PlayCount, LastPlayedDate. A missing `user_data` means unplayed at 0.

**Where in Moonfin**

- `silo_item_mapper.dart`

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

<a id="step-5-6"></a>
## 5.6 Item mapper: people

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Cast and crew to `People` with roles and photo tags through the registry.

**Where in Moonfin**

- `silo_item_mapper.dart`

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

<a id="step-5-7"></a>
## 5.7 Library mapper

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** User libraries to `CollectionFolder` with `CollectionType` (movies, tvshows, books, mixed).

**Where in Moonfin**

- `silo_library_mapper.dart`

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

<a id="step-5-8"></a>
## 5.8 Versions and streams → MediaSources/MediaStreams

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** One MediaSource per file version. Build Jellyfin's single stream index space and store the map `index → {kind, ordinal, track_id}` (subtitles keep the container index; video then audio take the lowest free indices). HDR/DV range types.

**Where in Moonfin**

- `silo_media_source_mapper.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- assert by type and ordinal (Emby orders audio first, so a straight golden diff can't work)

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-5-9"></a>
## 5.9 Chapters mapper

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Version chapters → `Chapters` (StartPositionTicks, Name, image tag when a thumbnail exists).

**Where in Moonfin**

- `silo_item_mapper.dart`

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

<a id="step-5-10"></a>
## 5.10 Markers mapper

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Marker segments → `MediaSegmentDto[]` (intro, credits→Outro, recap, preview), every occurrence.

**Where in Moonfin**

- `silo_marker_mapper.dart`

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

<a id="step-5-11"></a>
## 5.11 Trickplay mapper

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `/watch/{id}/trickplay` → Jellyfin `Trickplay` map, registering sheet URLs for `getTrickplayTileImageUrl`.

**Where in Moonfin**

- `silo_trickplay_mapper.dart`

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

<a id="step-5-12"></a>
## 5.12 Cursor pager

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Turn Moonfin's `startIndex/limit` into Silo cursors: first page plain; next page `next_cursor`; any other offset `window_cursor + seek`; `invalid_cursor` → reset once.

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_pager.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- sequential pages; jump; invalid cursor recovery; limit clamps

**Manual test plan**

- _Write the checks before testing._

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-5-13"></a>
## 5.13 Sort map

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Moonfin sort fields → Silo `sort` values (descending = `-field`); unknown → server default.

**Where in Moonfin**

- `silo_sort_map.dart`

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

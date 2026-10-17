# Phase 11: Player features

[← Roadmap](../ROADMAP.md)

The extras around playback.

**Phase done when:** Skip intro, trickplay, chapters and up-next behave as they do on Emby/Jellyfin.

---

<a id="step-11-1"></a>
## 11.1 Skip intro, credits and recap

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Markers through `getMediaSegments`.

**Silo v2 endpoints**

- `GET /markers/items/{id}`
- `GET /markers/files/{file_id}`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_markers.dart` (new): reads and keeps a file's markers
- `silo_items_api.dart`: `getMediaSegments`, `notePlayingFile`
- `packages/playback_silo/lib/src/silo_media_stream_resolver.dart`: names the file it plays
- `packages/server_core/lib/src/feature/feature_detector.dart`: `supportsMediaSegments` and `supportsSkipSegments` on for Silo
- `lib/data/services/media_segment_service.dart`: unchanged; it asks `getMediaSegments` once the flag is on

**Also in this commit: the phase 10 bookkeeping.** The 16 phase 10 hashes and the 10.6 fix (`ec9a9c830`) are filled in, with Brady's macOS Pass rows (2026-10-17), and 10.1–10.16 are ticked in the roadmap. The local trailer button (10.6) still does nothing; Brady will revisit it later, so it stays open in 10.6's Results.

### How it works

Moonfin's skip prompts, auto-skip and "replace skip credits with Next Up" all run on media segments (`MediaSegmentService`, Jellyfin's `MediaSegmentDto`: `Type`, `StartTicks`, `EndTicks`). Silo calls them markers and keeps them per **file**, so a film's two versions can each have their own. 5.10 already maps Silo's `FileMarkers` to segments (`siloMarkersToMediaSegments`: every occurrence in `marker_segments`, Silo's `credits` as Jellyfin's `Outro`, a credits or preview marker without an end running to the file's end). This step reads them:

- **Which file.** When the resolver starts or replans a session it tells the items API which file the item plays (`notePlayingFile(itemId, effective file, runtime)`), and `getMediaSegments(itemId)` then reads `GET /markers/files/{file}`. An item asked for before it plays reads `GET /markers/items/{id}`, which Silo answers with the item's first playable file.
- **Kept 5 minutes per file** (`SiloMarkers.ttl`), since the player asks again for each queue item and each return to it; a failed read isn't kept. A file with no markers, or a 404, has no segments.
- **Times** are source seconds. The player compares segments with the media position, which already includes a remux's timeline offset (10.1), so a skip on a resumed remux lands where it should.
- **The flags.** `supportsMediaSegments` and `supportsSkipSegments` turn on for Silo (phase 1 rule: a flag turns on with the step that makes it work). `MediaSegmentService` checks the second before asking.

What the viewer sees comes from Moonfin's existing settings (segment actions per type: ask to skip, skip, nothing).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_markers_test.dart` (new, 6 tests): an item not playing yet reads `/markers/items/{id}` (Young Justice 1x01: an intro 4:08.0–4:28.3); once the resolver names the file, `/markers/files/89618`; recap, intro and an open-ended credits marker in order, the credits running to the file's end; a film with none and an unknown item (404) give none; a second ask within 5 minutes reads nothing; a failed read isn't kept.
- `packages/playback_silo/test/silo_start_test.dart`: a start names its file, so the segments come from `/markers/files/4598`.
- `server_core/test/feature_detector_test.dart`: the two flags are on for Silo.
- `silo_items_api_library_test.dart`: the not-implemented check moves to `getThemeMedia` (11.5).

**Manual test plan**

In Moonfin's settings, *Skipping & Autoplay*: set *Intro Segments* to *Prompt User*.

- a. Play Young Justice 1x01: at 4:08 the *Skip intro* button shows; pressing it jumps to 4:28. Compare the same episode on Emby.
- b. Set *Intro Segments* to *Skip*: the intro is skipped once by itself; seeking back before 4:08 and playing through skips it again.
- c. Resume the episode at 3:00 (a remux on your setup): the button still shows at 4:08 on the seek bar's time.
- d. A title with credits markers (any episode Silo's web app shows credits for): with *Replace skip credits with Next Up* on, the Next Up card appears at the credits.
- e. xXx (no markers): nothing shows, and playback is as before.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | markers 6/6; `playback_silo` 84/84; feature detector; analyzer: no new issues |
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

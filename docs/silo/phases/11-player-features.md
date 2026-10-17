# Phase 11: Player features

[← Roadmap](../ROADMAP.md)

The extras around playback.

**Phase done when:** Skip intro, trickplay, chapters and up-next behave as they do on Emby/Jellyfin.

---

<a id="step-11-1"></a>
## 11.1 Skip intro, credits and recap

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

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
| ◐ Ready for testing | — | previous step |

**Goal.** Fetch the trickplay manifest when `trickplay_available` is true; refresh after `expires_at`.

**Silo v2 endpoints**

- `GET /watch/{id}/trickplay?file_id=`

**Where in Moonfin**

- `packages/server_core/lib/src/api/trickplay_manifest_api.dart` (new): `TrickplayManifestApi`, an optional `ItemsApi` extra
- `packages/server_silo/lib/src/api/silo_trickplay.dart` (new): reads, keeps and refreshes a file's previews
- `silo_items_api.dart`: implements `TrickplayManifestApi`
- `silo_image_api.dart`, `silo_media_server_client.dart`: a sheet URL handed out refreshes previews that are due
- `lib/data/utils/server_trickplay.dart` (new): `mergeServerTrickplay`
- `video_player_screen.dart`, `video_mini_player.dart`, `appletv_player_host_screen.dart`: call it before reading the item's previews
- `feature_detector.dart`: `supportsTrickplay` on for Silo

### How it works

Moonfin's seek previews read Jellyfin's `Trickplay` item field (`TrickplayInfo.fromItemData`: thumbnail size, tiles per sheet, interval) and load each sheet through `ImageApi.getTrickplayTileImageUrl`. Silo doesn't put previews on its items; a player asks for the file it plays (`GET /watch/{id}/trickplay?file_id=`, `WatchTrickplay`). 5.11 already maps that answer to Jellyfin's field and records each sheet's signed URL in the image registry under the file id. This step reads it:

- **A new optional interface**, `TrickplayManifestApi.getTrickplayManifest(itemId, mediaSourceId:)`, answers the `Trickplay` field for one file. The players call `mergeServerTrickplay` before reading the item's previews: when the server has the interface and the item has no entry for the playing file (`currentResolution.mediaSourceId`, Silo's effective file), the answer is merged into the item and read as Jellyfin's. Jellyfin and Emby don't have it, so nothing changes for them. It is a candidate for upstream with the other `server_core` extras.
- **Silo's side** (`SiloTrickplay`): one read per file, kept until 2 minutes before `expires_at`. A file without previews (404) is remembered for 10 minutes, so a queue doesn't ask again on each return to an episode. A failed read isn't kept. Moonfin doesn't check `trickplay_available` first: the player only knows ids, and the answer for a file without previews is the same 404.
- **Expiry.** Sheet URLs stop working at `expires_at`. A player keeps the grid it read, since that doesn't change, and asks the image API for a sheet URL whenever it shows or prefetches one. Each time, `SiloImageApi` tells `SiloTrickplay` which file it served (`onTrickplaySheet`); once the file's URLs are due, the previews are read again in the background (one read at a time), and the registry hands out the fresh URLs from then on. A sheet loaded earlier stays in the image cache, which keys signed artwork by path (6.2), so it isn't fetched again. A viewer who doesn't scrub at all past `expires_at` may see the first sheet they ask for afterwards fail once; the next ask has the new URL.
- **Times** are media time: a thumbnail *i* covers `i × interval_ms` onward on the file's timeline, and the seek bar is in media time (10.1), so a resumed remux shows the right picture.
- `supportsTrickplay` turns on for Silo (it isn't read anywhere today; kept true to what Silo now does).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_trickplay_test.dart` (new, 5 tests), on the captured Young Justice 1x01 previews (300 × 168, 10 × 8 per sheet, 136 thumbnails, interval 10 s): the answer in Jellyfin's shape and its sheet URLs from the image API; kept until 2 minutes before expiry, then read again; a sheet asked for once the URLs are due reads them again, once; a 404 is remembered for 10 minutes; a failed read isn't kept.
- `test/data/utils/server_trickplay_test.dart` (new, 2 tests): the merged field gives a valid `TrickplayInfo` whose 14:00 tile is on sheet 1, served by the image API; an item with the file's entry isn't read again; no file id, nothing.
- `server_core/test/feature_detector_test.dart`: `supportsTrickplay` on for Silo.
- Existing trickplay tests (`test/data/models/trickplay_*`, 69) pass.

**Manual test plan**

- a. Play Young Justice 1x01 and scrub or hover the seek bar: thumbnails show and match the picture at that point (compare Emby's).
- b. Seek with the arrow keys or the remote while the controls show: the preview follows.
- c. Resume the episode part way through (a remux on your setup): previews still match the seek bar's time.
- d. xXx (no previews on this server): the seek bar works with no thumbnails and no errors.
- e. The mini player (minimise the player, if your build shows it on the Mac): its scrub preview shows thumbnails too.
- f. Optional, long: leave the episode paused past the time its previews expire (shown in Silo's web app network log as `expires_at`, a few hours), then scrub: thumbnails still show (at most the first one may fail once).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | trickplay 5/5; merge 2/2; trickplay model tests 69/69; `server_silo` 549/549; `server_core` 95/95; analyzer: no issues in the changed files |
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

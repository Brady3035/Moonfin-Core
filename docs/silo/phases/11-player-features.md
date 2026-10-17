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
| ☑ Done | — | previous step |

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
| ☑ Done | — | previous step |

**Goal.** Chapters in the player (menu, seek bar marks, previous/next chapter) and chapter thumbnails on the detail page, for the version that plays.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart`: every media source carries its version's `Chapters`
- `lib/data/utils/chapter_markers.dart`: `chaptersForItem(…, mediaSourceId:)`, `itemChaptersForSource`
- `video_player_screen.dart`, `appletv_player_host_screen.dart`: use the playing version's chapters
- (`silo_image_api.dart`: unchanged; chapter thumbnails were wired in 5.9 and 6.1)

### How it works

Most of this already worked before the step: 5.9 maps a version's chapters to Jellyfin's `Chapters` (names, start times, a thumbnail per chapter registered with its tag), the item carries its **default** version's, as Jellyfin does, and 6.1 serves the thumbnails (`getChapterImageUrl` by tag). The detail page's chapter row, the player's chapter menu, the seek bar marks and the previous/next chapter steps read them like Jellyfin's. What was missing is the version: Silo's versions are separate files with their own chapters (The Salt Path's 4K default has none, its 1080p file has 12), and Moonfin showed the default's whatever played.

- **Silo's side.** Each media source now carries its own version's `Chapters` too, and the item's `Chapters` stay the default's. Thumbnails of every version are registered under the item with their own tags, so the detail page and the player find each by its tag. The default's are registered last, so a lookup by index without a tag still finds the default's.
- **Moonfin's side.** `chaptersForItem` takes the playing version (`currentResolution.mediaSourceId`) and uses that media source's `Chapters` when it has them, otherwise the item's. Jellyfin and Emby don't send chapters on their media sources, so they keep the item's as before. The full player's menu, chapter button and marks use the playing version's, and are taken again when a replan or a version change plays another file. The tvOS host hands the same starts to the manager.
- A title played from a row (no chapters on the item) still reads them once with the item (`fetchChapters`), and gets its default version's.

Chapter thumbnail URLs are signed like all Silo artwork (6.1); the image cache keys them by path (6.2), so a thumbnail shown once stays shown.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_chapter_mapper_test.dart` (11 tests, 1 new): The Salt Path's 1080p source carries its 12 chapters, the 4K default's none, the first 1080p thumbnail is found by its tag, and the item's chapters are the default's.
- `test/data/utils/chapter_markers_test.dart` (2 new): the playing version's own chapters; the item's for no version, a version without its own, or an unknown one.
- Existing chapter tests pass (`chapter_steps`, `chapter_transport`, `osd_buttons`: 18).

**Manual test plan**

- a. xXx's detail page: the chapter row shows 16 chapters with thumbnails (compare Emby).
- b. Play xXx: the seek bar shows the chapter marks (with the *Chapter Marks* setting on), the chapter button opens the list with names and times, and picking one seeks there; previous/next chapter (if your build maps them) step through them.
- c. The Salt Path: pick the 1080p version on the detail page and play it: the chapter button shows its 12 chapters. Play the 4K default: no chapter button.
- d. Resume xXx part way (a remux): the marks sit at the same places on the film's time, and picking a chapter seeks to it.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | chapters mapper 11/11; chapter markers 8/8; chapter steps/transport/OSD 18/18; `server_silo` 550/550; analyzer: no issues in the changed files |
| | | | | |

---

<a id="step-11-4"></a>
## 11.4 Next episode and autoplay

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Goal.** Queue from `getEpisodes`; Up Next card.

**Where in Moonfin**

- No code change: the queue, the Up Next card and the move to the next season are Moonfin's own, over `getSeasons`/`getEpisodes` (6.7, 6.8)
- `test/playback/silo_next_episode_test.dart` (new): checks Silo's answers give that logic what it needs

### How it works

Moonfin builds an episode's queue itself and needs nothing Silo-specific for it:

- **The queue.** Playing an episode queues its season (`getEpisodes(series, seasonId:)`, in episode order, `orderSeasonEpisodes`), keeping the episodes that can play (`isEligibleNextEpisodeCandidate`: not virtual or missing, aired, with a media source and a runtime). Silo's season list gives each episode its file (`files` → a media source, 5.8), `runtime`, `air_date`, numbers, and season and series ids that are the same ids `getSeasons` lists (`season-<key>-<n>`, 5.4).
- **The next season.** At the end of the queue the playback module checks that the queue is one season of one show and that the last episode is that season's finale, then asks `getSeasons` for the lowest season number above it and queues its playable episodes.
- **Up Next.** The card shows the queue's next episode at the credits segment (from Silo's markers since 11.1) or the configured time before the end, and autoplay starts it under Moonfin's settings (*Autoplay Next Episode*, *Next Up Display*, *Next Up Timeout*, *Replace Skip Outro with Next Up Display*).
- **Playing it.** The next episode is a season list entry with lightweight files, so the resolver reads the episode once for its full version (10.6), and starts a new Silo session after the previous one is stopped (10.10). Silo then moves Next Up and Continue Watching on itself.

Moonfin doesn't use a Silo "next episode" call: Silo's series cards carry `play_content_id` (8.x) for the Play button, but autoplay works on the queue, as on Jellyfin and Emby.

Nothing was missing, so this step adds tests and the manual checks only.

### Testing

**Automated tests**

- `test/playback/silo_next_episode_test.dart` (new, 3 tests), on Young Justice's captured seasons and season 1 episodes (and the same three as season 2): season 1 queues in order with every episode playable, carrying its series, season and number and a media source; the queue is season-scoped and resolves to season 1; the last episode is the finale and not the second; the next season is season 2, whose episodes are playable; an episode before its air date isn't.

**Manual test plan**

With *Autoplay Next Episode* on:

- a. Play Young Justice 1x01 from the episode list and seek near the end: the Up Next card shows 1x02 with its still and title; letting it count down plays 1x02, which starts from the beginning (not 1x01's position).
- b. With *Replace Skip Outro with Next Up Display* on, the card appears at the credits marker (an episode Silo has credits for), and pressing it plays the next episode.
- c. Finish the last episode of a season (seek near the end of a season finale): playback moves on to the next season's first episode.
- d. Afterwards Silo's web app shows the finished episode watched, and Home's Next Up / Continue Watching show the next one (after Home reloads).
- e. Turn *Autoplay Next Episode* off: the player stops at the end instead.
- f. Compare a and c with the same show on Emby.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | next episode 3/3 |
| | | | | |

---

<a id="step-11-5"></a>
## 11.5 Theme music

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Moonfin's theme music on detail pages plays a title's local theme songs from Silo.

**Silo v2 endpoints**

- `GET /catalog/themes/capabilities`
- `GET /catalog/items/{id}` (its `themes`)
- `POST /catalog/items/{id}/themes/{theme_id}/playback` (a grant)
- `GET /catalog/items/{id}/themes/{theme_id}/audio?token=` (what the grant's URL points to)

**Where in Moonfin**

- `packages/server_core/lib/src/api/theme_song_stream_api.dart` (new): `ThemeSongStreamApi`, an optional `ItemsApi` extra
- `packages/server_silo/lib/src/api/silo_themes.dart` (new): themes, capabilities and grants
- `silo_items_api.dart`: `getThemeMedia`, `themeSongStreamUrl`; `silo_media_server_client.dart` passes the base URL
- `lib/data/services/theme_music_service.dart`: asks the server for the song's link when it has `ThemeSongStreamApi`

### How it works

Moonfin's `ThemeMusicService` plays a random theme song while a detail page is open (*Theme Music* in the detail page settings), fading it in and out. It lists songs with `getThemeMedia` (Jellyfin's `ThemeSongsResult`) and streams one from `/Audio/{id}/stream` with the account's token. Silo lists a title's local theme songs in its detail (`themes`: owner and songs) and plays each through a **grant**: a short-lived URL that carries its own credential, made per play, possibly on a proxy node.

- **Listing.** `getThemeMedia(id)` first checks `GET /catalog/themes/capabilities` (kept 10 minutes; `state` must be `available` and `allowed` not false), then reads the title's detail and answers its songs in Jellyfin's shape (`Id` = Silo's theme id, `Name`, `Container`, `RunTimeTicks`, the owner as `OwnerId`). Silo has no theme videos or soundtracks. An episode's or season's page asks for its series, as on Jellyfin. Without the capability nothing is read.
- **Playing.** A new optional interface, `ThemeSongStreamApi.themeSongStreamUrl(owner, song, accepts:)`, makes the link. `ThemeMusicService` uses it when the server has it, otherwise builds Jellyfin's or Emby's URL as before. Silo's side posts a grant naming the formats the theme player decodes: everything usual for libmpv (media_kit, on the Mac, Windows, Linux and Android), and MP3, AAC/ALAC in MP4 and WAV for AVPlayer on Apple TV. Silo then serves the original when it matches and otherwise converts to AAC in MP4. A relative URL is made absolute on the server's base URL; a proxy node's absolute URL is used as it is. A `404`, `406` or `503` plays nothing.
- **One grant per play.** A grant lasts `grant_lifetime_seconds` (300 s here). Each detail page visit asks for a new one. With *Loop* on, libmpv replays the same URL; an original allows that while the grant lasts, but a converted song has no length or ranges and Silo says to fetch a new grant to replay it, so looping a converted song past its first play may stop. On the Mac every original is accepted, so this only matters on Apple TV (phase 12).

`getThemeMedia` came off the not-implemented list; its check moves to `searchRemoteSubtitles` (10.14).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_themes_test.dart` (new, 6 tests): a title's theme song in Jellyfin's shape with its owner; a title without themes, with the capabilities read once for two pages; a server whose themes are disabled answers none without reading the detail; a play posts a grant with the accepted formats and gets an absolute URL; a proxy node's URL is used as it is; a `406` plays nothing.
- `silo_items_api_library_test.dart`: the not-implemented check moves to `searchRemoteSubtitles`.
- The app side has no unit test (the service needs a player and the audio arbiter); the manual test covers it.

**Manual test plan**

Setup: Silo finds a local theme as a file named `theme.<ext>` (`theme.mp3`) next to a title's file or in its folder, or files in a `theme-music` folder. Add one to a film's and a show's folder and rescan them in Silo; its web app then plays the theme on their pages. In Moonfin turn *Theme Music* on (detail page settings).

- a. Open the film's detail page: the theme fades in; leave the page: it fades out. The network log shows `POST …/themes/<id>/playback` and the audio from the grant's URL.
- b. Open the show, a season and an episode: each plays the show's theme.
- c. Start playing the title: the theme stops before playback starts.
- d. A title without a theme: nothing plays, no errors.
- e. Volume and *Loop* settings apply.
- f. Compare with Emby if the same title has a theme there.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | themes 6/6; `server_silo` 556/556; analyzer: no issues in the changed files |
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

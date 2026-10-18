# Phase 11: Player features

[← Roadmap](../ROADMAP.md)

The extras around playback.

**Phase done when:** Skip intro, trickplay, chapters and up-next behave as they do on Emby/Jellyfin.

---

<a id="step-11-1"></a>
## 11.1 Skip intro, credits and recap

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `684ac0647` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: skip intro, auto skip, the resumed remux and the credits Next Up all work |
| | | | | |

---

<a id="step-11-2"></a>
## 11.2 Trickplay scrubbing

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `51cc69428` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: previews on scrub, after a resume, none on xXx, in the mini player |
| | | | | |

---

<a id="step-11-3"></a>
## 11.3 Chapters and chapter images

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `6403ab9b3` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: chapter row, list, seeking; the marks show once *Chapter Marks* is on (off by default); the 1080p/4K versions |
| | | | | |

---

<a id="step-11-4"></a>
## 11.4 Next episode and autoplay

| Status | Commit | Depends on |
|---|---|---|
| ◐ Open (see Results) | `fd6067c03` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Fail | Brady: a season finale of a show watched before moves on to the next season; on an unwatched show the player closes at the end of the season without Next Up. Not diagnosed yet; deferred by Brady to the end of the project (open) |
| | | | | |

---

<a id="step-11-5"></a>
## 11.5 Theme music

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | `1c87701f3` | previous step |

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
| 2026-10-17 | macOS | `bd9d59ea` | Not tested | Brady: no title on the server has a theme yet; to test later |
| | | | | |

---

<a id="step-11-6"></a>
## 11.6 Per-series audio and subtitle choice *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `924bd780e` | previous step |

**Goal.** Sync Moonfin's per-series track choice with Silo's.

**Silo v2 endpoints**

- `GET/PUT /audio-prefs/{series_id}`
- `GET/PUT /subtitle-prefs/{series_id}`
- `GET /settings/values/effective?keys=&series_ids=`, `PUT /settings/values/{key}?scope=profile_series&series_id=` (`playback.subtitle_language`, `playback.subtitle_mode`)

**Where in Moonfin**

- `packages/server_core/lib/src/api/series_track_preferences_api.dart` (new): `SeriesTrackPreferencesApi`, `SeriesTrackChoice`
- `packages/server_silo/lib/src/api/silo_track_preferences.dart` (new): reads and writes Silo's rows and series settings
- `packages/server_silo/lib/src/mappers/silo_subtitle_order.dart` (new): the combined subtitle order, moved from `playback_silo` (10.14), which re-exports it
- `silo_items_api.dart`: implements the interface; `notePlayingFile` also keeps the playing file's media source
- `lib/data/services/series_track_sync.dart` (new): Silo's choice into the device's
- `lib/data/viewmodels/item_detail_view_model.dart`: syncs on a show's, season's or episode's page
- `lib/di/modules/playback_module.dart`: a choice made in the player is written through

### How it works

Moonfin remembers a series' audio and subtitle choice on the device (`UserPreferences` series track preferences: language, track title, place among same-language tracks, or subtitles off). It picks the remembered track for every episode, and a choice in the player updates it. Silo remembers the same per profile and series: an audio row (Silo's track index, language, signature), a subtitle row (combined index or -1 for off, language, mode, signature), and two series-scope settings, `playback.subtitle_language` and `playback.subtitle_mode`. Silo's web player writes those settings with the row, and they outrank the row's language and mode. Silo also writes the audio row itself whenever a session starts or replans with an audio track (10.6, 10.13), and uses it when a start names none.

A new optional interface, `SeriesTrackPreferencesApi`, reads and writes a series' choice. It is a candidate for upstream with the others.

- **Moonfin → Silo.** When the viewer picks a track in the player, the device's preference is saved as before, and the choice is written to Silo too (best effort): audio as `PUT /audio-prefs` with Silo's track ordinal; subtitles as `PUT /subtitle-prefs` (combined index, language, mode `always`, signature) plus the two series settings, or for *Off* the row with -1 and mode `off`, the language setting cleared and the mode setting `off`. This is what Silo's web player writes. Track indices are Silo's, so the write uses the playing file's track map, which the resolver now hands to the items API with the playing file. A downloaded subtitle (one Silo numbers only inside a plan) isn't written, nor anything when no file was noted.
- **Silo → Moonfin.** Opening a show's, season's or episode's page reads Silo's choice (`syncSeriesTrackChoices`): the audio row (language and track title), and the subtitle row with the series-scope settings on top (a profile-wide setting is not a series choice, so only `profile_series` values count). Silo's choice replaces the device's when it names another language, or turns subtitles off or on where the device's doesn't. A device choice in the same language is kept as it is, since it also knows which of two same-language tracks was picked. The page refreshes its track highlights when something changed.
- **Why on the page.** The player picks tracks while a start is being prepared, synchronously, so Silo's choice has to be on the device before then. Every way into a show's episodes from its pages goes through one of these pages. An episode started straight from a Home card uses what the device already has, and Silo applies its own audio choice when the start names no track.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_track_preferences_test.dart` (new, 10 tests):
  - reading: an audio row's language and title; no choice for a 404 or track -1; the subtitle row with the series language setting on top (the request names both keys and the series); a newer language drops the row's label; off from the settings or the row; a profile-wide setting isn't a series choice.
  - writing: xXx's audio stream 1 as Silo's track 0 with its signature; its forced English sidecar as combined index 0 with the two series settings; off writes -1, clears the language, mode `off`; nothing without a noted file or for a track Silo doesn't number.
- `test/data/services/series_track_sync_test.dart` (new, 4 tests): Silo's choices fill an empty device (Japanese audio, subtitles off); another language replaces the device's; the same language (`en` and `eng`) keeps the device's track and its place; nothing on Silo changes nothing.
- `playback_silo` 84/84 (the subtitle order tests run through the re-export); view model tests `test/viewmodels/` 76/76.

**Manual test plan**

Use a show with two audio languages or several subtitle tracks (an anime with Japanese and English audio is ideal).

- a. In Moonfin play an episode, switch audio to Japanese and subtitles to English. In Silo's web app play another episode of the show: it starts in Japanese with English subtitles.
- b. In Silo's web app pick English audio and subtitles off on an episode. In Moonfin open the show's page (or an episode's), then play an episode: English audio, no subtitles.
- c. In Moonfin turn subtitles off on an episode: Silo's web app plays the next episode without subtitles.
- d. A film is unaffected (no series): picking a track there writes nothing to Silo (network log).
- e. Regression on Emby: the per-series choice still carries to the next episode as before.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | track preferences 10/10; sync 4/4; `server_silo` 566/566; `playback_silo` 84/84; view models 76/76; analyzer: no new issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: Moonfin → Silo web, Silo web → Moonfin, subtitles off |
| | | | | |

---

<a id="step-11-7"></a>
## 11.7 Shuffle *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `c731063c5` | previous step |

**Goal.** Silo's server-side shuffle for a series or library.

**Silo v2 endpoints**

- `GET /shuffles/capabilities`
- `POST /shuffles`
- `POST /shuffles/{id}/advance`

**Where in Moonfin**

- `packages/server_core/lib/src/api/server_shuffle_api.dart` (new): `ServerShuffleApi`, `ServerShuffle`
- `packages/server_silo/lib/src/api/silo_shuffles.dart` (new): scopes, start, advance
- `silo_items_api.dart`: implements `ServerShuffleApi`
- `lib/playback/server_shuffle_queue.dart` (new): the running shuffle as a growing queue
- `item_detail_screen.dart`: *Shuffle* starts the server's shuffle when there is one
- `playback_module.dart`: the queue extension asks the shuffle for its next item

### How it works

Moonfin's *Shuffle* button (on a show, season, collection or library page) loads every item and shuffles them on the device. Silo can shuffle itself: `POST /shuffles` over a scope (`series`, `season`, `library`, `library_collection`, `user_collection`) answers the item to play now and the one after it, and `POST /shuffles/{id}/advance` with the finished item moves it on and picks another. Silo plays every movie and episode of the scope once before any repeats, and the order carries on in its web app and on other devices.

- **A new optional interface**, `ServerShuffleApi` (`canShuffle`, `startShuffle`, `advanceShuffle`). It is a candidate for upstream with the others.
- **Silo's side** (`SiloShuffles`). A page's item becomes Silo's scope by its id: a show, a season, a library view (by type, since person ids are numbers too), a personal collection (`user_collection`) or a library's collection (`library_collection`). Only the kinds `GET /shuffles/capabilities` lists are used (kept 10 minutes; none unless `state` is `available`). The answer's cards are mapped like any catalog card. When `next` equals `current`, the scope has one item and there is no next. Starting isn't retry-safe (a repeat starts a second shuffle, which Silo cleans up later), so it goes once. Advancing is retry-safe: it only moves on from the item named.
- **Moonfin's side** (`ServerShuffleQueue`). *Shuffle* first asks the server. When it shuffles that page, the queue is its two items (the first read in full, as before). When the second becomes the queue's last item, the playback module's queue extension (the same hook that moves an episode queue to the next season) asks the shuffle: it advances from the first and adds the item Silo picks next. Silo's current item is always the one Moonfin plays, and the queue grows by one each time. Only one shuffle is followed; starting another replaces it, and a queue that no longer ends in the shuffle's next item isn't extended. Without the interface, for a page Silo can't shuffle, or if starting fails, *Shuffle* works as before.
- Skipping to the next item in the player moves the shuffle on too (the next item becomes the last one). Moonfin doesn't use `POST /shuffles/{id}/skip` (replace the next item without playing) or `DELETE`: Moonfin has no control for the first, and Silo removes abandoned shuffles itself.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_shuffles_test.dart` (new, 6 tests): scopes for a show, a season, a library, both kinds of collection, none for a person or a film; only the kinds the capabilities list, read once, and none while shuffles are disabled; a start posts the scope and answers two Young Justice episodes with their series and season; one item has no next; an advance names the item that was current; a gone shuffle answers null.
- `test/playback/server_shuffle_queue_test.dart` (new, 2 tests): a show's shuffle queues two, then grows one at a time, advancing from the item that was current each time, and not twice for the same item; a film isn't shuffled by the server.

**Manual test plan**

- a. On Young Justice's page press *Shuffle*: a random episode plays. The network log shows `POST …/shuffles` (not a read of every season).
- b. Skip to the next item (or let it end): another random episode plays, and the log shows `POST …/shuffles/<id>/advance`. Keep going a few times: no episode repeats.
- c. Shuffle a season, a movie library and a collection: each plays random items from it.
- d. Start a shuffle of the same show in Silo's web app afterwards: it doesn't replay what Moonfin's shuffle just played (Silo remembers what each shuffle played; a new shuffle starts over, so this only shows for one shuffle). Optional.
- e. Regression on Emby: *Shuffle* on a show plays a random episode as before.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-17 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | shuffles 6/6; shuffle queue 2/2; analyzer: no new issues |
| 2026-10-17 | macOS | `bd9d59ea` | Pass | Brady: shuffling a show works. The nav bar's shuffle picker only offered the start of the alphabet: fixed under 5.13 (`36f999a42`) |
| | | | | |

---

# Phase 8: Home screen

[← Roadmap](../ROADMAP.md)

Moonfin's own home rows, one row type per commit.

**Phase done when:** Home looks like it does on Emby for the same account, minus the rows Silo can't provide.

---

<a id="step-8-1"></a>
## 8.1 Continue Watching

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `8ce77ba` | previous step |

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
| 2026-10-15 | macOS | `bd9d59ea` | Pass | Brady: all six checks pass |

---

<a id="step-8-2"></a>
## 8.2 Next Up

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `ac1d2cd` | 8.1 |

**Goal.** Home `next_up` section (tolerate it being absent); per series via `play_content_id`.

**Silo v2 endpoints**

- `GET /home/layout`, `GET /home/sections/{id}/items` (and the library page's, as in 8.1)
- `GET /catalog/items/{id}` (a series' `play_content_id`, then that episode)

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`: `getNextUp`.

### How it works

Moonfin asks `ItemsApi.getNextUp` in two places:

- **the Next Up row** (`RowDataSource.loadNextUp` and the library and multi-server versions): no series, `enableResumable: false`, a date cutoff from the user's setting;
- **a series page** (`ItemDetailViewModel._loadNextUp`): `seriesId`, `limit: 1`, for the "next up" episode card.

**The row.** Silo works out each show's next episode per profile (the episode after the last one finished, skipping dismissed and dropped shows) and presents it according to the profile's `ui.next_up_mode` setting:

- `combined` (Silo's default): inside the Continue Watching section, as cards with `item_source: next_up`. Silo keeps one card per show there, preferring an episode already started;
- `separate`: as a section of its own, `section_type: next_up` (Silo's "On Deck").

Moonfin reads both from the page, through the same `SiloHomeSections` as 8.1: the `next_up` cards of the Continue Watching sections first, then the cards of any `next_up` section, episodes only, without repeats. So the row works with either setting, and Continue Watching and Next Up share their reads when Home loads them together. A page with neither section gives an empty row. A library `parentId` reads that library's page, like 8.1.

- Order is Silo's: most recently finished show first, as Emby's legacy Next Up.
- `enableResumable: false` leaves out an episode already started (it is in Continue Watching). Silo's next-up cards are unstarted, so this rarely drops anything.
- `nextUpDateCutoff` (Moonfin's "max age" for Next Up) is ignored: Silo decides when a show stops being current.
- `startIndex`/`limit` slice the list.

**A series' next episode.** A Silo series carries `play_content_id`, the episode its own Play button starts (Silo's resume, next-episode and first-episode logic). `getNextUp(seriesId:)` reads the series, then that episode (`getItem`, so it arrives with media sources like any episode page), and answers it unless it was already watched (`Played`, Silo's answer for a series finished) or, with `enableResumable: false`, already started. When the series names no episode, nothing.

**Not covered here:**

- Moonfin then dates each next-up card by its show's last play (`enrichNextUpItemsWithSeriesLastPlayed`, used to merge rows across servers). It reads the 100 most recently played episodes with `sortBy: DatePlayed`, and reads any show not among them one by one. `DatePlayed` maps to Silo's `date_viewed` since the 5.13 follow-up later in this batch, with the date from `sort_metrics.viewed_at`; before it, Silo answered in its default order and Moonfin read nearly every show separately.
- Hiding a card from Next Up is 9.7.

The fixture's next-up cards are the captured ones from 2026-10-13. Like Silo's, they carry no `progress_updated_at` (only in-progress cards do).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_next_up_test.dart` (new, 9 tests):
  - the row from the Continue Watching section's `next_up` cards, in Silo's order, with series fields and no position; the in-progress cards left out;
  - Continue Watching and Next Up loading together read the layout and the section once;
  - a separate `next_up` section is read, films in it left out;
  - a page with neither section: empty, only the layout read;
  - `enableResumable: false` drops a started episode;
  - a library row reads the library page and remembers the library;
  - one series: the series then its `play_content_id` episode, with media sources; nothing when that episode was watched; nothing (and no second request) when the series names none; nothing asked for a film id.
- `silo_items_api_library_test.dart`: the not-implemented check now uses `getLatestItems` (8.3).
- `server_silo`: 467/467.

**Manual test plan**

Before testing: finish an episode of a show that has a next one (in Silo's web app if playback in Moonfin isn't there yet), so it has a next episode.

1. **Home → Next Up** lists that show's next episode, with series name and S/E, most recently watched show first. Compare with Emby's Next Up for the same account.
2. **No duplicates with Continue Watching**: a show with a started episode appears in Continue Watching, not also in Next Up.
3. **Silo's "Separate row" setting**: in Silo's web app set *Next up episodes* to *Separate row*, reopen Moonfin's Home: Next Up still lists the same episodes. Set it back.
4. **Series page**: open that show in Moonfin: the next-up episode card names the right episode. A show never started shows its first episode; a show fully watched shows none.
5. **Library page**: the TV library's Next Up row (if shown) lists only that library's shows.
6. **Emby unchanged**.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | next up 9/9; `server_silo` 467/467; analyzer: no issues |
| 2026-10-15 | macOS | `bd9d59ea` | Pass | Brady: all four checks pass |

---

<a id="step-8-3"></a>
## 8.3 Latest per library

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `8d162e6` | 8.2 |

**Goal.** Recently added per library.

**Silo v2 endpoints**

- `GET /catalog?library_id=&type=&sort=-added_at|-latest_episode_added&groups=`
- `GET /user/libraries` (the library's kind, cached since 6.4)
- `GET /settings/values/effective?keys=home.hide_watched_items`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`: `getLatestItems`.
- `packages/server_core/lib/src/feature/feature_detector.dart`: `supportsLatestItemsExcludes`.
- `lib/ui/screens/settings/library_settings_screen.dart`: the "Show in Latest Media" switch.

### How it works

Moonfin builds a "Latest in <library>" row per library (`RowDataSource.loadLatestMedia`) with `ItemsApi.getLatestItems(parentId: <library>, limit: …)`, Jellyfin's `/Users/{id}/Items/Latest`. The media bar and the Android TV launcher channels ask it across the server by type (`includeItemTypes: [Movie]` or `[Series]`/`[Episode]`). Jellyfin answers a bare list, which the Emby client wraps as `{Items, TotalRecordCount}`; Silo's answer has the same shape.

**One catalog page, newest first.** Silo's Home has "Recently added" sections, but those are the profile's own rows (a library's can be removed), and `GET /recommendations/recently-added` covers a fixed window and isn't per library. The catalog is always there, so Latest is one catalog page through the pager (5.12):

| Library (or asked types) | `type` | `sort` |
|---|---|---|
| Films (`movies`, `[Movie]`) | `movie` | `-added_at`: when the file arrived |
| TV (`tvshows`, `[Series]`, `[Episode]`, `[Season]`) | `series` | `-latest_episode_added`: when the show's newest episode arrived |
| Mixed, or a kind Moonfin doesn't know | `video` | `-added_at` |

- **TV as shows.** Jellyfin groups a show's new episodes into the show, and Moonfin turns a TV library's Latest into series cards anyway (`normalizeLatestMediaItems`). Silo's `latest_episode_added` (the time the newest episode file arrived) puts a show with a new episode back at the front, so a TV row is the shows in that order. In a mixed library both kinds share one sort, so a series counts from when it was first added.
- **Watched titles: as on Silo.** Silo has a per-profile setting, *Hide watched items from Home* (`home.hide_watched_items`, off by default); when on, Silo leaves watched titles out of its ordinary Home sections, Recently Added among them (featured, Continue Watching and watch-history sections keep them). Latest follows it: the setting is read from the profile's effective settings (once a minute, shared by every Latest row), and when on the query adds the rule `watched is false` (a show leaves once every episode is watched). Like Silo, a setting that can't be read counts as off, so nothing disappears because of an error. This differs from Emby, which hides watched titles from Latest by default (`HidePlayedInLatest`); Brady chose Silo's behaviour.
- **The kind** comes from `includeItemTypes` when given, else from the library's `CollectionType` (the libraries list, cached 5 minutes since 6.4). Types Silo can't list (music…) answer empty with no request, and so does a `parentId` that isn't a library.
- **Size.** `limit` defaults to Jellyfin's 20. TV rows ask for 80 (Moonfin asks four times the row for TV, to fill it after grouping); both fit the pager's one page of 100.

**"Show in Latest Media" (open since 2.7, D3).** Moonfin's library settings let you hide a library from the Latest rows, kept on Jellyfin and Emby in the user's `LatestItemsExcludes`. Silo has no such setting and keeps none for a client (its settings store only takes its own keys), so on Silo the switch would flip and then come back. Like phase 4's gates (D10), the switch now asks a `FeatureDetector` flag, `supportsLatestItemsExcludes`, false for Silo: a Silo library shows only "Show in navigation". Every Silo library gets its Latest row; the Latest section as a whole can still be turned off in Home settings. See D11.

**Not covered here:** Silo's Home groups new TV arrivals Plex-style (one episode alone, several as their show); Moonfin's Latest stays Jellyfin-style (shows).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_latest_test.dart` (new, 7 tests):
  - a TV library: `library_id`, `type=series`, `sort=-latest_episode_added`, `image_size`, one page of 100; series cards with the library as `ParentId`, remembered for the ancestors;
  - a film library: `type=movie`, `sort=-added_at`, no watched rule (the setting off), Jellyfin's default 20;
  - `home.hide_watched_items` on: the `watched is false` rule; off: none; the setting read once for two rows;
  - a setting that can't be read hides nothing;
  - a mixed library: `type=video`, `-added_at`;
  - across the server by type: `[Movie]` → `movie` without a library, `[Episode]` → `series`, `[Movie, Series]` → `video`;
  - types Silo lacks and a non-library parent: empty, no request.
- `packages/server_core/test/feature_detector_test.dart`: `supportsLatestItemsExcludes` on for Jellyfin and Emby, off for Silo.
- `silo_items_api_library_test.dart`: the not-implemented check now uses `getRecentlyReleasedItems` (8.4).
- `server_silo`: 474/474; `server_core`: 94/94; app analyzer: no errors or warnings.

**Manual test plan**

1. **Home → Latest Movies** (the Movies library's Latest row): newest films first, watched ones included (Silo's default). Compare with Silo's web "Recently Added in Movies" (Emby hides watched films here by default, so it may list fewer).
2. **Latest TV Shows**: series cards, the show with the most recent new episode first. Compare with Emby (Emby may show a lone new episode's season or episode where Moonfin shows the show).
3. **Hide watched items**: in Silo's web app turn on *Hide watched items from Home* (Settings → navigation), wait a minute, reload Moonfin's Home: watched films leave Latest Movies, and shows you finished leave Latest TV Shows. Turn it off again: they come back.
4. **Library settings** (Settings → Libraries) with Silo active: each Silo library has only "Show in navigation", no "Show in Latest Media". With Emby active, both switches are there and work as before.
5. **Media bar** set to "Latest" (Settings → Home → media bar source, if offered): it fills with recent Silo titles.
6. **Emby unchanged**: Latest rows and the switch.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | latest 7/7; `server_silo` 474/474; `server_core` 94/94; app analyzer: no errors or warnings. Watched titles follow Silo's `home.hide_watched_items` (Brady's choice, before testing) |
| 2026-10-15 | macOS | `bd9d59ea` | Pass | Brady: all four checks pass |

---

<a id="step-8-4"></a>
## 8.4 Recently released

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `faae7a7` | 8.3 |

**Goal.** Sorted by release date.

**Silo v2 endpoints**

- `GET /catalog?library_id=&type=&sort=-release_date&groups=` (rule `release_date lt <tomorrow>`)
- `GET /settings/values/effective?keys=home.hide_watched_items` (read in 8.3)

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`: `getRecentlyReleasedItems`; a clock for the date.
- `packages/server_silo/lib/src/silo_media_server_client.dart`: passes the session's clock.

### How it works

Moonfin's "Recently released in <library>" rows (`RowDataSource.loadRecentlyReleased`), the media bar's "recently released" source and the launcher's "upcoming" channel ask `ItemsApi.getRecentlyReleasedItems`. On Jellyfin and Emby that is `/Users/{id}/Items` sorted by `PremiereDate` descending with `MaxPremiereDate` now, so nothing announced for later shows. The row asks by type: films for a film library, and for a TV library series, seasons or episodes, as the user's "Recently released" setting says.

On Silo it is one catalog page through the pager:

- **`sort=-release_date`**: Silo's release date is a film's release, a series' first air date, an episode's air date (the same values Moonfin shows as `PremiereDate`).
- **Released by today**: the rule `release_date lt <tomorrow>`, tomorrow in the device's time zone (Silo compares calendar dates; its date rules take `lt` but not `lte`). The client's clock is passed in so tests can fix the day.
- **The kind**: from `includeItemTypes`, else from the library (as in 8.3). An episode stays an episode here; a season counts as its series, since the catalog doesn't list seasons. So the "season" choice in Moonfin's setting gives the same row as "series" on Silo.
- **Watched titles: as on Silo**, like Latest (8.3): they stay unless the profile turned on *Hide watched items from Home*, which Silo applies to its Recently Released section too; then the rule `watched is false` joins the date rule. `limit` defaults to 20; the answer keeps Silo's total. `recursive` changes nothing, as the catalog lists a library's titles at every depth. Types Silo can't list and a parent that isn't a library answer empty without a request.

**Not covered here:** Silo also has a `recently_released` home section with the same order; Moonfin keeps its own rows.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_recently_released_test.dart` (new, 5 tests):
  - a film library: `library_id`, `type=movie`, `sort=-release_date`, the rule with tomorrow's date from the test clock, `image_size`, one page of 100; films in Silo's order with their premiere dates and the library as parent;
  - with *Hide watched items from Home* on, the watched rule joins the date rule;
  - a TV library by setting: series → `series`, season → `series`, episode → `episode`, no types → the library's kind;
  - across the server: `[Movie, Series]` → `video`, no library;
  - types Silo lacks and a non-library parent: empty, no request.
- `silo_items_api_library_test.dart`: the not-implemented check now uses `createCollection` (9.5).
- `server_silo`: 479/479.

**Manual test plan**

Turn on the "Recently released" home section (Settings → Home) if it isn't on.

1. **Recently released in Movies**: films newest release first, nothing with a future date. Compare with Emby's row for the same library.
2. **Recently released in TV Shows** with the setting on *Series*: shows by first air date. On *Episode*: episodes by air date, today's at most. On *Season*: same as *Series* (Silo has no season listing).
3. **A film releasing later** (if your library has one, e.g. a pre-release copy with a future date): not in the row.
4. **Hide watched items** on in Silo's web app (as in 8.3): watched titles leave the row after a minute and a Home reload; off again, they return.
5. **Emby unchanged**.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | recently released 5/5; `server_silo` 479/479; analyzer: no issues |
| 2026-10-15 | macOS | `bd9d59ea` | Pass with note | Brady: checks 1–3 pass. The row stops at its first page (Moonfin's row size) for both films and shows, where other Home rows load more as you scroll: asked for paging, done in `silo(8.4): Page recently released` |

---

<a id="step-8-5"></a>
## 8.5 Favorites row

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `3c2447d` | 8.4 |

**Goal.** `source=favorites`.

**Silo v2 endpoints**

- `GET /catalog?type=&groups=[favorited is true]&sort=` (in place since 6.10)

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`: favourite collections.
- `packages/server_silo/test/silo_items_api_favorites_test.dart` (new).

### How it works

Home's favourite rows (Favorite Movies, Series, Episodes, People…, `RowDataSource.loadFavorites`, and the per-library and multi-server ones) are ordinary item queries: `getItems(includeItemTypes: [Movie], isFavorite: true, sortBy: <the row's sort>, recursive: true, limit: 20)`, once for the whole server, or once per library when some libraries are hidden from Home.

**Already served by the catalog.** Since 6.10, `isFavorite` becomes Silo's rule `favorited is true` on `GET /catalog`, with the type scope, sort and paging of any library query. Silo's rule matches the profile's favourites by content id, for films, series and episodes alike, so every video favourite row works without a Silo-specific path. The plan named Silo's `source=favorites` list (and `GET /favorites`); it was checked and not used:

- it gives the same titles (both read the profile's favourites);
- the library grid's Favourites filter and its alphabet jump (6.11) go through the same `getItems`, and the jump's letter index is computed for a plain catalog query with rule groups, which `source=favorites` isn't;
- the rows always ask a sort, so the favourites list's own order (newest favourite first) wouldn't show anyway.

**Fixed here: favourite collections.** A query for `BoxSet` lists collections (6.15) and ignored `isFavorite`, so a favourite-collections view would have listed every collection. Silo's favourites are titles only, so a favourites query for collections now answers empty, without a request.

**Silo has no favourite people**, and no music: those rows (People, Artists, Albums, Songs, Music Videos) ask for types Silo can't list and answer empty without a request (5.1), so Home leaves them out.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_favorites_test.dart` (new, 4 tests), on the captured favourites:
  - films: `type=movie`, the `favorited` rule, the row's sort, no `source`; the captured series left out of a films row; every card a favourite;
  - series and episodes: their scopes with the rule and sort;
  - one library at a time (`library_id`) when some are hidden;
  - people and collections: empty, no request.
- `server_silo`: 483/483.

**Manual test plan**

In Silo's web app, favourite two films, a series and an episode (or use existing favourites). Turn on the favourite rows in Home settings.

1. **Favorite Movies**, **Favorite Series**, **Favorite Episodes**: each lists what you favourited in Silo, in the row's sort. Compare with Emby's rows for favourites there.
2. **Favorite People**: no row (Silo has none).
3. **Hide a library** that holds a favourite film (Settings → Libraries → *Show in navigation* off): Favorite Movies drops it. Turn it back on.
4. **Unfavourite a film in Silo**, reload Home: it leaves the row.
5. **Library grid → Favourites filter** (6.10): still lists the same films; the alphabet jump works on it.
6. **Emby unchanged**.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | favourites 4/4; `server_silo` 483/483; analyzer: no issues |
| 2026-10-15 | macOS | `bd9d59ea` | Pass | Brady: all four checks pass |

---

<a id="step-8-6"></a>
## 8.6 Collections and genre rows

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `d6040bb` | 8.5 |

**Goal.** Check the remaining row types in `row_data_source.dart` and fix any hand-built URL.

**Silo v2 endpoints**

- `GET /collections`, `GET /library/{id}/collections` (6.15)
- `GET /user/libraries` (6.4)

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`: collections with no library.
- `lib/data/services/row_data_source.dart`, `lib/ui/screens/home/home_view_model.dart`: checked, unchanged.

### How it works

**The other rows, checked.** Every Home row Moonfin can show was traced to the `ItemsApi`/`UserViewsApi` calls it makes, with which arguments, and what Silo does with them now:

| Row | Moonfin call | On Silo |
|---|---|---|
| Continue Watching, Next Up, Latest, Recently released, favourites | `getResumeItems`, `getNextUp`, `getLatestItems`, `getRecentlyReleasedItems`, `getItems(isFavorite)` | 8.1–8.5 |
| My Media (library tiles and buttons) | `getUserViews` | 6.4 |
| Genres | `getGenres`, then per genre `getItems(genreIds, sortBy: Random, limit: 10)` for its artwork | 6.12. Silo genres have no counts, so Moonfin keeps each genre and drops one only when its titles query is empty |
| A genre row (added from Home settings) | `getItems(genreIds)` | 6.12 |
| Studios | `getStudios` | 6.13 |
| **Collections** | `getItems(includeItemTypes: [BoxSet], sortBy, limit: 20)`, per library when some are hidden | **fixed here**, below |
| A collection row (added from Home settings) | `getItems(parentId: <collection>)`; "Playlist order" asks the Moonfin plugin, which Silo lacks (4.6), and falls back to the collection's order | 6.15 |
| Since You Watched, Rewatch | `getItems(filters: [IsPlayed], sortBy: DatePlayed)` and `getSimilarItems` | Work. `DatePlayed` maps to Silo's `date_viewed` with the 5.13 follow-up at the end of this batch; before it, "most recently watched" was Silo's default order |
| Seasonal, IMDb/TMDB charts, Seerr, Radarr/Sonarr | Moonfin plugin or Seerr | Hidden on Silo (4.6–4.9) |
| Live TV, playlists, music rows | | Hidden on Silo (4.1–4.3) |
| Continue Reading/Listening (books) | | Phase 16; empty until then |

**Hand-built URLs:** none left on Home. The only one near it, the account avatars in the user menu, already asks the Silo client for the avatar Silo sent (6.1). Artwork everywhere goes through the image API (6.1–6.3).

**Fixed: the Collections row.** On Emby the row lists every collection the user can see. On Silo, `getItems([BoxSet])` with no library listed only the profile's personal collections (6.15), so a server whose collections are all curated per library (Silo's admin collections) showed an empty row. Now, with no library, it lists:

- the personal collections (`GET /collections`), then
- each visible library's curated collections (`GET /library/{id}/collections` for every library in the libraries list, which leaves out hidden ones, 6.4), read together. A library whose list can't be read is skipped, and so is the lot if the library list can't be.

A name sort (`SortName` or `Name`, the rows' usual one) is applied to the merged list, either direction; another sort keeps Silo's order, personal first. Paging and the total cover the merged list. With a library as parent, nothing changes: that library's collections.

This also widens the list Home settings offers when adding a collection row, and Moonfin's "add to collection" dialog, which lists collections the same way. Only personal collections can be changed; 9.5 has to keep the dialog to those.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_home_collections_test.dart` (new, 3 tests):
  - every collection, personal and each library's, by name in either direction; a library whose list fails is skipped;
  - another sort keeps Silo's order, personal first;
  - ids and `ParentId` say where each came from; the total counts all of them.
- `silo_items_api_collections_test.dart` (6.15) unchanged: a library's collections, a collection's titles.
- `server_silo`: 486/486.

**Manual test plan**

1. **Home → Collections** (turn the row on in Home settings): lists your personal Silo collections and the libraries' curated ones, by name. Compare with what Silo's web app lists.
2. **Open a curated collection** from the row: its titles, sortable (6.15).
3. **Home settings → add a collection row**: the picker lists the same collections; add a curated one and it shows on Home.
4. **Hide a library** that has curated collections (*Show in navigation* off): its collections leave the Collections row. Turn it back on.
5. **Genres row**: genres with artwork from their titles; opening one lists its titles.
6. **Studios row**: studios and networks; opening one lists its titles.
7. **My Media**: the library tiles and buttons as before.
8. **Since You Watched / Rewatch** (if you use them): rows appear without errors, built from what you watched most recently (needs the 5.13 follow-up).
9. **Emby unchanged**.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | home collections 3/3; `server_silo` 486/486; analyzer: no issues |
| 2026-10-15 | macOS | `bd9d59ea` | Fail | Brady: the Genres row doesn't show on Home once switched on (the per-genre rows are listed in Home settings); Studios and My Media pass; Rewatch looks sorted by name. Genres: Silo refuses `sort=random`, which each genre card's artwork query sends, so every genre was dropped; fixed in `silo(5.13): Fix random sort`. Rewatch: by name because `DatePlayed` wasn't mapped yet (`silo(5.13): Sort by date played` was not applied for this test), and its shows picked a season instead of an episode: fixed in `silo(8.6): Fix Rewatch shows` |

---

<a id="step-8-7"></a>
## 8.7 Server-curated home sections *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 8.6 |

**Goal.** A new row kind that renders Silo's own home sections (recommended, trending…).

**Silo v2 endpoints**

- `GET /home/layout`
- `GET /home/sections/{id}/items`

**Where in Moonfin**

- `packages/server_core/lib/src/api/server_home_sections_api.dart` (new): `ServerHomeSectionsApi`, `ServerHomeSection`.
- `packages/server_silo/lib/src/api/silo_items_api.dart`: implements it.
- `lib/preference/home_section_config.dart`: `HomeSectionPluginSource.server`.
- `lib/data/services/row_data_source.dart`: loads such a row.
- `lib/ui/screens/settings/home_sections_screen.dart`: lists the server's rows in Home settings.
- `lib/ui/screens/home/home_screen.dart`: the row's subtitle.
- `lib/l10n/app_en.arb`: `siloServerRowSubtitle`.

### How it works

Silo curates a home page per profile: Continue Watching, plus rows like Hidden Gems, Trending on Server, Seasonal Picks, Recently Added in each library, and any the admin or profile added (`GET /home/layout`, each row's cards from `GET /home/sections/{id}/items`). Moonfin builds its Home from its own row types, so these are offered as **extra rows the user can switch on**, the way Moonfin already offers each collection or genre as a row of its own.

**A small optional interface.** `server_core` gets `ServerHomeSectionsApi`, which an `ItemsApi` may also implement (like `LetterPositionApi`, 6.11): `getServerHomeSections()` lists the server's rows (id, title, kind) and `getServerHomeSectionItems(id)` gives one row's items in Jellyfin's shape. The app checks `itemsApi is ServerHomeSectionsApi`; Jellyfin and Emby don't implement it and are untouched. This is an interface addition to raise upstream before the PR (README).

**On Silo** (`SiloItemsApi`, through 8.1's `SiloHomeSections`):

- the rows are the layout's sections in Silo's order, **without Continue Watching and Next Up**, which Moonfin builds itself (8.1, 8.2). A failed read throws, so the settings screen doesn't take it for "no rows";
- a row's items are its cards, mapped like any catalog card, types Moonfin can't show left out, in Silo's order. Silo caps a section at its `item_limit`, so the row comes whole; a row no longer in the layout is empty. The layout is reused for a minute (8.1).

**In the app:**

- **Home settings** (`HomeSectionsScreen._refreshPluginSections`) reads the active server's rows next to the collections, genres and Seerr sliders it already discovers, and lists each as a `pluginDynamic` entry with source `server` (the row's id in `pluginSection`, its title in `pluginDisplayText`), **off** until the user turns it on, subtitled "From your server". Titles follow the server; a row the server no longer has is dropped; a failed read leaves the list as it was. Only the active server's entries are touched.
- **Home** loads an enabled entry through `RowDataSource.loadDynamicSection`: the server's row, all items at once, as a plain item row (`HomeRowType.pluginDynamic`) with the same subtitle. Opening a card opens the title as anywhere else.
- Entries are saved with the rest of the Home layout; a version of Moonfin without this source reads one back as a collection entry with no collection, which shows nothing.

**New string:** `siloServerRowSubtitle` ("From your server"), added to `app_en.arb`; the generated localizations are regenerated, and the stale `ca`, `fi`, `pt` and `hu` files got only the new getter.

**Not covered here:** Silo's featured sections, editing Silo's layout from Moonfin, and Continue Watching/Next Up as Silo-curated rows (Moonfin's own rows cover them).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_server_sections_test.dart` (new, 4 tests): the captured layout's rows without Continue Watching, with id and kind; a row's items in Silo's order (the layout read reused, `image_size=medium`); a row Silo no longer has is empty; a failed read is an error.
- `test/data/services/row_data_source_server_sections_test.dart` (new, 3 tests): a `server` entry loads the server's row (items, server id, no paging); a server without the interface gives an empty row; the entry survives saving with its source and id.
- `server_silo`: 490/490; app analyzer: no new issues.

**Manual test plan**

1. **Settings → Home sections** with Silo active: the list has Silo's rows (Hidden Gems, Trending on Server, Seasonal Picks, Recently Added in Movies / TV Shows…), each off, subtitled "From your server". No Continue Watching or Next Up among them.
2. **Turn on Trending on Server**, go back to Home: the row shows Silo's cards in the order Silo's web home shows them; opening one opens the title.
3. **Rename or remove a row in Silo's web app** (if your Silo lets the profile customise Home), reopen Home settings: the title follows, a removed row disappears.
4. **Switch to Emby** with a Silo row on: Home settings lists no rows of Emby's own, and the Silo row adds nothing to Emby's Home (no empty row, no error).
5. **Emby unchanged**.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | server sections 4/4; row data source 3/3; `server_silo` 490/490; app analyzer: no new issues |

---

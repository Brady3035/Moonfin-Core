# Phase 5: Translation layer

[← Roadmap](../ROADMAP.md)

Pure functions that turn Silo JSON into the Jellyfin/Emby `BaseItemDto` shape the whole app reads. Each mapper is tested against a Silo fixture and diffed against the same title's Emby fixture. No UI changes.

**Phase done when:** Every fixture maps to a BaseItemDto whose fields match the Emby fixture for the keys `AggregatedItem` reads.

---

<a id="step-5-1"></a>
## 5.1 Time, ID and type helpers

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `7770ba5` | 4.10 |

**Goal.** Seconds ↔ ticks, opaque string IDs with synthetic `silo-genre:`/`silo-studio:` forms, and the Silo type → Jellyfin `Type`/`MediaType`/`IsFolder` table.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_ticks.dart`
- `packages/server_silo/lib/src/mappers/silo_ids.dart`
- `packages/server_silo/lib/src/mappers/silo_item_types.dart`
- `packages/server_silo/lib/server_silo.dart` (exports)

### How it works

Three small sets of pure functions that every later mapper uses. Nothing calls them yet.

**Time (`silo_ticks.dart`).** Jellyfin counts time in ticks of 100 ns (`RunTimeTicks`, `PlaybackPositionTicks`). Silo doesn't use a single unit:
- **seconds** for most fields (`versions[].duration`, markers, playback positions);
- **minutes** for an item's `runtime` (the xXx fixture says 124, while its file's `duration` is 7445 seconds);
- **milliseconds** in progress sync (`position_ms`).

So each helper names its unit (`secondsToTicks`, `minutesToTicks`, `millisecondsToTicks` and the reverse); there is no "Silo time" helper that guesses. The `…OrNull` forms take a raw JSON value and give null when it's missing. A `runtime` of 0 counts as unknown, which Jellyfin expresses by leaving `RunTimeTicks` out.

**IDs (`silo_ids.dart`).** Moonfin treats ids as opaque strings, so Silo's pass through unchanged: content ids like `movie-imdb-tt0295701`, and person and library ids, which `siloIdOf` turns into strings when Silo sends numbers. Genres and studios are different: Jellyfin gives them ids and Moonfin opens their pages by id, but Silo only names them. So Moonfin makes `silo-genre:<name>` and `silo-studio:<name>`, with the name percent-encoded so any character round-trips. The Silo client will turn these back into name filters (phase 6).

**Types (`silo_item_types.dart`).** Silo's `CatalogItem.type` is one of `movie, series, season, episode, audiobook, ebook, podcast, podcast_episode`. The table gives each the Jellyfin `Type`, `MediaType` and `IsFolder` that Emby sends for the same kind of item:

| Silo | Type | MediaType | IsFolder |
|---|---|---|---|
| movie | Movie | Video | false |
| series | Series | — | true |
| season | Season | — | true |
| episode | Episode | Video | false |
| audiobook | AudioBook | Audio | false |
| ebook | Book | Book | false |

Podcasts have no Jellyfin type and no Moonfin screen, so they don't map; mappers will skip them. This is logged as an open item.

**Reverse map for queries.** Moonfin asks for items in Jellyfin terms (`includeItemTypes=Movie,Series`, `mediaTypes=Audio`). `siloTypesForQuery` turns that into Silo types, with both parameters narrowing together as on Jellyfin, and limits the answer to the types Moonfin handles **today** (`siloSupportedTypes`: video). Audiobooks and ebooks join when phase 16 implements them, the same rule `FeatureDetector` follows. It answers:
- **null**: no type filter;
- **an empty set**: only types Silo can't serve here, such as music, playlists, channels, or audio before phase 16. The caller then returns an empty result **without a request**. This is the 4.2/4.3 requirement: dropping the filter instead would fill a "Continue listening" or "Albums" row with films;
- otherwise, the Silo types to ask for.

`siloCatalogScopeFor` picks the single `GET /catalog` `type` scope for a set (`movie`, `series`, `episode`, and `video` for movies with series), or null when one request can't cover it. Seasons are listed through their series.

**Correction found while building:** Silo does serve audiobooks and ebooks. 4.8's note said otherwise and is fixed.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_translation_helpers_test.dart` (new, 18 tests):
  - ticks: each unit converts and round-trips; the movie fixture's 124-minute runtime and 7445-second file agree within a minute; missing values give null;
  - ids: pass-through and numbers; genre and studio ids round-trip names with spaces, `&`, `:`, `/`, `%` and accents; the two kinds never mix up;
  - types: every mappable type maps; podcasts and unknown types don't; `MediaType`/`IsFolder` match the Emby fixtures; the Silo fixtures use only mappable types;
  - reverse map: no filter is null; music, playlist, channel and audio-only queries are empty; mixes keep what Silo has; types and media types narrow together; books open up when supported; catalog scopes.
- `server_silo`: 148/148.

**Manual test plan**

- Nothing to check by hand: no screen uses these yet (phase 5 is pure functions). The "types Silo lacks answer empty" check moves to 6.5's test plan, where queries first reach Silo.
- Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | new tests 18/18; `server_silo` 148/148; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-2"></a>
## 5.2 Image URL registry

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `cb59241` | 5.1 |

**Goal.** While mapping, record each artwork URL by item, image type and index, with a tag hashed from the URL **path** so the daily-rotating signature keeps the same tag. Relative URLs get the base URL; absolute (TMDB, TVDB, S3) pass through. Never append a token.

**Silo v2 endpoints**

- `GET /images/capabilities`

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_image_registry.dart` (new)
- `packages/server_silo/lib/src/api/silo_images_api.dart` (new)
- `packages/server_silo/lib/src/silo_media_server_client.dart` (`imagesApi`)
- `packages/server_silo/pubspec.yaml` (`crypto`, already used by the app)

### How it works

**Why a registry.** Jellyfin builds an image URL from an item id (`/Items/{id}/Images/Primary`), and Moonfin's `ImageApi` asks exactly that: "the primary image of item X". Silo has no such route. Every item it returns carries ready, signed URLs (`poster_url`, `backdrop_url`, `logo_url`, `still_url`, people's `photo_url`). So the Silo client remembers each URL as it maps an item, and answers `ImageApi` from memory.

**`SiloImageRegistry`:**
- `register(itemId, type, url, index:)` stores the URL under (item, `SiloImageType`, index) and returns its **tag**, which the mappers (5.3 onwards) will put in `ImageTags`/`BackdropImageTags`. A newer URL for the same image replaces the older one, so the signature stays fresh.
- `urlFor` / `tagFor` answer by the same key; `ImageApi` will use them in 6.1. An id that was never registered answers null. What to do then (cold start, deep links) is D2, for 6.3.
- `clear()` for a sign-out or another server.
- `SiloImageType` names the Jellyfin image types (`Primary`, `Backdrop`, `Logo`, `Banner`, `Thumb`, `Art`, `Disc`). Primary comes from `poster_url`, `still_url` or `photo_url` depending on the item.

**Tags (`siloImageTag`).** Silo signs artwork URLs with a query that rotates daily (`?exp=…&sig=…`), while the path names the picture itself and carries a content hash (`poster/w500.f6c3….webp`). The tag is the first 16 hex digits of the SHA-1 of the **path**, so:
- the same picture keeps the same tag every day, and image caches keyed by tag stay valid;
- a changed picture gets a new tag;
- the tag is taken from the URL **as Silo sent it**, before the server address is added, so the same poster reached over a LAN address and a public address shares one tag (a test caught this while building).

**URLs (`resolveSiloImageUrl`).** Server paths (`/api/v2/artwork/…`) get the base URL in front, keeping any reverse-proxy sub-path. Absolute URLs (TMDB, TVDB, an S3 bucket) pass through, and `//host/…` takes the base URL's scheme. **No token is ever appended**: the URLs are already signed, and a token in an image URL would leak the session into caches and logs.

**Sizes (`SiloImagesApi`, `SiloImageCapabilities`).** A registered URL is fixed at one size, so `ImageApi`'s `maxWidth` can't resize it afterwards. Silo picks the size per **request**: item-returning calls take `image_size` (`small`, `medium`, `large`, `original`), and `GET /images/capabilities` gives each bucket's width per artwork kind (poster 300/500/780, backdrop 300/1920/1920…). `sizeFor(kind, width)` picks the smallest bucket at least that wide, `original` when none is, and `medium` when no width is given. Later steps use it to choose `image_size` per screen (grid vs hero).

Nothing calls the registry yet; 5.3's item mapper is the first.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_image_registry_test.dart` (new, 20 tests):
  - tags: same across rotating signatures, different for a different picture, independent of the server address;
  - URLs: base URL and proxy sub-path added, absolute and `//` URLs passed through, never a token;
  - registry: per item, type and index, a fresher signature replaces the URL and keeps the tag, empty URLs ignored, every artwork URL in the movie fixture registers;
  - sizes: the capability fixture parses; bucket choice for posters, backdrops and logos; `original` when wider; `medium` by default; fetched from `GET /images/capabilities`.
- `server_silo`: 168/168.

**Manual test plan**

- Nothing to check by hand: no screen uses the registry until 6.1. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | new tests 20/20; `server_silo` 168/168; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-3"></a>
## 5.3 Item mapper: core fields

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `4759d72` | 5.2 |

**Goal.** Id, Name, SortName, Type, Overview, Genres, Studios, years and dates, OfficialRating, Community/Critic rating, RunTimeTicks, ProviderIds, DateCreated, Status; `backdrop_urls` → every `BackdropImageTags` entry; original payload kept under `_silo`.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart` (new)

### How it works

`siloItemToBaseItemDto(item, images:)` turns one Silo `CatalogItem` (a list entry or a detail answer) into the Jellyfin `BaseItemDto` map Moonfin reads. It is a pure function. Later steps add series links (5.4), user data (5.5), people (5.6) and media sources (5.8) to the same map.

| Jellyfin | From Silo | Notes |
|---|---|---|
| `Id` | `content_id` | Unchanged (5.1). |
| `Name`, `SortName` | `title` | Silo has no sort title; Jellyfin also falls back to the name. |
| `OriginalTitle`, `Overview` | `original_title`, `overview` | |
| `Taglines` | `tagline` | As a one-element list, or empty. |
| `Type`, `MediaType`, `IsFolder` | `type` | The 5.1 table. |
| `Genres`, `GenreItems` | `genres` | `GenreItems` carry synthetic ids (`silo-genre:Action`). |
| `Studios` | `networks` then `studios` | Emby lists a series' networks among its studios, so the mapper does too, without repeats. Ids are synthetic (`silo-studio:…`). |
| `ProductionYear` | `year` | Else the year of the date below (episodes have no `year`). |
| `PremiereDate` | `release_date`, `first_air_date` or `air_date` | Silo sends a calendar date; written as midnight UTC in Jellyfin's format. |
| `Status`, `EndDate` | `show_status`, `last_air_date` | `ended`/`canceled` → `Ended` (with `EndDate`), returning/in production → `Continuing`, anything else left out. |
| `OfficialRating` | `content_rating` | |
| `CommunityRating` | `rating_tmdb` | Out of 10, one decimal. |
| `CriticRating` | `ratings[]` with source `rt_critic` | Only when a metadata plugin provides one, rounded to a whole percent. |
| `RunTimeTicks` | first `versions[].duration` (s), else `runtime` (min) | The file's exact length, as Emby reports; `runtime: 0` means unknown. |
| `ProviderIds` | `imdb_id`, `tmdb_id`, `tvdb_id` | `Imdb`, `Tmdb`, `Tvdb`. |
| `DateCreated` | earliest `versions[].added_at` | Silo dates the files, not the item. |
| `ImageTags`, `BackdropImageTags` | `poster_url`, `logo_url`, `backdrop_urls` (or `backdrop_url`) | Each URL is registered in the 5.2 registry and its tag goes here; every backdrop gets its own index. |
| `PrimaryImageAspectRatio` | | 2/3 when there is a poster; 16/9 for an episode's still (since 5.4). |
| `_silo` | the whole item | For later steps and debugging. |

Without a registry the item has no image tags. A type with no Jellyfin equivalent (podcasts) or an item without an id gives null, and the caller drops it.

**Left for other steps:** series/season/episode links and parent artwork (5.4), `UserData` (5.5), `People` (5.6), `MediaSources`/`MediaStreams` (5.8), chapters (5.9), trailers. `ProductionLocations` isn't mapped: Silo sends country codes (`US`), Emby full names, and nothing on the roadmap shows them yet.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_item_mapper_test.dart` (new, 19 tests). These are golden comparisons against the **same titles on Brady's Emby server**:
  - **xXx (movie):** name, sort and original title, type, overview, tagline, rating, provider ids, year, premiere day, run time within a second of Emby's, the same number of backdrops, primary and logo registered (URL and tag agree), the Silo item kept;
  - **Young Justice (series):** name, type, year, status `Ended`, premiere and end day, rating, networks and studios;
  - **episode 1x01:** name, type, year, air day, run time.
  - The servers take metadata from different sources, so genres and studios are compared as "everything Emby has is there": Silo adds Drama to xXx and DC to Young Justice.
  - Edge cases: podcasts and items without an id are dropped; a bare list entry maps with what it has; no registry means no tags; a `rt_critic` score; the series status words.
- `server_silo`: 187/187.

**Manual test plan**

- Nothing to check by hand: no screen uses the mapper until phase 6. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | new tests 19/19; `server_silo` 187/187; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-4"></a>
## 5.4 Item mapper: series, seasons and episodes

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `d392f0b` | 5.3 |

**Goal.** SeriesId/Name, SeasonId (both id forms), Index numbers, ChildCount, and the Parent*/Series* image fields filled from the series' slots. Since build `4b2e921c` movie and series detail carry `thumb_url` and `banner_url` (when `images/capabilities.extended_item_artwork` is true): use them, and fall back to the backdrop only when they're missing. Use `*_is_episode_still` so an episode still never becomes a series poster.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart`
- `packages/server_silo/lib/src/mappers/silo_ids.dart`

### How it works

**List entries.** Silo lists a series' seasons (`series_seasons`) and a season's episodes (`season_episodes`) without a `type` and without repeating the series in each entry. So `siloItemToBaseItemDto` takes an optional `type`, falls back to the id's prefix (`season-…`, `episode-…`: `siloTypeOfId`), and takes the series from a `SiloSeriesRef(id, name)` when the entry doesn't say.

**Season ids, both forms.** Silo names seasons after their series: `series-imdb-tt1641384` has `season-imdb-tt1641384-1`, `-2`… An episode's detail carries `series_id` and `season_number` but no season id:
- `siloSeasonId(seriesId, n)` builds the id, to fill `SeasonId`;
- `parseSiloSeasonId` reads it back into series and number, which phase 6 needs when Moonfin asks for a season's episodes by `SeasonId`.

**Fields:**

| | Series | Season | Episode |
|---|---|---|---|
| `IndexNumber` | | `season_number` | `episode_number` |
| `ParentIndexNumber` | | | `season_number` |
| `ChildCount` | `season_count` | `episode_count` | |
| `SeriesId`, `SeriesName` | | series | `series_id`, `series_title` (or the ref) |
| `SeasonId`, `SeasonName` | | | built id; `Season N`, or `Specials` for season 0 |
| `ParentId` | | the series | the season |
| `SeriesPrimaryImageTag`, `ParentLogo*`, `ParentThumb*` / `SeriesThumbImageTag`, `ParentBackdrop*` | | from the series | from the series |

**Parent artwork comes from the registry.** Jellyfin repeats the series' artwork tags on every season and episode. Rather than needing the series alongside each child, the mapper reads what the 5.2 registry holds for the series id. Moonfin opens a series before its seasons and episodes, so it's there; when it isn't, the fields are simply absent, as on a Jellyfin item without that artwork.

**Episode artwork rules (`*_is_episode_still`):**
- The episode's own image is its still: `still_url` in a season list, or `poster_url` when `poster_is_episode_still` is true. A `poster_url` that is really the series' poster (`false`) is **never** the episode's image. It goes to the series slot, and the episode points at it through `SeriesPrimaryImageTag`.
- An episode's `backdrop_url` is normally the series' backdrop (`backdrop_is_episode_still: false`). It goes to the series too, and the episode has no backdrop of its own, matching Emby.
- Borrowed artwork only fills an **empty** series slot; it never replaces the series' own.
- An episode still is 16:9 (`PrimaryImageAspectRatio`), as Emby reports.

**Thumb and banner.** Movies and series take `thumb_url` and `banner_url` when Silo sends them (`extended_item_artwork`). Without a thumb, the first backdrop stands in as the landscape image Moonfin's thumb cards use. There is no fallback for a missing banner.

### Testing

**Automated tests** (`packages/server_silo/test/silo_item_mapper_test.dart`, 11 new and 1 updated, 30 in all)

- Golden against **Young Justice on Brady's Emby server**, with the series mapped first:
  - the series counts 4 seasons, as on Emby; its thumb is its first backdrop;
  - the season list: names, numbers, ids, 26 episodes in season 1, series links, and the **same set** of parent artwork fields Emby fills, with values equal to the series' own tags;
  - the episode detail: index, season index, series and season names match Emby; series and season ids; the same parent artwork fields as Emby; its image is the still, and its backdrop stays with the series (no own backdrop, like Emby);
  - the season's episode list: all 26 titles and numbers match Emby, in order.
- Artwork rules: a series poster sent with an episode goes to the series and never becomes the episode's image; borrowed artwork never replaces the series' own; season 0 is Specials.
- Season ids: built and parsed back (including season 0 and `tmdb` keys); non-season ids rejected; type from the id prefix.
- Updated from 5.3: an episode still now has a 16:9 aspect ratio, matching Emby.
- `server_silo`: 198/198.

**Manual test plan**

- Nothing to check by hand until phase 6 shows series and episodes. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | mapper tests 30/30; `server_silo` 198/198; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-5"></a>
## 5.5 Item mapper: user data

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `05c2935` | 5.4 |

**Goal.** Favorite, Played, PlaybackPositionTicks, PlayedPercentage, UnplayedItemCount, PlayCount, LastPlayedDate. A missing `user_data` means unplayed at 0.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart`

### How it works

Silo keeps the viewer's state in two places, and the mapper merges them into Jellyfin's `UserData`:

- `user_state`, on every catalog item: `played`, `is_favorite`, `in_watchlist` (Jellyfin has no watchlist field; phase 9 decides what to do with it);
- `user_data` (`WatchUserData`), on series, seasons and watch answers: `position_seconds`, `duration_seconds`, `is_in_progress`, `unplayed_count`, `watched_count`, `played`.

| Jellyfin | From | Notes |
|---|---|---|
| `Played` | `user_state.played` or `user_data.played` | |
| `IsFavorite` | `user_state.is_favorite` | |
| `PlaybackPositionTicks` | `user_data.position_seconds` | 0 when played, or nothing is said. |
| `PlayedPercentage` | position ÷ `duration_seconds` | Only with a position and a length; capped at 100. |
| `PlayCount` | `played` | 1 or 0: Silo knows *whether* it was watched, not how often. |
| `UnplayedItemCount` | `user_data.unplayed_count` | Series and seasons only, as on Emby. |
| `LastPlayedDate` | `progress_updated_at` | When Silo sends it. |

Whatever neither part says means **unplayed at position 0**: exactly the `UserData` Emby sends for an untouched item.

**Progress list entries.** Silo's Continue watching list (`GET /progress`) returns `ProgressEntry` items (`media_item_id`, `position_seconds`, `duration_seconds`, `completed`, `updated_at`), not catalog items. `siloProgressToUserData(entry)` turns one into `UserData` the same way, so the Continue watching rows (phase 8) can merge it into the items they show. A completed entry is played, at position 0.

### Testing

**Automated tests** (`packages/server_silo/test/silo_item_mapper_test.dart`, 9 new, 39 in all)

- Golden against **Brady's Emby server**: `UserData` is **identical** to Emby's for xXx, Young Justice (98 unplayed), episode 1x01, season 1 from the series list (26 unplayed) and episode 1 from the season list.
- Rules: nothing said is unplayed at 0; played and favourite from `user_state`; a resume position with its percentage and last-played date; a played item has no resume position; unplayed counts only on series and seasons.
- Progress list: the first real entry of the in-progress fixture (582 s of 2832 s, 20.6%); a completed entry is played at 0.
- `server_silo`: 207/207.

**Manual test plan**

- Nothing to check by hand until phase 6 shows items (watched ticks, favourites) and phase 8 the Continue watching row. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | mapper tests 39/39; `server_silo` 207/207; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-6"></a>
## 5.6 Item mapper: people

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 5.5 |

**Goal.** Cast and crew to `People` with roles and photo tags through the registry.

**Where in Moonfin**

- `silo_item_mapper.dart`

### How it works

Silo sends `cast` (`CastCredit`: `name`, `character`, `order`, `person_id`, `photo_url`) and `crew` (`CrewCredit`: `name`, `job`, `person_id`, `photo_url`) on item details. The mapper turns them into Jellyfin's `People` list, which Moonfin's cast row and person links read:

| Jellyfin | From | Notes |
|---|---|---|
| `Name` | `name` | |
| `Id` | `person_id` | Opens the person page (phase 6). |
| `Role` | cast: `character`; crew: `job` | A crew role is left out when it only repeats the type ("Director"), as on Emby. |
| `Type` | cast: `Actor`; crew: by job | See below. |
| `PrimaryImageTag` | `photo_url` | Registered under the person's id as `Primary`, so `ImageApi` serves it. |

**Order.** Cast first, in billing order (`order`; ties keep Silo's order, unnumbered last), then crew grouped by type: Creator, Director, Writer, Producer, Composer, Editor.

**Crew jobs.** Matched case-insensitively:

- Director: director, co-director.
- Writer: writer, screenplay, story, teleplay, novel, author, characters.
- Producer: producer, executive / co- / co-executive / associate producer.
- Composer: composer, original music composer, music.
- Jobs that fit none (gaffer, casting…) are left out rather than shown under a type Moonfin can't name.

**Duplicates.** A person credited twice with the same type (producer and executive producer) appears once; one who both writes and directs appears under each.

**Episodes.** Silo has no guest-star flag, so an episode's cast is the series regulars, all `Actor`s. Emby lists guest stars as `GuestStar`; Moonfin shows both in the same row, so only the guest names are missing.

### Testing

**Automated tests** (`packages/server_silo/test/silo_item_mapper_test.dart`, 8 new, 47 in all)

- Golden against **Brady's Emby server** (xXx): the lead is Vin Diesel as Xander Cage on both. All 20 Silo actors are in Emby's 66, with the same characters. The director, Rob Cohen, matches, with no `Role`.
- Crew comes after the cast, grouped by type; every photo is in the registry, and its tag is the entry's `PrimaryImageTag`.
- Episode 1x01 of Young Justice: 21 actors and 2 creators.
- Rules: billing order with stable ties and unnumbered entries last; job mapping and unknown jobs left out; dedupe by person and type; no people is an empty list; without a registry there are no tags.
- `server_silo`: 215/215.

**Manual test plan**

- Nothing to check by hand until phase 6 shows the cast row and person pages. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | mapper tests 47/47; `server_silo` 215/215; analyzer: no issues |
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

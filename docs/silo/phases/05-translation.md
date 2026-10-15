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
| ☑ Done | `1bacabf` | 5.5 |

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
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-7"></a>
## 5.7 Library mapper

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `326105b` | 5.6 |

**Goal.** User libraries to `CollectionFolder` with `CollectionType` (movies, tvshows, books, mixed).

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_library_mapper.dart` (new)

### How it works

Silo lists the profile's libraries with `GET /user/libraries`. Each entry is a `UserLibrary`: `id`, `name`, `type`, `sort_order` and a signed `poster_url`. `siloLibraryToCollectionFolder` turns one into the `CollectionFolder` Moonfin reads from `getUserViews` (wired in 6.4):

| Jellyfin | From | Notes |
|---|---|---|
| `Id` | `id` | Unchanged: library order and hidden libraries are stored in Silo's settings by this id (2.7). |
| `Name`, `SortName` | `name` | |
| `Type`, `IsFolder` | — | `CollectionFolder`, true. |
| `CollectionType` | `type` | See below. |
| `ImageTags.Primary` | `poster_url` | Registered under the library id. |
| `UserData` | — | Unplayed, not a favourite: the same empty `UserData` Emby sends. |

**Collection types.** Moonfin picks the screen a library opens in, and its icon, from `CollectionType`:

| Silo `type` | `CollectionType` | Opens in |
|---|---|---|
| `movies` | `movies` | library grid |
| `series` | `tvshows` | library grid |
| `mixed` | none, as on Jellyfin | library grid |
| `audiobooks` | `audiobooks` | book screens |
| `ebooks` | `books` | book screens |
| `podcasts`, `manga` | no entry | — |

Audiobooks keep their own type, as on Emby, rather than `books` as the design notes said: Moonfin's book screens tell an audiobook library from an ebook one by it.

**Which libraries show.** `siloLibrariesToUserViews` maps the whole list. It keeps only types Moonfin can open today: movies, series and mixed. Book libraries join when the optional books phase (16) can open their items. Until then they would open onto an empty grid. Podcasts and manga have no Moonfin screen (open item). The list is ordered by `sort_order`; equal or missing positions keep Silo's order, unnumbered ones last.

**Known limits.**

- A library poster's path has no content hash (`library-posters/1.png`), so its tag doesn't change when an admin uploads a new poster. Moonfin may show the old one until its image cache expires (open item).
- Moonfin treats a library with no collection type and a name like "Games" as a games library. A Silo mixed library named that way would open the games browser. Checked in 6.4.

### Testing

**Automated tests** (`packages/server_silo/test/silo_library_mapper_test.dart`, new, 14 tests)

- Golden against **Brady's Emby server**: Movies and TV Shows come out in order with Emby's collection types (`movies`, `tvshows`). `Type`, `IsFolder` and `UserData` are identical to Emby's. Each poster is registered under its library.
- Collection types for every Silo type; mixed has none; podcasts, manga and unknown types don't map; a numeric id becomes a string; no poster gives no tag.
- User views: only openable types are kept (books once supported); `sort_order` with stable ties and unnumbered entries last; junk entries are skipped.
- `server_silo`: 229/229.

**Manual test plan**

- Nothing to check by hand until 6.4 shows the libraries. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | library mapper tests 14/14; `server_silo` 229/229; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-8"></a>
## 5.8 Versions and streams → MediaSources/MediaStreams

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `f2be8d0` | 5.7 |

**Goal.** One MediaSource per file version. Build Jellyfin's single stream index space and store the map `index → {kind, ordinal, track_id}` (subtitles keep the container index; video then audio take the lowest free indices). HDR/DV range types.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_media_source_mapper.dart` (new)
- `packages/server_silo/lib/src/mappers/silo_languages.dart` (new): English language names for stream titles.
- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart`: items get `MediaSources` and `MediaStreams`.

### How it works

Silo describes each file of a movie or episode as a **version** (`FileVersion`): `file_id`, container, size, bitrate in kbps, duration in seconds, and its `video_tracks`, `audio_tracks` and `subtitle_tracks`. Item details and `/watch` answers carry the full versions. Season lists carry a lightweight `files[]` per episode. Moonfin reads Jellyfin's `MediaSources`, each with `MediaStreams`.

**Sources.** `siloItemMediaSources(item)` makes one `MediaSource` per version:

| Jellyfin | From | Notes |
|---|---|---|
| `Id` | `file_id` | What Moonfin sends back as `mediaSourceId`. |
| `ItemId` | the item's id | |
| `Name` | file name without extension | What Emby and Jellyfin show in the version picker. Without a file name: edition and quality ("Extended 2160p HEVC DOVI"). |
| `Path` | `file_path` | Only for viewers Silo shows paths to. |
| `Container`, `Size` | `container`, `file_size` | |
| `Bitrate` | `bitrate` × 1000 | Silo sends kbps. |
| `RunTimeTicks` | `duration` or `duration_seconds` | Detail and `/watch` name it differently. |
| `Type` | — | `Default` for the first, `Grouping` for the rest, as on Emby. |
| `SupportsDirectPlay/DirectStream/Transcoding` | — | All true: Silo decides delivery when playback starts (phase 7). |
| `DefaultAudioStreamIndex` | `effective_audio_track_index` | Else the track flagged default, else the first. |
| `DefaultSubtitleStreamIndex` | the subtitle flagged default | Absent when none is. |

The **default version comes first**: the first playback variant's `default_file_id`, which is what Silo's own player picks (the 4K file of The Salt Path). The item also gets the default version's streams as its own `MediaStreams`, as Jellyfin sends them. Series and items without files get neither field.

**One index space.** Jellyfin numbers all of a file's streams in one list. Moonfin's track pickers and players work in that number. Silo numbers each kind on its own, and only subtitles carry the container index (`index` 2, 3…). So:

1. Subtitles keep Silo's `index`.
2. Video tracks, then audio tracks, take the lowest indices left (xXx: video 0, audio 1, subtitles 2 and 3).
3. A subtitle with no index, or one already used, takes the next free index after them.

Within each kind the order is Silo's, so the player's per-kind track numbers stay right. Emby numbers in container order (xXx has audio 0, video 1), so the golden tests compare streams by type, not by index.

**Track map.** Each source keeps under `_siloTracks` which Silo track every index stands for: kind, ordinal within its kind, and a subtitle's container index. `siloTrackForStreamIndex(source, index)` gives it back, and `siloStreamIndexForTrack(source, kind, ordinal)` goes the other way. The resolver (phase 7) uses these to send `audio_track_index` and the subtitle ordinal, and to read back `selected_tracks`. The plan's `file:<id>:subtitle:<n>` ids are built there from the ordinal.

**Streams.**

- **Video:** codec, profile, level, size, aspect ratio, interlacing, frame rate (also `24000/1001` fractions), bit depth, pixel format, colour fields, Dolby Vision profile, level and compatibility, and bitrate (the file's when the track has none).
- **Audio:** codec, profile, language, channels, `ChannelLayout` ("5.1(side)" → "5.1"; from the channel count without a layout), bitrate, sample rate.
- **Subtitles:** codec, language, forced, hearing-impaired, default, external. `IsTextSubtitleStream` and `SupportsExternalStream` are false for image codecs (PGS, DVD, DVB).
- **Titles:** `Title` is the track's own embedded title only. Silo's `title` falls back to ffprobe's codec name ("DCA (DTS Coherent Acoustics)") or the subtitle file name, which Emby doesn't show either.
- **Display titles:** `DisplayTitle` follows Emby, so the pickers read the same: "English DTS 5.1 (Default)", "English (Forced SRT)", "English (SDH PGSSUB)", "4K HDR10 HEVC". A subtitle title that only repeats the language ("English (CC)") is left out, as Emby does. Language names come from a small table of common languages; other codes show in upper case.
- **Delivery:** `DeliveryMethod` and `DeliveryUrl` are not set here. They come from the playback plan (phase 7).

**HDR.** `VideoRangeType` uses Jellyfin's names (`SDR`, `HDR10`, `HDR10Plus`, `HLG`, `DOVI`, `DOVIWithHDR10`…), which Moonfin's HDR badge reads. Silo usually sends `video_range_type`; it is matched without regard to case or separators (`hdr10_plus`, `HDR10+`). Without it, the type is worked out as Jellyfin does:

1. Dolby Vision from its profile and base-layer compatibility (1 or 6 → with HDR10, 2 → with SDR, 4 → with HLG).
2. Otherwise `hdr10_plus` gives HDR10+.
3. Otherwise the transfer function: PQ (`smpte2084`) is HDR10, `arib-std-b67` is HLG, anything else SDR.

`VideoRange` is Silo's `video_range`, or `SDR`/`HDR` from the type.

**Season list files.** A lightweight file has a resolution, codec, HDR flag and audio channel count. It becomes a source with a video stream at the resolution's nominal 16:9 size (1080p → 1920×1080, what the resolution badge reads) and an audio stream with its channels. Its track map is empty, so playback loads the full version first.

**Known limits.**

- Multi-part (`presentation_part_*`) and multi-episode files are listed as ordinary single sources for now. The fields stay in the version kept under `_silo`.
- Emby marks a subtitle titled "SDH" as hearing-impaired; Silo marks it only if the file says so. The mapper keeps Silo's flag.
- Languages stay as Silo sends them (`en`, `ro`). Moonfin's language matching already accepts two- and three-letter codes.

### Testing

**Automated tests** (`packages/server_silo/test/silo_media_source_mapper_test.dart`, new, 28 tests)

- Golden against **Brady's Emby server**, xXx:
  - name, path, size, container and flags are identical; bitrate and run time match to Silo's whole kbps and seconds;
  - video, audio and subtitle streams match field by field, including Emby's display titles;
  - indices are video 0, audio 1, subtitles 2 and 3, and the default audio index points at the audio stream;
  - the track map goes both ways.
- Golden, The Salt Path (two versions): the 4K default comes first. Each version matches the same file on Emby (Emby has a third WEB-DL file). HDR10 on 4K, SDR on 1080p; PGS is an image subtitle.
- Golden, Young Justice 1x01: from `/watch`, the same indices and streams as Emby. From the season list, the badge fields match Emby's (1920×1080, HEVC).
- Index space: gaps around subtitle indices; missing or repeated subtitle indices; default audio and subtitle rules.
- Video range: Silo's spellings, derivation (DV with HDR10 or HLG, HDR10+, PQ, HLG, SDR), frame-rate fractions.
- Labels: channel layouts, audio titles, language names, version names without a file name.
- Items: a series and an item without versions get no `MediaSources`.
- `server_silo`: 257/257.

**Manual test plan**

- Nothing to check by hand until 6.6 shows the detail page (version picker, quality badges, audio and subtitle lists) and phase 7 plays. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | media source tests 28/28; `server_silo` 257/257; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-9"></a>
## 5.9 Chapters mapper

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `b79ce1f` | 5.8 |

**Goal.** Version chapters → `Chapters` (StartPositionTicks, Name, image tag when a thumbnail exists).

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_chapter_mapper.dart` (new)
- `silo_item_mapper.dart`: items get `Chapters`.
- `silo_image_registry.dart`: a `chapter` image type.

### How it works

Each Silo version lists its chapters (`VersionChapter`: `index`, `title`, `start_seconds`, `end_seconds`, `thumbnail_url`). `siloChaptersToJellyfin(version)` turns them into Jellyfin's `Chapters`, which Moonfin's chapter row and the player's chapter list read:

| Jellyfin | From | Notes |
|---|---|---|
| `StartPositionTicks` | `start_seconds` | Negative starts become 0. |
| `Name` | `title` | The file's own names ("01", "Chapter 1"). Left out when empty; Moonfin then shows "Chapter n". |
| `ImageTag` | `thumbnail_url` | See below. |
| `MarkerType`, `ChapterIndex` | — | `Chapter`, and the place in the list, as Emby sends them. |

- **Order:** chapters are listed in start order; chapters that start together keep Silo's order. Entries without a start are skipped.
- **Which chapters:** the item gets the **default version's** chapters, as Jellyfin does. Season list entries get no `Chapters` field, because their lightweight files don't say. An item whose version simply has no chapters gets an empty list.
- **Thumbnails:** a new image type `SiloImageType.chapter` records them in the image registry under the item id, at the chapter's place in the list. That place is the `index` Moonfin passes to `getChapterImageUrl`, which `SiloImageApi` will answer from the registry (6.1). The path carries a content hash, so the tag stays the same while the picture does.
- **Markers:** Emby also lists intro markers among the chapters ("Intro Start", "Intro End"). Silo keeps them apart as marker segments, and Moonfin reads those as media segments (5.10). So only real chapters are listed.

### Testing

**Automated tests** (`packages/server_silo/test/silo_chapter_mapper_test.dart`, new, 10 tests)

- Golden against **Brady's Emby server**:
  - xXx: 16 chapters at exactly Emby's start times and indices.
  - Young Justice 1x01: the same 6 names and times as Emby's real chapters, without Emby's two intro marks.
  - `/watch` answers too.
- Thumbnails: each chapter's tag is the registered one; 16 different tags; no thumbnail or no registry gives no tag.
- Rules: start order with stable ties, skipped entries, empty names, negative starts, the default version's chapters (The Salt Path's 4K default has none), and no field on season list entries.
- `server_silo`: 267/267.

**Manual test plan**

- Nothing to check by hand until 6.6 shows the chapter row. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | chapter tests 10/10; `server_silo` 267/267; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-10"></a>
## 5.10 Markers mapper

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `0604c44` | 5.9 |

**Goal.** Marker segments → `MediaSegmentDto[]` (intro, credits→Outro, recap, preview), every occurrence.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_marker_mapper.dart` (new)

### How it works

Silo detects or imports **markers** per file: intro, credits, recap and preview. Moonfin's skip button and segment actions (`MediaSegmentService`) read Jellyfin's media segments from `ItemsApi.getMediaSegments`: `{Id, ItemId, Type, StartTicks, EndTicks}`. `siloMarkersToMediaSegments(markers, itemId:)` makes those. It accepts anything that carries one file's markers: the `FileMarkers` answer of `GET /markers/files/{id}` or `/markers/items/{id}`, or a version from `/watch` or an item detail.

| Silo kind | Jellyfin `Type` |
|---|---|
| `intro` | `Intro` |
| `credits` | `Outro` |
| `recap` | `Recap` |
| `preview` | `Preview` |

**Every occurrence.** `marker_segments` lists all of them in time order. An episode can have a recap, an intro, and a second intro after a cold open. It is used whenever Silo sends it. Older answers and catalog versions only have one segment per kind (`intro`, `credits`…), either as `MarkerSegment` (`start_seconds`/`end_seconds`) or `Marker` (`start`/`end`); those are the fallback.

**Rules.**

- **Missing end:** a segment without an end runs to the end of the file when the caller passes its length (Silo defaults credits and previews to the end). Otherwise it is dropped rather than guessed.
- **Dropped:** empty, inverted, repeated and unknown segments.
- **Clamped:** a negative start begins at 0.
- **Order:** segments are sorted by start.
- **Ids:** each occurrence gets its own `Id` (`silo-intro-<item>-0`, `-1`…), because Moonfin tells segments apart by id when deciding whether it already skipped one.

**Not switched on yet.** `FeatureDetector.supportsSkipSegments` and `supportsMediaSegments` stay off for Silo until 11.1 wires `getMediaSegments` to Silo's markers (phase 1 rule: a flag turns on with the step that makes it work).

### Testing

**Automated tests** (`packages/server_silo/test/silo_marker_mapper_test.dart`, new, 8 tests)

- Golden:
  - Young Justice 1x01 (`markers_episode.json`) gives one intro at 248.0–268.3 s. Emby marks the same intro with chapter markers, and its detector lands within 2 seconds of Silo's.
  - The `/watch` version gives the same.
  - xXx has no markers.
- Rules: every occurrence in start order with distinct ids; the single fields as fallback (both shapes); a missing end with and without the run time; empty, inverted, repeated and unknown segments dropped; negative starts.
- `server_silo`: 275/275.

**Manual test plan**

- Nothing to check by hand until 11.1 shows the skip-intro button. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | marker tests 8/8; `server_silo` 275/275; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-5-11"></a>
## 5.11 Trickplay mapper

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `b07903c`, fixture `c7aa25b` | 5.10 |

**Goal.** `/watch/{id}/trickplay` → Jellyfin `Trickplay` map, registering sheet URLs for `getTrickplayTileImageUrl`.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_trickplay_mapper.dart` (new)
- `silo_image_registry.dart`: a `trickplay` image type.
- `packages/server_silo/test/fixtures/silo/watch_trickplay_episode.json` (new, written by hand; replaced by a real capture on 2026-10-15, see below).

### How it works

Silo makes seek-bar previews per file. Version entries say whether a file has them (`trickplay_available` on `/watch`), and `GET /watch/{id}/trickplay` returns them (`WatchTrickplay`):

- `thumbnail_width`, `thumbnail_height` in pixels;
- `tile_columns` × `tile_rows` thumbnails per sheet;
- `interval_ms` per thumbnail, and `thumbnail_count`;
- `sheets[]` with signed JPEG URLs that expire at `expires_at`.

Moonfin reads Jellyfin's `Trickplay` item field, `{ <media source id>: { "<width>": {…} } }`, into `TrickplayInfo`, and asks `ImageApi.getTrickplayTileImageUrl(itemId, width:, index:, mediaSourceId:)` for each sheet. `siloTrickplayToJellyfin(answer)` produces that field:

| Jellyfin | From |
|---|---|
| outer key | `file_id` (the `MediaSource` id, 5.8) |
| inner key | `thumbnail_width` (Silo serves one width per file) |
| `Width`, `Height` | `thumbnail_width`, `thumbnail_height` |
| `TileWidth`, `TileHeight` | `tile_columns`, `tile_rows` |
| `Interval` | `interval_ms` |
| `ThumbnailCount` | `thumbnail_count`, else every tile of every sheet |
| `Bandwidth` | 0 (Silo gives no estimate) |
| `SiloExpiresAt` | `expires_at` (Moonfin's reader ignores unknown keys) |

**Layout.** Both servers lay thumbnails out the same way. Sheet *s* holds thumbnails *s × columns × rows* onward, left to right and top to bottom. So Moonfin's tile arithmetic works unchanged.

**Sheet URLs.** Each sheet's URL is recorded in the image registry under the **file id**, as a new `SiloImageType.trickplay`, at its sheet index. `getTrickplayTileImageUrl` will answer from there (11.2). The URLs carry their own authorization and expire, so 11.2 reads the previews again after `SiloExpiresAt`; a fresher URL replaces the old one.

**Answers it can't use.** Null without a file id, a size, a grid, an interval or sheets.

**Not switched on yet.** `supportsTrickplay` stays off for Silo until 11.2 fetches the previews and merges this field into the item.

**Sample.** No file on the test server had seek previews when this step was built, so `watch_trickplay_episode.json` was written from the schema. Brady's probe run on 2026-10-15 (Silo `bd9d59ea`) captured a real one for Young Justice S01E01, which replaced it: 300 × 168 thumbnails, 10 × 8 per sheet, 136 thumbnails on two sheets. The tests read their expectations from the file and pass unchanged. One difference from the guess: real sheet URLs live under `/api/v2/artwork/trickplay/`, so the image cache keys them by path like other signed artwork (6.2), which 11.2 relies on.

### Testing

**Automated tests** (`packages/server_silo/test/silo_trickplay_mapper_test.dart`, new, 9 tests)

- Episode sample: keyed by file id then width; the entry has exactly the fields `TrickplayInfo` reads; every sheet is registered under the file id; Jellyfin's tile arithmetic puts the last thumbnail on the last sheet.
- Rules: incomplete answers give null; a numeric file id; the count fallback; sheets without an index; fresh URLs replace old ones.
- `server_silo`: 284/284.

**Manual test plan**

- Nothing to check by hand until 11.2 shows seek previews. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | trickplay tests 9/9; `server_silo` 284/284; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | real capture (`bd9d59ea`): trickplay tests 9/9 unchanged; `server_silo` 449/449 |
| | | | | |

---

<a id="step-5-12"></a>
## 5.12 Cursor pager

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `d53c6c6`, fix `8eb8242` | 5.11 |

**Goal.** Turn Moonfin's `startIndex/limit` into Silo cursors: first page plain; next page `next_cursor`; any other offset `window_cursor + seek`; `invalid_cursor` → reset once.

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_pager.dart` (new)

### How it works

**The mismatch.** Moonfin pages by offset: `getItems(startIndex: 150, limit: 50)`. Silo has no offset. Each list answer (`CatalogBrowseCollection` and its kin) carries:

- `page.next_cursor` and `page.has_more`, for the page after it;
- `window_cursor`, which, sent back with `seek=<offset>`, jumps anywhere in the same result;
- `total` (an estimate unless `total_exact`).

`limit` is at most 200.

**Cursors are bound to `limit`.** Silo signs each cursor over the whole query, `limit` included (server `listCatalogItems`: the cursor scope's filter carries `limit`). A `next_cursor` or `window_cursor` is only accepted with the **same** `limit` as the request that issued it; any other gets `invalid_cursor` ("belongs to a different query"). The first version of the pager passed Moonfin's limits through (75 for a first page, 48 per scroll, 300 for a jump), so most cursor requests were refused and recovered only through the one restart. It was found at 6.11, where Brady's timing run got `invalid_cursor` for a next page asked with a new limit, and the alphabet jump failed outright.

**The pager.** `SiloPager.page(signature:, startIndex:, limit:, fetch:)` asks Silo for pages of **one fixed size** (`pageSize`, 100) whatever Moonfin asks for, and serves Moonfin's range from the pages it has fetched. Per query **signature** it remembers the window cursor, the next cursor and where it points, where the result ends once known, and the last 8 pages fetched. For each part of the range not already held it picks the cheapest request:

| Moonfin asks for | Request (always `limit=100`) |
|---|---|
| part of a page already fetched | nothing: served from memory |
| offset 0 | plain (no cursor) |
| one page from where the last page ended | `cursor=<next_cursor>` (scrolling down a grid) |
| any other offset, or more than one page | `cursor=<window_cursor>&seek=<offset>`, up to 4 pages at once (alphabet bar, a grid restored mid-way, going back) |
| an offset, with no window cursor yet | the first page, then the seeks |
| at or past the end | nothing: an empty answer |

**Rules.**

- **Any limit:** Moonfin's `limit` only decides how much of the fetched pages is returned. A large one (a jump loading 3,500 titles) is 35 seeks of 100, four at a time. No `limit` means 50 items, Silo's default.
- **Signatures:** `siloPageSignature(path, params)` keys a query by its parameters, sorted, without the paging ones (`cursor`, `seek`, `limit`) and without null or empty values. So the same library, sort and filters share cursors, and different ones never do.
- **Memory:** up to 32 queries are remembered, least recently used forgotten first. `clear()` forgets all of them, for a library change.
- **Rejected cursors:** when Silo rejects a cursor (expired, or the server restarted), the query's state is dropped and the request starts over from the first page, **once**; a second rejection is passed on. `isSiloInvalidCursorError` decides what counts: a 400 or 422 whose problem code mentions a cursor (`invalid_cursor`…), or whose field errors point at `cursor` or `seek`.
- **Totals:** `TotalRecordCount` is Silo's exact total when it gives one; otherwise where the result was seen to end (a page without more); otherwise Silo's estimate, never less than what has been seen; without any total, what has been seen plus one while Silo says there is more, so the grid keeps asking.
- **End of the list:** only `has_more: false` or an exact total ends a result; a page shorter than asked does not. A page that brings nothing though Silo claims more, or more claimed with no cursor to follow, ends the range instead of asking again.
- **No window cursor:** for a result Silo gives no window cursor, an offset is reached by following next cursors from the start; a range behind the walk starts it over.

`fetch` is a callback, so the pager knows nothing about endpoints. The items API (6.5) wraps each list call in it. `SiloPage.fromJson` reads Silo's list answers.

### Testing

**Automated tests** (`packages/server_silo/test/silo_pager_test.dart`, new, against a fake Silo list that issues and checks cursors; since the fix the fake also refuses a cursor sent with a different `limit`, as Silo does: 26 tests)

- Requests:
  - first page, next pages, seeks forward and back;
  - a jump before any first page;
  - every request to Silo has the same limit, whatever Moonfin asks;
  - ranges served from fetched pages without a request; going back served from what was kept;
  - a 3,500-title range as 35 seeks; a range past the end stops at the end;
  - no limit; past an exact total with no request;
  - signatures kept apart.
- Invalid cursors: a server "restart" mid-scroll recovers with one restart; a second rejection is passed on; other errors aren't retried; which problems count.
- Totals: an estimate corrected at the end; no total.
- No window cursor: an offset reached by walking.
- Odd answers: an empty page that claims more, and more with no cursor, end the range.
- Cache: least recently used forgotten; `clear`.
- Signatures: paging parameters, order and empty values ignored; list order kept.
- Reading the library page fixture (5 items, 4611 exact, both cursors) and a last page.
- `server_silo`: 304/304 at 5.12; 426/426 with the fix (on top of 6.19).

**Manual test plan**

- Nothing to check by hand until 6.5 scrolls a library grid. Regression: full `flutter test`.
- With the fix: scroll a large Silo library from top to bottom without stalls or a reload from the top; jump to letters far down (6.11); go back up.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | pager tests 20/20; `server_silo` 304/304; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| 2026-10-14 | macOS | `4b2e921c` | Fail | found at 6.11: Silo refused next and window cursors sent with a different `limit` (`invalid_cursor`); the alphabet jump failed |
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | fix: one fixed page size per query, pages kept; pager 26/26; `server_silo` 426/426 |
| | | | | |

---

<a id="step-5-13"></a>
## 5.13 Sort map

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `549c133` | 5.12 |

**Goal.** Moonfin sort fields → Silo `sort` values (descending = `-field`); unknown → server default.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_sort_map.dart` (new)

### How it works

Moonfin asks for an order the Jellyfin way: `sortBy` as a comma-separated list of fields (`ProductionYear,SortName`), and `sortOrder` (`Ascending`/`Descending`). Silo takes one term, `sort=field`, or `-field` for descending. Its contract names these fields: `title`, `year`, `release_date`, `added_at`, `rating`, `runtime`, `random`. `siloSortFor(sortBy:, sortOrder:)` gives the `sort` value, or null to leave `sort` out:

| Moonfin | Silo |
|---|---|
| `SortName`, `Name`, `SeriesSortName` | `title` |
| `ProductionYear` | `year` |
| `PremiereDate` | `release_date` |
| `DateCreated`, `DateLastContentAdded` | `added_at` |
| `CommunityRating` | `rating` |
| `Runtime` | `runtime` |
| `Random` | `random` (no direction) |

**Rules.**

- **First term only.** Only the **first** term of `sortBy` and `sortOrder` counts. When the first term has no Silo field, the answer is null rather than the next term. An episode list asked for in `ParentIndexNumber,IndexNumber,SortName` order must keep Silo's natural episode order, not be sorted by title.
- **Unknown fields leave `sort` out.** Silo then applies the list's saved or default order, rather than risk an error for a field it doesn't know. `CriticRating`, `OfficialRating`, `DatePlayed` and `PlayCount` are among them. Silo's items carry `play_count` and `viewed_at` sort metrics, so it may accept them as sort fields. The contract doesn't say, so they are left out until a check against the server (6.5) shows they work. "Recently watched" rows don't need them: they read Silo's progress and history lists (phase 8).
- **Reverse map.** `jellyfinSortForSilo('-added_at')` → `DateCreated`, `Descending`. It is for showing the order Silo applied (`effective_sort`) in Moonfin's sort menu.

### Testing

**Automated tests** (`packages/server_silo/test/silo_sort_map_test.dart`, new, 8 tests)

- Every mapped field, both directions; no order; case; `random` without direction.
- The first term only, and an unmapped first term leaving `sort` out (the episode order).
- Fields with no Silo sort, and no input.
- The reverse map, round-tripping every Silo field; unknown values.
- `server_silo`: 312/312.

**Manual test plan**

- Nothing to check by hand until 6.5 sorts a library grid. Then, in 6.5: try Moonfin's sort menu entries on a Silo library and note any that Silo ignores. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | sort map tests 8/8; `server_silo` 312/312; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

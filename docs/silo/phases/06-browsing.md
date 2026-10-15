# Phase 6: Browsing

[← Roadmap](../ROADMAP.md)

Libraries, grids and detail pages. Each step replaces one placeholder method with the real call.

**Phase done when:** You can open each library, scroll a full grid with artwork, open a movie, a series, its seasons and episodes, and the detail screen looks like it does on Emby.

---

<a id="step-6-1"></a>
## 6.1 Image API on the registry

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `6292646` | 5.13 |

**Goal.** `getPrimary/Backdrop/Logo/Thumb/BannerImageUrl` and user avatars from the registry (Thumb and Banner use Silo's own art when the item has it, otherwise the backdrop); user menu avatar goes through `imageApi`.

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_image_api.dart` (new)
- `packages/server_silo/lib/src/silo_image_registry.dart`: URLs by tag.
- `packages/server_silo/lib/src/silo_media_server_client.dart`: the client owns the registry (`images`) and answers `imageApi` from it.
- `packages/server_silo/lib/src/api/silo_users_api.dart`: registers the profile avatar.
- `packages/server_core/lib/src/models/server_type.dart`: `hasJellyfinUserImagePath`.
- `lib/ui/widgets/user_menu_dialog.dart`

### How it works

Jellyfin builds an image URL from an item id and an image type. Silo hands out ready, **signed** URLs inside each item, and the mappers (phase 5) record them in the client's `SiloImageRegistry` as they translate items. `SiloImageApi` answers every `ImageApi` call by looking a URL up, never building one:

- **With a `tag`** (what an item's `ImageTags`, `BackdropImageTags` or a person's `PrimaryImageTag` carry): exactly the URL registered with that tag. The registry now keeps URLs by tag as well as by slot, so a grid (which asks Silo for `medium` artwork) and a detail page (`large`) each get the size their own request returned, even though both fill the same slot.
- **Without one:** the latest URL for the item, type and index.
- **Size arguments:** `maxWidth`/`maxHeight` are ignored. Silo chooses sizes per request with `image_size`, and a signed URL can't be resized afterwards.

| `ImageApi` | Answer |
|---|---|
| `getPrimaryImageUrl` | poster, episode still, person photo, library poster |
| `getBackdropImageUrl` | backdrop by index |
| `getLogoImageUrl` | logo |
| `getThumbImageUrl` | Silo's thumb, else the backdrop (the mapper already registers it in the thumb slot) |
| `getBannerImageUrl` | Silo's banner, else the backdrop: Moonfin's banner cards are wide |
| `getChapterImageUrl` | chapter thumbnail by index (5.9) |
| `getUserImageUrl` | the profile avatar (below) |
| `getTrickplayTileImageUrl` | a sheet registered under the `mediaSourceId` (5.11); empty without one |

**No URL yet.** Nothing registered gives an empty URL, which Moonfin shows as its placeholder, as the old placeholder API did. Step 6.3 fills these misses.

**Avatars.** Silo's profile has an `avatar_url` (a preset such as `/avatars/presets/fox.png`, or an upload). `getCurrentUser` registers it under the profile id, which is the Moonfin user id, and sets the user's `PrimaryImageTag`.

The **user menu** used to build a Jellyfin URL (`/Users/{id}/Images/Primary`) for every server. It now asks the server's own client (`imageApi.getUserImageUrl`) when the server type has no Jellyfin user-image path (`ServerType.hasJellyfinUserImagePath`, false for Silo). With no client yet, or no avatar, it shows the initial as before. Jellyfin and Emby are unchanged.

The client owns the registry (`SiloMediaServerClient.images`), so the items API (6.4 onward) and `imageApi` share it. `SiloPendingImageApi` is removed.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_image_api_test.dart` (new, 10 tests):
  - from the mapped xXx: every tag it carries gives its URL; the slot without a tag; thumb and banner fall back to the backdrop; chapters by index; a person's photo;
  - tags pick the exact size when a grid and a detail URL share a slot;
  - misses give empty URLs; trickplay needs the file id;
  - the client's `imageApi` reads its registry.
- `silo_users_api_test.dart`: 2 new, an avatar is registered (tag and URL); no avatar, no tag.
- `server_silo`: 323/323.

**Manual test plan** (needs the libraries and grids of 6.4 and 6.5, so run it with all of phase 6)

- Posters, backdrops and logos show on Silo grids and detail pages.
- A Silo profile with an avatar (set one in Silo's web app) shows it in Moonfin's user menu; one without shows the initial. Emby accounts in the same menu are unchanged.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | image API tests 10/10, users 2 new; `server_silo` 323/323; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-2"></a>
## 6.2 Image cache keyed by path

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `e8f063f` | 6.1 |

**Goal.** Pass a path-only `cacheKey` so the signed query rotating every day doesn't re-download every image.

**Where in Moonfin**

- `packages/cached_network_image_fork/` (`CachedNetworkImageProvider.cacheKeyFor`)
- `packages/server_silo/lib/src/silo_image_cache_key.dart` (new)
- `lib/util/silo_image_hooks.dart` (new), installed from `lib/main.dart`

### How it works

**The problem.** Silo signs every artwork URL with a query that rotates: `…/poster/w500.f6c3….webp?exp=…&sig=…`. Moonfin's image cache (the vendored `cached_network_image`) keys memory and disk entries by the whole URL. Each new signature would therefore look like a new image: downloaded again, decoded again, cached twice.

**The fork hook.** The vendored provider gets one static hook, `CachedNetworkImageProvider.cacheKeyFor`. When a provider is built without an explicit `cacheKey`, the hook may name one for its URL. That key is used for the disk cache (the cache manager's `key`) and for the provider's equality, which is the memory cache's key. Unset, or returning null, everything behaves as before. `CachedNetworkImage.evictFromCache` uses the same key, so evicting still finds the entry. The fork's `pubspec.yaml` notes the change.

**The key.** `siloImageCacheKey(url)` returns `silo-artwork:<scheme://host/path>` for a URL under `/api/v2/artwork/` with a signed query (`sig=` or `exp=`), and null for anything else. The path names the picture (it carries a content hash), so:

- the same picture is one cache entry whatever its signature;
- a changed picture has a new path, so a new entry;
- another server, or the same path on another host, never collides;
- TMDB/TVDB photos, Emby and Jellyfin URLs keep their usual key, the URL.

**Wiring.** `installSiloImageHooks()` (app side) sets the hook at startup, right after the in-memory image cache is configured. The fork stays server-agnostic: it knows nothing about Silo, only that a key can be supplied.

**Stale entries.** When a cached file goes stale (14 days), the cache manager downloads it again from the URL the widget now holds, which carries a fresh signature.

**Known limit.** A library poster's path has no content hash (open item from 5.7), so a replaced library poster keeps its cache entry until it goes stale.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_image_cache_key_test.dart` (new, 3): one key across signatures; different pictures and hosts differ; unsigned, foreign and non-artwork URLs get none.
- `test/util/silo_image_hooks_test.dart` (new, 3, app):
  - without the hooks a new signature is a new provider;
  - with them the two are one cache entry (equal, same hash);
  - Emby URLs and explicit `cacheKey`s are untouched.
- `server_silo`: 326/326.

**Manual test plan**

- Browse a Silo library, quit Moonfin, and open it again the next day (or after Silo's signatures rotate). The artwork shows at once from the cache. Silo's request log shows no new `/api/v2/artwork/` downloads for posters already seen.
- Emby artwork caching is unchanged: browse an Emby library, restart, artwork shows from cache.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | cache key 3/3, hooks 3/3; `server_silo` 326/326; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-3"></a>
## 6.3 Image registry misses

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `b821d73` | 6.2 |

**Goal.** When nothing is registered for an item (cold start, deep link), follow the decision in DECISIONS.md D2 (resolver image provider or placeholder).

**Where in Moonfin**

- `packages/server_silo/lib/src/silo_image_resolver.dart` (new): placeholder URLs, `SiloImageResolver`, `SiloImageResolution`.
- `packages/server_silo/lib/src/api/silo_image_api.dart`: hands out placeholders for unseen items.
- `packages/server_silo/lib/src/silo_image_registry.dart`, mappers: which items were read (`note`/`knows`).
- `packages/server_silo/lib/src/silo_media_server_client.dart`: owns the resolver and loads artwork.
- `packages/cached_network_image_fork/` (`CachedNetworkImageProvider.urlResolver`)
- `lib/util/silo_image_hooks.dart`
- `lib/ui/widgets/user_avatar_image.dart` (new), used by `user_menu_dialog.dart`, `top_toolbar.dart`, `left_sidebar.dart` and `bottom_nav/bottom_nav_tab.dart`.
- `docs/silo/DECISIONS.md`: D2 decided.

### How it works

**The problem.** `ImageApi` is synchronous and asks by item id only. Silo has no image URL that can be built from an id: artwork comes signed, inside the item. So an image of an item this session hasn't read has no URL. That happens with rows restored from a cache at startup, a deep link, or a parent id (series of an episode, a person on a cached page).

**Decision D2: resolve by loading the item.** Brady chose this over a plain placeholder, so artwork always appears.

1. **Known or not.** The mappers now `note` every item, person and library whose artwork fields they read, whether or not it had any. A missing image of a **known** item doesn't exist, and the answer stays an empty URL (Moonfin's placeholder art), with no request. A logo request for a film with no logo costs nothing.
2. **Placeholder URL.** For an item **never read**, `SiloImageApi` returns a placeholder URL instead: `<server>/api/v2/__moonfin/image?item=<id>&type=<type>[&index=<n>]`. It is an ordinary-looking `https` URL, so every widget treats it like any image.
3. **The image cache resolves it.** The vendored `cached_network_image` gets a second static hook, `urlResolver`. Before downloading, the provider asks the hook about its URL. For an ordinary URL the hook answers `null` synchronously and the image loads as before, with no extra hop. For a placeholder it answers a future of the real URL. The download then uses that URL, keyed (6.2) by the real picture, so a picture already on disk is reused. A future that gives `null` fails the load like a missing image, **without a request**.
4. **The app wires it.** `installSiloImageHooks()` sets `urlResolver = SiloImageResolution.resolve`. That entry point finds the Silo client the URL belongs to (by base URL; each client registers its resolver while it exists and unregisters on dispose) and calls its `SiloImageResolver`.
5. **Loading.** The resolver checks the registry first. Otherwise it loads what Silo has on the id through the client (`_loadArtwork`), which registers the artwork:
   - a catalog id (`movie-…`, `series-…`, `season-…`, `episode-…`): `GET /catalog/items/{id}?image_size=large`, mapped as usual;
   - otherwise the library list (library posters). If that doesn't know the id: the profile list for a UUID (avatars), or `GET /catalog/people/{id}` (person photos).

**Guards.**

- Concurrent requests for one item share one load. A poster, backdrop and logo of the same unseen film load it once.
- An item that failed to load, or turned out to have no such image, isn't tried again for 10 minutes, so a grid of missing art doesn't hammer the server.
- The thumb and banner fallbacks to the backdrop (6.1) apply after loading too.

Trickplay sheets are never placeholders; step 11.2 fetches them.

**Avatars** (found in Brady's first test of 6.1–6.3: his Silo avatar didn't show). The avatar widgets didn't go through the image cache's provider, and Silo's preset avatars are **SVG**: its bundled set (`/profile-avatars/<id>.svg`) or DiceBear (`https://api.dicebear.com/9.x/<style>/svg?seed=…`). Flutter's bitmap decoders can't draw SVG; only uploaded avatars are bitmaps (`w256.webp`). The new `UserAvatarImage` widget:

- resolves a placeholder URL through the same `urlResolver` hook before loading;
- draws an SVG avatar with `flutter_svg` (already a dependency);
- loads anything else as before (`PacedNetworkImage`, decoded at the painted size).

The user menu, top toolbar, left sidebar and mobile bottom bar use it. For Jellyfin and Emby avatars only the user menu changes: it used `Image.network`, and now uses the same bitmap path as the toolbar.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_image_resolver_test.dart` (new, 13 tests):
  - placeholder URLs round-trip; ordinary URLs aren't placeholders and resolve to null synchronously;
  - placeholders are handed out only for unseen items (a known item without a logo gets an empty URL);
  - through the client: a catalog item loaded **once** at `large` for poster and logo together; a library poster; a person; a profile avatar;
  - a failed load gives null and isn't retried; an item without the image gives null; a disposed client's placeholders give null;
  - the retry wait; a resolver owns only its own server's placeholders.
- `silo_media_server_client_test.dart`: the old "image URLs are empty" test now checks an unseen item gets a placeholder its client resolves.
- `test/util/silo_image_hooks_test.dart`: 1 new, placeholders are resolved and other URLs load directly.
- `test/widgets/user_avatar_image_test.dart` (new, 6):
  - which URLs are SVG (Silo presets, DiceBear) and which are bitmaps;
  - no URL shows the fallback; a bitmap avatar is an `Image`;
  - a placeholder is resolved before loading; one with nothing behind it stays the fallback.
  - (Drawing a real SVG needs the network, so that path is checked by hand.)
- `server_silo`: 339/339.

A self-wait was caught by these tests: a `whenComplete` callback returning the removed future made the load wait on itself. It now uses a block body.

**Manual test plan**

- **Avatar:** a Silo profile with an avatar shows it in the user menu, the top toolbar (or left sidebar, depending on the navigation style) and the mobile bottom bar. Try a preset (SVG) and an uploaded photo; with none, the initial shows. Emby avatars still show everywhere.
- With Silo artwork showing, quit Moonfin and start it again. Any Silo row or page restored before its items are fetched again shows its artwork after a moment, not blank cards.
- Open a Silo episode's detail page straight after a cold start (or from a cached Continue Watching row once phase 8 lands): the series logo and backdrop appear.
- A Silo film without a logo shows its title text, and Silo's request log shows no repeated requests for it.
- Turn Silo off (or disconnect) and open a Silo page: placeholders, no flood of retries in the log; turn it back on and the art appears within ten minutes or on the next load.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | resolver 13/13, hooks 4/4; `server_silo` 339/339; analyzer: no issues in changed files |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-4"></a>
## 6.4 Libraries (`UserViewsApi`)

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `cfff681` | 6.3 |

**Goal.** `GET /user/libraries` with caching and `invalidateCache()`.

**Silo v2 endpoints**

- `GET /user/libraries`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_user_views_api.dart` (new)
- `packages/server_silo/lib/src/api/silo_users_api.dart`: `onConfigurationUpdated`.
- `packages/server_silo/lib/src/silo_media_server_client.dart`

### How it works

`SiloUserViewsApi.getUserViews` reads `GET /user/libraries` and maps it with the library mapper (5.7): `CollectionFolder` views with Silo's library ids, collection types and registered posters, openable types only (movies, series, mixed).

**Order and hidden libraries.** Jellyfin and Emby apply the user's library order and hidden list (`OrderedViews`, `MyMediaExcludes`) on the server, and parts of Moonfin rely on that. Silo doesn't for a profile without library restrictions. Its contract says the list includes the libraries the profile hid itself, and "navigation should filter by the setting". So this class applies the profile's settings (2.7), read through `UsersApi.getUserConfiguration`:

- `ui.library_order` orders the list; libraries it doesn't name follow in Silo's `sort_order`;
- `ui.disabled_library_ids` is left out, unless `includeHidden` is set. Silo is then also asked with `include_hidden=true`, so a restricted profile gets its hidden libraries back too;
- if the settings can't be read, the list comes back in Silo's order, unfiltered.

The settings request runs alongside the library request.

**Caching.** Answers are cached for five minutes per `includeHidden`, and concurrent callers share one request. `invalidateCache()` drops them. The users API now calls an `onConfigurationUpdated` callback after saving settings, and the client wires it to `invalidateCache`, as Emby does. Hiding or reordering a library in Moonfin's settings shows at once.

`SiloPendingUserViewsApi` is removed.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_user_views_api_test.dart` (new, 9 tests):
  - the captured libraries come out as Emby lists them (Movies, TV Shows; `movies`, `tvshows`);
  - podcasts are left out;
  - the profile's order and hidden list apply; `includeHidden` keeps hidden ones and sends `include_hidden=true`, and without it the parameter isn't sent;
  - unreadable settings give Silo's order;
  - caching and shared requests; saving the hidden list drops the cache;
  - posters are registered for `ImageApi`.
- `test/silo_test_client.dart` (new): shared setup for the phase 6 API tests.
- `silo_media_server_client_test.dart`: the placeholder check now uses `DisplayPreferencesApi` (6.19).
- `server_silo`: 348/348.

**Manual test plan**

- Signed in to Silo, the libraries show in the sidebar or toolbar, on Home's library row and in the library list, with their posters. They match Silo's web app.
- **Compare with Emby:** the library list and order match what Emby shows for the same libraries.
- From 2.7: hide a library and reorder libraries in Moonfin's library settings. Moonfin updates at once, and Silo's web app shows the same (`ui.disabled_library_ids`, `ui.library_order`). Unhide it again.
- From 3.5: with Moonfin open on a library, sign its session out from Silo's sessions page, then open another library. Expected: Moonfin returns to the login screen with your name filled in.
- A Silo library named like "Games" (if you have a mixed one) doesn't open the games browser (from 5.7).
- From 4.3: with Silo and Emby signed in, a Silo film's detail screen and context menu have no Add to playlist; an Emby film's still do (needs 6.6).
- From 4.7: a Silo film's detail screen shows no MDBList/TMDB rating badges and logs no errors; Silo's request log shows no `/Moonfin/` requests (needs 6.6).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | user views 9/9; `server_silo` 348/348; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-5"></a>
## 6.5 Library grid (`getItems` for a library)

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `cc2b4f6` | 6.4 |

**Goal.** Library id → `library_id`, type filter, sort, page through the cursor pager.

**Silo v2 endpoints**

- `GET /catalog`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart` (new)
- `packages/server_silo/lib/src/silo_media_server_client.dart`

### How it works

`SiloItemsApi` is the client's `ItemsApi`. This step brings its first real method, `getItems` for a library grid (or the whole catalog), and the frame later steps fill in.

**`getItems`.**

| Moonfin | Silo `GET /catalog` |
|---|---|
| `parentId` = a library id | `library_id` (Silo's library ids are plain numbers; no parent = the whole catalog) |
| `includeItemTypes` | `type` (5.1): `Movie` → `movie`, `Series` → `series`, both → `video`, `Episode` → `episode` |
| `sortBy`, `sortOrder` | `sort` (5.13), first term only, unmapped → Silo's default order |
| `startIndex`, `limit` | cursors through `SiloPager` (5.12): next page by `next_cursor`, a jump by `window_cursor` + `seek`, at most 200 per request |
| — | `image_size=medium` (posters 500 px, backdrops 1920) |

Each item is mapped (phase 5) and its artwork registered, and the answer is Jellyfin's `{Items, TotalRecordCount, StartIndex}`.

**Types.**

- Types Silo can't serve (`BoxSet`, `Playlist`, music, `TvChannel`) are dropped from the request. A query for **only** such types answers empty **without a request**, so a Continue listening, album or playlist row never fills with films (4.2, 4.3, 5.1).
- `excludeItemTypes` is applied to what comes back.
- Item types Moonfin can't open yet (audiobooks, ebooks until phase 16; podcasts) are dropped too.
- A type mix with no single Silo scope (say movies with episodes) asks for everything and keeps the asked types.

**Not yet.** Parents other than a library (series, seasons, genres, studios, collections, people) and `ids` throw `SiloNotImplementedError` naming their step. The grid's filter arguments (genres, years, ratings, favourites, played state, name prefix) are not applied until 6.10–6.11.

**The rest of `ItemsApi`.**

- Methods not implemented yet throw `SiloNotImplementedError` with their roadmap step (a table in the class, through `noSuchMethod`), as the old placeholder did.
- Silo has no music or playlists, so `getPlaylists`, `getPlaylistItems`, `getArtists`, `getAlbumArtists` and `getLyrics` answer empty, like Live TV, so a shared row renders nothing.
- Playlist changes and deleting media are refused with `UnsupportedError`.

`SiloPendingItemsApi` is removed.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_library_test.dart` (new, 8 tests):
  - the captured library page: 5 items, total 4611, `library_id`, `type=movie`, `sort=title`, `image_size=medium`, artwork registered;
  - TV and mixed libraries ask for `series`, `video`, or no type;
  - sort direction;
  - scrolling a 300-item library: first page, `next_cursor`, then a jump by window cursor + `seek`;
  - only unservable types: empty, **no request**; excluded and unopenable types dropped;
  - later steps name themselves; music and playlists answer empty, playlist changes refused.
- `server_silo`: 356/356.

**Manual test plan**

- Open each Silo library from the sidebar or toolbar: the grid fills with posters, the item count is right, and it scrolls smoothly to the end of the largest library. Compare the count with Silo's web app.
- Change the sort (name, date added, release date, year, rating, runtime, random) in both directions. Each re-sorts.
- Carried from 5.12 and 5.13: jump with the alphabet bar and scroll back up (window cursor + seek; the letter bar itself is 6.11). Try every entry of Moonfin's sort menu on a Silo library, both directions. Fields 5.13 leaves unmapped (critic rating, date played, play count…) fall back to Silo's default order. Note any that Silo could sort by, and whether `play_count` / `viewed_at` work as `sort` values.
- Carried from 4.2, 4.3 and 5.1: with only Silo signed in, no Continue listening, artist, album or playlist row fills with films or episodes (rows that load once Home loads, phase 8).
- Filters in the grid's filter menu don't apply yet (6.10). A film opens a detail page only from 6.6.
- An Emby library grid is unchanged.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | library grid 8/8; `server_silo` 356/356; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-6"></a>
## 6.6 Movie detail (`getItem`)

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.5 |

**Goal.** Item detail with its versions in one call when available.

**Silo v2 endpoints**

- `GET /catalog/items/{id}`
- `GET /catalog/items/{id}/versions`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`: `getItem`, `getItems(ids)`.
- `packages/server_silo/lib/src/api/silo_user_library_api.dart` (new)
- `packages/server_silo/lib/src/silo_media_server_client.dart`

### How it works

**`getItem(id)`** reads `GET /catalog/items/{id}?image_size=large` and maps it (phase 5): core fields, series links, user data, people, media sources, chapters. Artwork is registered at the detail size (posters 780 px), and the item's tags pick exactly those URLs (6.1).

- **Versions.** Silo's detail answer embeds `versions` for playable items, so a movie or episode costs **one** request. When a playable item's answer has no `versions` (an older server, a trimmed answer), they are read from `/catalog/items/{id}/versions` and merged, so `MediaSources` are always there.
- **`mediaSourceId`** is sent as `file_id`, which makes that version the item's effective one.
- **A library id** (Moonfin asks for the library it is browsing) answers the library's view from the libraries list (6.4).
- **`fields`** is ignored: Silo has no field selection, and its detail answer is always whole.

**`ParentId`.** Silo's item answers don't name their library. The items API remembers which library each item was listed in by a grid (up to 5000 items, oldest forgotten first), sets `ParentId` on the grid's items and later on their detail, and offers `libraryOf(id)` for the ancestors (6.9).

**`getItems(ids: …)`** reads each item with `getItem`, six at a time, in the order asked. Ids Silo doesn't know are left out. Silo has no "these ids" list query.

**`UserLibraryApi`.** The new `SiloUserLibraryApi` answers `getItem` through the items API. Favourites, played state and ratings throw `SiloNotImplementedError` naming their phase 9 step. `supportsNumericUserRatings` is true (Silo rates 0–10). `SiloPendingUserLibraryApi` is removed.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_detail_test.dart` (new, 8 tests):
  - a movie in one request at `image_size=large`, with versions, people and registered artwork;
  - versions fetched when the detail has none; a series has none to fetch;
  - `mediaSourceId` → `file_id`;
  - a library id answers its view; `UserLibraryApi.getItem` is the same, and favourites name 9.1;
  - an item listed in a library knows its `ParentId`;
  - `getItems(ids)` keeps the order and drops unknown ids.
- `silo_items_api_library_test.dart`: "later steps name themselves" now checks `getSeasons` (6.7).
- `server_silo`: 364/364.

**Manual test plan**

- Open a film from a Silo grid. The detail page shows title, year, rating, runtime, overview, genres, studios, cast with photos, backdrop and logo.
- **Compare with Emby:** open the same film on Emby. Overview, cast, ratings, runtime and version badges (resolution, HDR, audio) match.
- A film with two versions (The Salt Path) offers both in the version picker, 4K first. The audio and subtitle lists name the tracks like Emby ("English DTS 5.1 (Default)").
- Chapters show with thumbnails where the file has them.
- From 4.3: a Silo film's detail screen and context menu have no Add to playlist; an Emby film's still do.
- From 4.7: a Silo film's detail screen shows no MDBList/TMDB rating badges and logs no errors; Silo's request log shows no `/Moonfin/` requests.
- Favourite and watched buttons answer with an error until phase 9; Play until phase 10.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | detail 8/8; `server_silo` 364/364; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-7"></a>
## 6.7 Series detail and seasons

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.6 |

**Goal.** Series detail and `getSeasons`.

**Silo v2 endpoints**

- `GET /catalog/series/{id}/seasons`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`

### How it works

**Series detail** is `getItem` (6.6). A series has no versions, so it is one request. Its `play_content_id`, season count, show status and unplayed count come through the mappers (5.3–5.5).

**`getSeasons(seriesId)`** reads `GET /catalog/series/{id}/seasons?include_artwork=true&image_size=medium`. `include_artwork` is the parameter `images/capabilities` names (`season_list_artwork_param`) for season posters. Seasons come in Silo's order (specials first when the series has them, as on Emby). Season entries carry no `type` and no series fields, so each is mapped as a season of that series:

- `SeriesId` and `SeasonId` links;
- `IndexNumber` from `season_number`, `ChildCount` from `episode_count`;
- `UserData` with `UnplayedItemCount`;
- parent artwork fields from the series' registered artwork (5.4).

**Series title.** Season and episode entries don't repeat the series title. The items API remembers titles of series it has read (detail or grid) and fills `SeriesName` from that.

**Also routed here:**

- `getItems(parentId: <series id>)` lists the seasons, as Jellyfin does for a series' children.
- `getItem(<season id>)` (a season page) answers from the series' season list. The list carries everything a season page shows, while Silo's item endpoint is for titles. The series is found from the season id (`season-<key>-<n>` → `series-<key>`, 5.4); a season the list doesn't have is an error.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_series_test.dart` (new, 4 tests):
  - the captured Young Justice seasons match Emby's names and numbers; links, `SeriesName`, unplayed count and poster; `include_artwork` and `image_size` sent;
  - a series as `parentId` lists its seasons;
  - a season by id comes from its series' list; a missing season is an error.
- `test/silo_test_client.dart`: `siloEmbyFixture`.
- `server_silo`: 368/368.

**Manual test plan**

- Open a Silo series. The detail page shows its overview, cast, networks, status (Ended/Continuing) and backdrop and logo.
- The seasons row shows every season with its poster and unwatched count. **Compare with Emby:** same seasons, same order.
- Open a season: its page shows the season poster, the series' backdrop, and the episodes (episodes are 6.8).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | seasons 4/4; `server_silo` 368/368; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-8"></a>
## 6.8 Season episodes

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.7 |

**Goal.** `getEpisodes(seasonId)` via `/catalog/items/{season_id}/episodes`; whole-series episodes when no season is given.

**Silo v2 endpoints**

- `GET /catalog/items/{id}/episodes`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`

### How it works

**`getEpisodes(seriesId, seasonId:)`**:

- **With a season:** `GET /catalog/items/{season_id}/episodes?image_size=medium`, the call Silo's own web app uses for a season page.
- **Without one:** every season's episodes in season order, specials first when the series has them. The seasons come from `getSeasons`, and their episodes are read four seasons at a time.
- A season id passed as `seriesId` is treated as the season, and the series is worked out from the season id.

Episode entries carry no type and no series fields, so they are mapped as episodes of the series:

- `SeriesId`, `SeasonId`, `ParentIndexNumber`, `IndexNumber`, and `SeriesName` (6.7);
- the episode still, falling back to the series' artwork (5.4);
- user data; a list entry without `user_data` is unplayed at 0 (5.5);
- a lightweight `MediaSources` entry from `files[]`, enough for the resolution and HDR badges (5.8). The detail page reads the full versions with `getItem`.

`getItems(parentId: <season id>)` lists the season's episodes too.

### Testing

**Automated tests**

- `silo_items_api_series_test.dart`, 3 new (7 in all):
  - a season's episodes match Emby's names and numbers, with links, `SeriesName` and a media source, from the right endpoint;
  - a season as `parentId`;
  - a whole series: specials first, then season 1.
- `server_silo`: 371/371.

**Manual test plan**

- Open a season of a Silo series: every episode shows with its still, number, title, runtime and overview. **Compare with Emby:** same episodes, same order.
- The resolution badge (e.g. 1080p) shows on episode cards where Moonfin draws one.
- Open an episode: its detail page shows the episode, the series' logo and backdrop, its cast (the series regulars), versions and chapters.
- A series' "all episodes" views (the episode browser, the next/previous episode arrows on an episode page) step through every season.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | episodes 3 new; `server_silo` 371/371; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-9"></a>
## 6.9 Ancestors

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.8 |

**Goal.** Synthesise episode → season → series → library for breadcrumbs and back navigation.

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`
- `packages/server_silo/lib/src/mappers/silo_ids.dart`: `parseSiloEpisodeId`.

### How it works

Jellyfin's `getAncestors` lists an item's parents, nearest first. In Moonfin today one place reads it: the detail page, looking for the collections (`BoxSet`) an item belongs to. Silo has no ancestors call and needs none, because the parents are in the ids (5.4): `episode-<key>-<s>-<e>` → `season-<key>-<s>` → `series-<key>`. `parseSiloEpisodeId` reads an episode id like `parseSiloSeasonId` reads a season's.

| Item | Ancestors |
|---|---|
| episode | season, series, library |
| season | series, library |
| film or series | library |

- **Season names** are "Season <n>", or "Specials" for 0. **Series titles** are those read this session (6.7).
- **The library** is the one the item, or its series, was listed in by a grid (6.6), named from the libraries list. It is left out when unknown, since Silo's item answers don't name it.
- **No catalog request** is made.

Collections an item is in are added by 6.15.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_ancestors_test.dart` (new, 4 tests):
  - episode ids parse;
  - an episode gives season, series and library with no catalog request;
  - a season of specials, a season, a film;
  - nothing known gives no ancestors.
- `server_silo`: 375/375.

**Manual test plan**

- Open an episode's and a film's detail page from a Silo grid: no errors in the log from the ancestors call. With collections (6.15), a film in a Silo collection shows that collection on its page.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | ancestors 4/4; `server_silo` 375/375; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-10"></a>
## 6.10 Library filters

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.9 |

**Goal.** `getQueryFilters` and genre, year and rating filters in `getItems`.

**Silo v2 endpoints**

- `GET /catalog/filters`
- `GET /catalog` with rule `groups`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`
- `packages/server_silo/lib/src/mappers/silo_filters_mapper.dart` (new)
- `lib/data/viewmodels/library_browse_view_model.dart`: `supportsUhdFilter` true for Silo.

### How it works

**Filter values.** `getQueryFilters(parentId, includeItemTypes)` reads `GET /catalog/filters?library_id=…&type=…`. `siloFiltersToQueryFilterValues` turns it into what the filter picker offers:

- genres;
- content ratings;
- audio and subtitle languages from the files (`technical`), named in English (5.8). `und` is left out.

Silo has **no year list and no tags**, so those sections stay hidden.

**Filtering.** Silo filters a catalog list with **rule groups**: `groups` is a JSON array of `{match, rules: [{field, op, value}]}`, the vocabulary Silo's smart collections use, and groups combine with `match=all`. `siloRuleGroups` turns Moonfin's `getItems` filters into one group each, matching any of its values:

| Moonfin | Silo rule |
|---|---|
| `genres` | `genre is` |
| `years` | `year is` |
| `officialRatings` | `content_rating is` |
| `filters: IsPlayed` / `IsUnplayed` | `watched is true` / `false` |
| `filters: IsResumable` | `in_progress is true` |
| `filters: IsFavorite`, `isFavorite` | `favorited is true` |
| `is4K` | `resolution is 2160p` (false: `is_not`) |
| `isHd` | `resolution is 1080p` or `720p`; false: none of 2160p, 1080p, 720p |
| `audioLanguages`, `subtitleLanguages` | `audio_language is`, `subtitle_language is` |

The groups are part of the query's cursor signature (5.12), so changing a filter starts a fresh traversal.

**Not filterable on Silo.**

- `Likes`/`Dislikes`, tags, trailers, extras, theme media, video types, `hasSubtitles` and 3D have no Silo rule and are left out.
- Series status (`Continuing`/`Ended`) has no rule either: Silo's `status` rule is the metadata match state, not the airing state. Each card carries `show_status`, so the filter is applied in Moonfin, but not page by page: a filtered page would come back short while the total still counted the whole library, and the grid would lose its place (Brady's first test: *Continuing* showed only the shows already loaded). With a series status asked for, the items API reads the whole list once (in chunks of 1,000), keeps the matching shows, and pages them from memory with an exact total. The list is kept for two minutes (four lists at most) so the grid's next pages need no request.

**4K filter.** Moonfin offered its 4K option only on Jellyfin; Silo can filter by resolution, so `supportsUhdFilter` is now true for every server but Emby.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_filters_test.dart` (new, 8 tests):
  - the captured filter document: genres, ratings, no years, English named, `und` left out;
  - `getQueryFilters` sends `library_id` and `type`;
  - no groups when nothing applies; one group per filter with any-of values; played, favourite, quality and language rules;
  - `getItems` sends the groups as JSON, and different filters are different queries;
  - the series status filter on a page;
  - series status over a 450-show library paged by cursor: exact total (150 continuing), full pages, later pages from memory, *Ended* read separately.
- `test/data/viewmodels/library_browse_filters_test.dart` (existing) still passes.
- `server_silo`: 382/382 at 6.10; 415/415 with the fix (on top of 6.19).

**Manual test plan**

- In a Silo library's filter menu: genres, parental ratings and audio/subtitle languages list what the library holds; there is no year or tag section.
- Each filter narrows the grid: a genre, two genres (either), a rating, watched / unwatched / in progress, favourites (none until favourites can be set in phase 9, or set some in Silo's web app), 4K and HD, an audio language. Combined filters narrow further.
- Series status (continuing/ended) on a TV library narrows the shows. *Continuing* lists every airing show in the library, not only the ones on screen: scroll to the end and compare with Silo's web app.
- Clearing filters brings back the whole library. Emby's filter menu is unchanged (no 4K option).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | filters 7/7; `server_silo` 382/382; browse filter tests pass; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| 2026-10-14 | macOS | `4b2e921c` | Fail | Brady: every filter works except *Continuing*, which only matched shows already loaded; *Ended* looked right because most shows have ended |
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | fix: whole-list series status; filters 8/8; `server_silo` 415/415; analyzer: no issues |
| | | | | |

---

<a id="step-6-11"></a>
## 6.11 Alphabet jump

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.10 |

**Goal.** Letter index and `nameStartsWith` through the new letters endpoint.

**Silo v2 endpoints**

- `POST /catalog/letters`
- `GET /catalog?name_prefix=`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`
- `packages/server_silo/lib/src/silo_pager.dart`: large requests seek in parallel.
- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart`: `SortName` from Silo's sort title.
- `packages/server_core/lib/src/api/letter_position_api.dart` (new): `LetterPositionApi`, an optional extra for an `ItemsApi`.
- `lib/data/viewmodels/library_browse_view_model.dart`: `ensureItemsLoadedForPrefix` asks for the position first.

### How it works

- **`nameStartsWith` → `name_prefix`.** Both match the start of the sort title ("The Hobbit" sorted as "Hobbit, The" is under H). Moonfin's `#` bucket (titles not starting with a letter) has no prefix equivalent, so a `#` or blank prefix sends none. The letter-bucket browse in Android Auto and CarPlay (`media_browse_service.dart`) uses this.
- **The letter index.** `SiloItemsApi.letters(libraryId:, includeItemTypes:, descending:)` reads `POST /catalog/letters`. It answers the letters that have titles, each title's count, and its zero-based position in the title-ordered list (`SiloLetterIndex`, `positionOf`). A position sent as `seek` with the list's window cursor loads that letter's window directly (5.12).
- **The jump bar.** Moonfin's library jump bar finds a letter by loading pages until one appears (`ensureItemsLoadedForPrefix`), 300 titles a page, and gives up after 15 seconds. The first version left that unchanged on Silo, and Brady's test showed it failing: a letter far down a 4,600-title library took about 30 requests one after another (Silo pages hold 200), so the jump timed out and only worked once the grid had already loaded that far. Now:
  - **Position first.** `SiloItemsApi` implements `LetterPositionApi.letterPosition(letter, parentId:)`. It remembers, per parent, the last `getItems` query sorted by name (library, scope, rule groups, direction) and asks `/catalog/letters` with the same scope and groups. The view model loads from where it is to that position plus one page in **one** `loadMore`, then its usual walk finishes the job (dropped or hidden items can shift the count a little). The grid stays one contiguous list. Any other sort, a person's or collection's titles, a `name_prefix` query or a series-status filter (6.10) forgets the query, and the jump walks as before. Jellyfin and Emby don't implement the interface and are unchanged.
  - **Parallel pages.** A request for more than one Silo page now seeks to each page from the window cursor, four at a time, instead of following `next_cursor` one by one (it still does that when Silo gives no window cursor). Reaching S in that library is about 5 rounds of requests instead of 30.
- **Sort names.** Silo orders titles by their sort title, and its default moves a leading article to the end ("The Hobbit" → "Hobbit, The"; server `titleutil.DeriveDefaultSortTitle`). Cards don't carry `sort_title`, only the detail does, so the item mapper gives `SortName` the detail's `sort_title` when present and otherwise the same default (`siloDefaultSortTitle`). Moonfin's alphabet bar files titles by `SortName`, so "The Hobbit" is now under H where Silo's list puts it, rather than under T while sitting among the H titles. A sort title an admin set by hand shows on the detail only; such a title on a card may still file by its default.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_alphabet_test.dart` (new, 8 tests):
  - `nameStartsWith` → `name_prefix`; `#` and blank send none;
  - the captured letter index (4611 titles, `#` first, B at 347), sent as a POST with library, type and order;
  - `letterPosition` for the list on screen: same library, scope and genre group, ascending and descending; none for another sort, a series status, or no list (and no request);
  - `siloDefaultSortTitle` (The/A/An, the article alone, "Theodore"); a card's default sort name, a detail's own `sort_title`.
- `silo_pager_test.dart`: a fill above 200 seeks the rest in parallel; a long fill goes in batches of four and stops at the total; without a window cursor it follows next cursors.
- `test/data/viewmodels/library_browse_search_test.dart`: 2 new, a server with a letter index reaches M in one request; with no position the walk runs as before.
- `server_silo`: 385/385 at 6.11; 422/422 with the fix (on top of 6.19).

**Manual test plan**

- In a large Silo library sorted by name, tap letters far down the bar (S, W) straight after opening it, without scrolling: the grid lands on that letter within a few seconds. `#` lands on the first titles.
- Titles starting with "The" or "A" sit under their second word, where Silo's web app shows them; tapping T lands on real T titles.
- Sorted by name descending, a letter still lands right. Sorted by date added, the jump walks as on Emby.
- Emby's jump bar is unchanged.
- Android Auto / CarPlay letter buckets (deferred platform check, 17.5): a Silo library's letters list the right titles.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | alphabet 3/3; `server_silo` 385/385; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| 2026-10-14 | macOS | `4b2e921c` | Fail | Brady: the jump only worked for letters already loaded by scrolling |
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | fix: letter position, parallel pages, sort names; alphabet 8/8; `server_silo` 422/422, pager 22/22, browse search 16/16; analyzer: no new issues |
| | | | | |

---

<a id="step-6-12"></a>
## 6.12 Genres

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.11 |

**Goal.** Genre list as synthetic Genre items, and the genre's items.

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`
- `packages/server_silo/lib/src/mappers/silo_filters_mapper.dart`: `siloNamedItem`, genre ids in `siloRuleGroups`.

### How it works

Silo names genres but gives them no id, count or artwork. Moonfin opens a genre page by id, so genres get the synthetic ids from 5.1: `silo-genre:<name>`, percent-encoded.

- **`getGenres(parentId, …)`** reads the library's filter document (`getQueryFilters`, 6.10) and answers its genres as Jellyfin `Genre` items (`siloNamedItem`). They are sorted by name, ascending or descending, and `startIndex`/`limit` slice the list. With no counts, Moonfin keeps every genre (`genreReportsCounts`). With no artwork, the genre cards use art from the genre's titles, which Moonfin already does.
- **A genre's titles.** `getItems(genreIds: [silo-genre:…])`, which the genre browse sends along with the library as `parentId`, becomes a `genre is <name>` rule (6.10). So does a genre id passed as the `parentId` itself, without a library.
- **`getItem(<genre id>)`** answers the genre item with no request, for the genre page's title.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_genres_test.dart` (new, 4 tests):
  - a library's genres as `Genre` items with synthetic ids, from `library_id`'s filter document;
  - descending order and slicing;
  - a genre's titles by genre id (a name with `&` and spaces round-trips) or as the parent;
  - `getItem` on a genre id names it with no request.
- `server_silo`: 389/389.

**Manual test plan**

- A Silo movie or TV library's Genres view lists its genres. Cards show artwork from titles in that genre.
- Open a genre: its titles show, only from that library, and sort and filter like a library grid.
- The all-genres screen, and the genre pickers in home sections, media bar, screensaver and shuffle settings, list Silo genres.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | genres 4/4; `server_silo` 389/389; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-13"></a>
## 6.13 Studios and networks

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.12 |

**Goal.** Same pattern as genres.

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`
- `packages/server_silo/lib/src/mappers/silo_filters_mapper.dart`: studios in `siloRuleGroups`.

### How it works

Same pattern as genres (6.12), with `silo-studio:<name>` ids and `Studio` items. One difference: Moonfin shows a series' network as its studio (5.3 maps networks first), while Silo keeps studios and networks apart.

- **`getStudios(parentId, …)`** reads `GET /catalog/filters` (with `skip_technical`, since only names are needed) and lists `networks` and `studios` together, each name once, sorted, sliced by `startIndex`/`limit`.
- **A studio's titles.** `getItems(studios: [name])`, which the studio browse sends, a studio id among them, or a studio id as the `parentId`, becomes one group matching `studio is <name>` **or** `network is <name>`. So "HBO" finds HBO series and "Warner Bros." finds Warner films.
- **`getItem(<studio id>)`** names it, with no request.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_studios_test.dart` (new, 3 tests):
  - studios and networks together, sorted, once each (`A24` is both); `library_id` and `skip_technical` sent;
  - a studio's titles match the studio or the network, by name or by id as parent;
  - `getItem` on a studio id.
- `server_silo`: 392/392.

**Manual test plan**

- Click a studio on a Silo film's detail page, and a network on a series' page: the studio page lists that studio's titles (films by studio, series by network).
- Home row settings that pick studios list Silo's studios and networks.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | studios 3/3; `server_silo` 392/392; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-14"></a>
## 6.14 People

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.13 |

**Goal.** Person detail and filmography.

**Silo v2 endpoints**

- `GET /catalog/people/{id}`
- `GET /catalog (source=person)`

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_person_mapper.dart` (new)
- `packages/server_silo/lib/src/api/silo_items_api.dart`

### How it works

**A person's page.** `getItem(<person id>)` reads `GET /catalog/people/{id}`. `siloPersonToBaseItemDto` turns it into the Jellyfin `Person` item Moonfin's person page reads:

| Jellyfin | Silo |
|---|---|
| `Overview` | `bio` |
| `PremiereDate` / `EndDate` | `birth_date` / `death_date` (born, died) |
| `ProductionLocations` | `[birthplace]` |
| `ProviderIds` | `imdb_id`, `tmdb_id`, `tvdb_id` |
| `ImageTags.Primary` | `photo_url`, registered under the person's id |
| `ExternalUrls` | `homepage`, when there is one |

**Library or person.** Silo's person ids and library ids are both plain numbers. `getItem` checks the libraries the profile can see first (cached, 6.4) and otherwise reads the id as a person.

**Filmography.** `getItems(personIds: [id])` pages Silo's `source=person&person_id=…`, with the usual sort, type and paging. Silo pages one person at a time, so a list of several people uses the first. The person page asks for films, series, music videos and episodes; there is no single Silo scope for that mix, so everything is asked for and those types are kept (6.5).

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_people_test.dart` (new, 4 tests):
  - Vin Diesel's page: bio, birth date, birthplace, provider ids and registered photo;
  - a library id still answers the library;
  - filmography sends `source=person`, `person_id` and `sort=-release_date`, with no type for the mix;
  - a death date.
- `server_silo`: 396/396.

**Manual test plan**

- On a Silo film's detail page, open a cast member. Their page shows photo, biography, birth date and place, and their films and series on Silo, newest first.
- **Compare with Emby:** the same person's page shows the same biography and dates.
- A crew member (director) opens the same way.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | people 4/4; `server_silo` 396/396; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-15"></a>
## 6.15 Collections (browse)

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.14 |

**Goal.** Personal and library collections as BoxSets, and their items.

**Silo v2 endpoints**

- `GET /collections` (and `?contains_item=`)
- `GET /library/{id}/collections`
- `GET /catalog?source=user_collection|library_collection&collection_id=`

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_collection_mapper.dart` (new)
- `packages/server_silo/lib/src/mappers/silo_ids.dart`: collection ids.
- `packages/server_silo/lib/src/api/silo_items_api.dart`
- `packages/server_silo/lib/src/silo_media_server_client.dart`: collection artwork for the resolver (6.3).

### How it works

Silo has two kinds of collections:

- **personal** ones, made by a profile (`GET /collections`), possibly shared within the household;
- **library** ones, curated by the admin per library (`GET /library/{id}/collections`).

Both become Jellyfin `BoxSet`s (`siloCollectionToBoxSet`):

- name or title, description, `ChildCount` from `item_count`;
- poster and (library ones) backdrop, registered;
- `CollectionType: boxsets`, and `ParentId` for a library's.

**Ids.** Silo's collection ids are opaque strings. So they get prefixes that tell them apart from titles, people and libraries: `silo-collection:<id>` for personal ones, `silo-libcollection:<library>:<id>` for a library's (it is read through its library). `parseSiloCollectionId` reads them back.

**Where they show.**

- `getItems(includeItemTypes: [BoxSet])` with a library as parent lists that library's collections; with no parent, the profile's personal ones. A grid that groups collections (`Movie, BoxSet`) still gets its films, since Silo has no "collapse into collections" listing.
- **A collection's titles:** `getItems(parentId: <collection id>)` pages the catalog with `source=user_collection` or `library_collection` and `collection_id` (plus `library_id` for a library's). Sort, filters and the cursor pager apply as on a library grid.
- **A collection's page:** `getItem(<collection id>)` finds it in its list; Silo has no single-collection read for a viewer.
- **"In collection" on a title's page:** the ancestors (6.9) now add the personal collections holding the item, from `GET /collections?contains_item=<id>`. The detail page also scans the personal collections, a short list on Silo, for membership. Library collections can't be asked about membership, so they don't show there.
- **Artwork after a cold start:** the 6.3 resolver loads a collection's artwork through its list.

Creating and changing personal collections is 9.5.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_collections_test.dart` (new, 7 tests):
  - collection ids round-trip;
  - personal collections as BoxSets with count, overview and registered poster;
  - a library's collections with backdrop and `ParentId`;
  - a grouping grid still gets its films;
  - a collection's titles page through the catalog with the right source, id and library;
  - a collection's page;
  - ancestors list the personal collections holding the item (`contains_item`).
- `silo_items_api_library_test.dart`: `BoxSet` alone now lists collections, so it left the "types Silo can't serve" check.
- `server_silo`: 403/403.

**Manual test plan**

- Make a personal collection in Silo's web app with a few films. In Moonfin, it shows where Moonfin lists collections (collections view, a film's "in collection" section). Opening it lists its films, which sort and filter.
- If your Silo libraries have curated collections (admin), they show for their library and open the same way.
- A film in a personal collection shows that collection on its detail page.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | collections 7/7; `server_silo` 403/403; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-16"></a>
## 6.16 Similar items

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.15 |

**Goal.** "More like this".

**Silo v2 endpoints**

- `GET /recommendations/similar/{id}`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`

### How it works

`getSimilarItems(id, limit:)` reads `GET /recommendations/similar/{id}?limit=…`, Silo's own recommendations for the title. Items are mapped like a grid's: artwork registered, series titles remembered. Types Moonfin can't open yet (audiobooks, ebooks) are left out. Moonfin's `bypass` (a cache-buster for Jellyfin's similar cache) has nothing to bypass on Silo.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_similar_test.dart` (new, 2 tests): xXx's recommendations (first: xXx: State of the Union) with `limit` sent and artwork registered; unopenable types left out.
- `server_silo`: 405/405.

**Manual test plan**

- A Silo film's and a series' detail page shows a "More like this" row with posters. **Compare with Emby:** similar titles (they come from different engines, so not the same list).
- Opening one from the row opens its detail page.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | similar 2/2; `server_silo` 405/405; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-17"></a>
## 6.17 Trailers and extras

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.16 |

**Goal.** Local trailers and special features from the item's extras.

**Where in Moonfin**

- `packages/server_silo/lib/src/mappers/silo_extras_mapper.dart` (new)
- `packages/server_silo/lib/src/mappers/silo_item_mapper.dart`: `RemoteTrailers`, extra counts.
- `packages/server_silo/lib/src/api/silo_items_api.dart`

### How it works

A Silo title's detail carries two kinds of supplemental video:

- **`videos[]`:** remote videos from the metadata provider (YouTube trailers and the like: `kind`, `site`, `site_key`, `name`). The item mapper now turns them into Jellyfin's `RemoteTrailers` (`{Url, Name}`), trailers and teasers first. YouTube and Vimeo get their watch URLs; other sites are left out. xXx's trailer gives exactly Emby's URL.
- **`extras[]`:** local extra files the scanner found beside the title (`content_id`, `kind`, `title`, `duration_seconds`, `file_id`). The mapper sets `LocalTrailerCount` (trailers and teasers) and `SpecialFeatureCount` (the rest) when the detail lists them.

The items API answers:

- `getLocalTrailers(id)`: the trailers and teasers;
- `getSpecialFeatures(id)`: the others.

Both come from the title's detail. Each extra is a video item (`siloExtraToBaseItemDto`) with Jellyfin's `ExtraType`:

| Silo kind | `ExtraType` |
|---|---|
| `trailer`, `teaser` | `Trailer` |
| `featurette` | `Featurette` |
| `clip` | `Clip` |
| `behind_the_scenes` | `BehindTheScenes` |
| `bloopers` | `Short` |
| `deleted_scene` | `DeletedScene` |
| `other` | `Unknown` |

An extra's `content_id` plays through Silo's usual watch flow, so playing one comes with phase 10. `getIntros` answers empty: Silo plays no intros before a title.

**Local trailers wait for phase 10.** Moonfin's trailer button plays a local trailer before a YouTube one. On Brady's first test the button picked a title's local trailer file, opened the player, and nothing played, since Silo playback is phase 10. Until then `siloLocalTrailersPlayable` is false: `LocalTrailerCount` is 0 and `getLocalTrailers` answers empty, so the button opens the YouTube trailer, and a title with only a local trailer shows no trailer button. Step 10.6 sets it to true (noted there). The mapping itself (`siloExtrasOf`) is tested now. The other extras still show in the extras row.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_extras_test.dart` (new, 3 tests):
  - xXx's YouTube trailer as Emby's `RemoteTrailers` URL, no local extras, no intros;
  - local trailers and special features from extras: counts, order, `ExtraType`, run time, untitled extras named by id, entries without an id skipped; local trailers hidden (count 0, none from `getLocalTrailers`) until phase 10;
  - remote trailer ordering and unknown sites.
- `server_silo`: 408/408 at 6.17; 422/422 with the fix (on top of 6.19).

**Manual test plan**

- A Silo film with a YouTube trailer shows the trailer button; it opens and **plays** the YouTube trailer (as on Emby), also for a film that has a trailer file in its folder.
- A title with local extras in its folder (`Featurettes/`, `Behind The Scenes/`… next to the file) shows them in its extras row with the right labels; local trailer files don't show until phase 10. Playing them comes with phase 10.
- The media bar's trailer preview (if enabled) finds Silo trailers.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | extras 3/3; `server_silo` 408/408; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| 2026-10-14 | macOS | `4b2e921c` | Fail | Brady: the trailer button opened a player that played nothing (it picked the local trailer); media bar not testable without trailers |
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | fix: local trailers hidden until phase 10; extras 3/3; `server_silo` 422/422; analyzer: no issues |
| | | | | |

---

<a id="step-6-18"></a>
## 6.18 Detail-screen media info without starting playback

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 6.17 |

**Goal.** `getPlaybackInfo` built from the versions mapping. It must never call `/playback/start`.

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_playback_api.dart` (new)
- `packages/server_silo/lib/src/silo_media_server_client.dart`
- `lib/util/detail_playback_info.dart` (unchanged: it calls `getPlaybackInfo` with the device profile, which this step answers)

### How it works

Moonfin's detail screen shows how a version would play ("Direct play: yes/no" and the reasons) by asking the server for `PlaybackInfo`, a dry run on Jellyfin and Emby. **Silo has no dry run.** Its only decision is `POST /playback/start`, which opens a session and may start a transcode, so it must never be called to fill a detail page.

`SiloPlaybackApi.getPlaybackInfo` builds the answer from the item's versions instead:

- **Sources.** `getItem` (6.6) gives the `MediaSources` (5.8). The one asked for (`MediaSourceId`) comes first, and the internal track map is left out. No playback request is made, and `PlaySessionId` is null.
- **Direct play is an estimate** from the device profile the detail screen sends (`siloDirectPlayReasons`). A version plays directly when one video direct-play profile takes its container (`mkv` and `matroska` are the same), its video codec and the chosen audio track's codec (`AudioStreamIndex`, else the default track). Otherwise the closest profile names the reasons, as Jellyfin does: `ContainerNotSupported`, `VideoCodecNotSupported`, `AudioCodecNotSupported`. Moonfin's own reason builder adds its client-side checks (Dolby Vision, bitrate) as usual.
- **Silo decides for real** when playback starts (phase 10), with its own codec evidence. The estimate can differ, for example a remux Silo can do where Jellyfin would transcode.

The rest of `PlaybackApi` (start, progress, stop, stream URLs) throws `SiloNotImplementedError` naming its phase 10 step. `SiloPendingPlaybackApi` is removed.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_playback_api_test.dart` (new, 5 tests):
  - The Salt Path built from its versions, 4K first, all direct with a profile that takes them, no track map, **no `/playback` request**;
  - the asked version comes first;
  - reasons when the device can't play it directly, read back by Moonfin's own `PlaybackInfoResult` parser;
  - container aliases, the chosen audio track, an empty profile;
  - the rest of playback names phase 10.
- `server_silo`: 413/413.

**Manual test plan**

- On a Silo film's detail page, the file details show "Direct play: Yes" for a file your Mac plays as is (e.g. H.264/AAC), and "No" with reasons for one it can't (e.g. a DTS track). Switching the audio track in the picker updates it.
- Silo's request log shows **no** `/api/v2/playback/start` while browsing detail pages, and Silo's sessions page shows no session.
- Pressing Play answers with an error until phase 10.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | playback info 5/5; `server_silo` 413/413; analyzer: no issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | full `flutter test` before committing |
| | | | | |

---

<a id="step-6-19"></a>
## 6.19 Display preferences

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 6.18 |

**Goal.** Per-library view settings, stored as decided in DECISIONS.md D3.

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_display_preferences_api.dart` (new)
- `packages/server_silo/lib/src/silo_media_server_client.dart`
- `docs/silo/DECISIONS.md`: D3 decided.
- `docs/silo/phases/17-launch.md`: the car letter-bucket check from 6.11 added to the deferred platform checks.

### How it works

**Decision D3 (Brady, 2026-10-14): local only.** Jellyfin and Emby store per-library view settings (`DisplayPreferences`) on the server. Silo's only comparable setting, `ui.library_page_state`, is its web app's own state for one profile on one device, so writing it would never sync anything across devices and would tie Moonfin to the web app's schema.

Moonfin already keeps these settings in its own preferences: image type, sort and view per library. It only mirrors the image type to the server (`library_browse_view_model`: `_syncImageTypeToServer` / `FromServer`). So `SiloDisplayPreferencesApi` keeps that mirror in memory: a read answers what was saved this session (per id and client name, as on Jellyfin) or an empty set, a save stores it, and **nothing is sent to Silo**. Library view settings therefore persist per device exactly as Moonfin's local preferences do.

`SiloPendingDisplayPreferencesApi` is removed. What remains pending is the session API (phase 3 and 13.6); the client test now checks that one.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_display_preferences_test.dart` (new, 1 test): empty at first, saved prefs read back, separate per id and client name, no request to Silo.
- `silo_media_server_client_test.dart`: the placeholder check now uses `SessionApi`.
- `server_silo`: 414/414.

**Manual test plan**

- In a Silo library, change the image type (poster / thumb / banner), the sort and the view, leave and reopen the library, then restart Moonfin: the choices stick.
- No errors in the log about display preferences, and Silo's request log shows no settings writes when changing them.
- Emby libraries still sync their image type with the server as before.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | display prefs 1/1; `server_silo` 414/414; analyzer: no issues |
| | | | | |

---

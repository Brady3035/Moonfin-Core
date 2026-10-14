# Phase 6: Browsing

[← Roadmap](../ROADMAP.md)

Libraries, grids and detail pages. Each step replaces one placeholder method with the real call.

**Phase done when:** You can open each library, scroll a full grid with artwork, open a movie, a series, its seasons and episodes, and the detail screen looks like it does on Emby.

---

<a id="step-6-1"></a>
## 6.1 Image API on the registry

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | 5.13 |

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
| ☑ Done | — | 6.1 |

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
| ◐ Ready for testing | — | 6.2 |

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
| | | | | |

---

<a id="step-6-4"></a>
## 6.4 Libraries (`UserViewsApi`)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `GET /user/libraries` with caching and `invalidateCache()`.

**Silo v2 endpoints**

- `GET /user/libraries`

**Where in Moonfin**

- `silo_user_views_api.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- From 3.5: with Moonfin open on a library, sign its session out from Silo's sessions page, then open another library. Expected: Moonfin returns to the login screen with your name filled in.
- From 2.7: hide a library and reorder libraries in Moonfin's library settings; Silo's web app shows the same (`ui.disabled_library_ids`, `ui.library_order`). This needs the view `Id` to be Silo's library id.
- From 4.3: with Silo and Emby signed in, a Silo film's detail screen and context menu have no Add to playlist; an Emby film's still do.
- From 4.7: a Silo film's detail screen shows no MDBList/TMDB rating badges and logs no errors; Silo's request log shows no `/Moonfin/` requests.
- Compare with Emby: The library list and order match what Emby shows for the same libraries.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-6-5"></a>
## 6.5 Library grid (`getItems` for a library)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Library id → `library_id`, type filter, sort, page through the cursor pager.

**Silo v2 endpoints**

- `GET /catalog`

**Where in Moonfin**

- `silo_items_api.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Scroll to the end of the largest library; total count is right.
- Carried from 4.2, 4.3 and 5.1: a query for **only** types Silo can't serve (`MusicArtist`, `MusicAlbum`, `Audio`, `Playlist`, `TvChannel`, `mediaTypes=Audio`) answers empty and sends no request; `siloTypesForQuery` returns an empty set for it. Check on Home with only Silo signed in (once Home loads, phase 8): no Continue listening, artist, album or playlist row fills with films or episodes.
- Carried from 5.12 and 5.13: jump with the alphabet bar and scroll back up (window cursor + seek); try every entry of Moonfin's sort menu on a Silo library, both directions. Fields 5.13 leaves unmapped (critic rating, date played, play count…) fall back to Silo's default order; note any that Silo could sort by, and whether `play_count` / `viewed_at` work as `sort` values.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-6-6"></a>
## 6.6 Movie detail (`getItem`)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Item detail with its versions in one call when available.

**Silo v2 endpoints**

- `GET /catalog/items/{id}`
- `GET /catalog/items/{id}/versions`

**Where in Moonfin**

- `silo_items_api.dart`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Compare with Emby: Open the same movie on Emby: overview, cast, ratings, runtime, version badges.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-6-7"></a>
## 6.7 Series detail and seasons

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Series detail and `getSeasons`.

**Silo v2 endpoints**

- `GET /catalog/series/{id}/seasons`

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

<a id="step-6-8"></a>
## 6.8 Season episodes

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `getEpisodes(seasonId)` via `/catalog/items/{season_id}/episodes`; whole-series episodes when no season is given.

**Silo v2 endpoints**

- `GET /catalog/items/{id}/episodes`

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

<a id="step-6-9"></a>
## 6.9 Ancestors

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Synthesise episode → season → series → library for breadcrumbs and back navigation.

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

<a id="step-6-10"></a>
## 6.10 Library filters

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `getQueryFilters` and genre, year and rating filters in `getItems`.

**Silo v2 endpoints**

- `GET /catalog/filters`

**Where in Moonfin**

- `silo_items_api.dart`
- `silo_filters_mapper.dart`
- `lib/data/viewmodels/library_browse_view_model.dart`

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

<a id="step-6-11"></a>
## 6.11 Alphabet jump

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Letter index and `nameStartsWith` through the new letters endpoint.

**Silo v2 endpoints**

- `POST /catalog/letters`

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

<a id="step-6-12"></a>
## 6.12 Genres

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Genre list as synthetic Genre items, and the genre's items.

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

<a id="step-6-13"></a>
## 6.13 Studios and networks

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Same pattern as genres.

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

<a id="step-6-14"></a>
## 6.14 People

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Person detail and filmography.

**Silo v2 endpoints**

- `GET /catalog/people/{id}`
- `GET /catalog (source=person)`

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

<a id="step-6-15"></a>
## 6.15 Collections (browse)

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Personal and library collections as BoxSets, and their items.

**Silo v2 endpoints**

- `GET /collections`
- `GET /collections/{id}/items`
- `GET /library/{id}/collections`

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

<a id="step-6-16"></a>
## 6.16 Similar items

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** "More like this".

**Silo v2 endpoints**

- `GET /recommendations/similar/{id}`

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

<a id="step-6-17"></a>
## 6.17 Trailers and extras

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Local trailers and special features from the item's extras.

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

<a id="step-6-18"></a>
## 6.18 Detail-screen media info without starting playback

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** `getPlaybackInfo` built from the versions mapping. It must never call `/playback/start`.

**Where in Moonfin**

- `silo_playback_api.dart`
- `lib/util/detail_playback_info.dart`

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

<a id="step-6-19"></a>
## 6.19 Display preferences

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Per-library view settings, stored as decided in DECISIONS.md D3.

**Where in Moonfin**

- `silo_display_preferences_api.dart`

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

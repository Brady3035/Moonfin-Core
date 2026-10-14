# Phase 6: Browsing

[← Roadmap](../ROADMAP.md)

Libraries, grids and detail pages. Each step replaces one placeholder method with the real call.

**Phase done when:** You can open each library, scroll a full grid with artwork, open a movie, a series, its seasons and episodes, and the detail screen looks like it does on Emby.

---

<a id="step-6-1"></a>
## 6.1 Image API on the registry

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 5.13 |

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
| | | | | |

---

<a id="step-6-2"></a>
## 6.2 Image cache keyed by path

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Pass a path-only `cacheKey` so the signed query rotating every day doesn't re-download every image.

**Where in Moonfin**

- `packages/cached_network_image_fork/**`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Cold start the next day: artwork shows from cache.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-6-3"></a>
## 6.3 Image registry misses

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** When nothing is registered for an item (cold start, deep link), follow the decision in DECISIONS.md D2 (resolver image provider or placeholder).

**Where in Moonfin**

- `silo_image_api.dart`
- `cached_network_image_fork`

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

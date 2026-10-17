# Phase 9: User actions

[← Roadmap](../ROADMAP.md)

Things a user changes on an item. One action per commit.

**Phase done when:** Each action shows the same result in Silo's web UI.

---

<a id="step-9-1"></a>
## 9.1 Favorite / unfavorite

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Silo v2 endpoints**

- `PUT/DELETE /favorites/{id}`

**Where in Moonfin**

- `silo_user_library_api.dart`

### How it works

`SiloUserLibraryApi.markFavorite` and `unmarkFavorite` send `PUT` and `DELETE /api/v2/favorites/{id}` as the profile the client acts for (`X-Profile-Id`), so each household profile keeps its own favourites, as in Silo's web app. The app's `ItemMutationRepository.setFavorite` already publishes the new `IsFavorite` to `userDataSync`, so the heart flips everywhere the item shows; Silo's favourites list (6.13) reads it back.

- **Retries.** Both are `natural_idempotent` in the contract: adding a favourite twice or removing one that isn't there changes nothing. The Silo client never retries on its own (only a `401` replay after a token refresh, which Silo hadn't acted on), so nothing here depends on that.
- **Only titles.** Silo keeps favourites on catalog titles: films, shows, seasons and episodes, whose Moonfin ids are Silo's content ids. Moonfin makes up ids for what isn't a title (`silo-genre:`, `silo-studio:`, `silo-collection:`, library and person numbers); those fail before any request with an `UnsupportedError` saying so, instead of a 404 from Silo. Moonfin offers the heart on a collection's menu too, so on Silo that entry shows the error (see the follow-up below).
- The placeholder that answered `SiloNotImplementedError` for these two members is gone; played state (9.2) and ratings (9.3) still answer it.

**Follow-up to raise:** the context menu offers *Add to favourites* on a collection (`BoxSet`); Silo has no favourite collections, so on Silo it fails with that message. Hiding it needs a capability the app can ask (left for Brady to decide).

### Testing

**Automated tests** (`packages/server_silo/test/silo_user_library_api_test.dart`, new, 4 tests)

- Marking then unmarking sends `PUT` then `DELETE` to `/favorites/{id}` with `X-Profile-Id`.
- A season and an episode id are titles too.
- Genre, studio, personal and library collection, and library/person ids throw `UnsupportedError` without a request.
- Silo's refusal (404) reaches the caller.
- `silo_items_api_detail_test.dart`: the not-implemented check moves to `markPlayed` (9.2).

**Manual test plan**

- In Moonfin, favourite a film from its detail page; in Silo's web app (same profile) it shows as a favourite. Unfavourite it in Moonfin; Silo's web app shows it gone.
- Favourite a show and an episode from the context menu; both appear in Silo's favourites and in Moonfin's Favourites row (Home) and library *Favorites* filter.
- Switch to another household profile: its favourites are its own.
- Favourite something in Silo's web app; reopen its detail page in Moonfin: the heart is filled.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-16 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | favourites 4/4; `server_silo` 508/508; analyzer: no issues. Full app suite left to Brady |
| | | | | |

---

<a id="step-9-2"></a>
## 9.2 Mark played / unplayed

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Goal.** Items, seasons and series.

**Silo v2 endpoints**

- `POST/DELETE /watched/{id}`

**Where in Moonfin**

- `silo_user_library_api.dart`

### How it works

`SiloUserLibraryApi.markPlayed` sends `POST /api/v2/watched/{id}` and `unmarkPlayed` sends `DELETE`, as the acting profile. On Silo a film or episode marked watched has its resume point set to 0 (as Jellyfin does), and a season or show marks or clears every episode (server `MarkWatched`, `user_watch_progress`). Unmarking also hides the item's history up to now, which is what Silo's web app's "Mark unwatched" does. Season ids are Silo's own (`season-…`), so seasons need no translation. `ItemMutationRepository.setPlayed` already publishes `Played`, a cleared `PlayedPercentage` and position 0.

- **Not retried.** Silo flags both `non_retryable`: a second send would add a second history entry or move the history cutoff. The Silo client has no automatic retry (only a `401` replay, for a request Silo refused before acting), so each call goes out once. Moonfin's offline queue (`sync_service.dart`) only replays a mark made while offline, which never reached the server.
- Ids that aren't titles (collections, genres…) fail before a request, as in 9.1.

### Testing

**Automated tests** (`silo_user_library_api_test.dart`, 3 more)

- A film and a season marked, a show unmarked: `POST`, `POST`, `DELETE` on `/watched/{id}`, in order, once each.
- A 503 reaches the caller after one request (no retry).
- A collection id throws `UnsupportedError`.

**Manual test plan**

- Mark an unwatched film watched in Moonfin (context menu); Silo's web app shows it watched. Mark it unwatched; Silo shows it unwatched.
- A film part way through: mark it watched; it leaves Continue Watching (in Moonfin after Home reloads; see 9.4) and in Silo.
- Mark a whole season watched from the season's menu: every episode shows watched in Moonfin and Silo; the show's unwatched count drops. Mark the show unwatched: every episode is unwatched again.
- From an episode's menu, mark watched; the next episode becomes Next Up in Silo's web app.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-16 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | played state 3/3; `server_silo` 511/511; analyzer: no issues. Full app suite left to Brady |
| | | | | |

---

<a id="step-9-3"></a>
## 9.3 Ratings

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Like and numeric ratings mapped onto Silo's rating scale.

**Silo v2 endpoints**

- `PUT/DELETE /ratings/{id}`
- The detail's `user_rating` (read back)

**Where in Moonfin**

- `silo_user_library_api.dart`
- `silo_item_mapper.dart` (`UserData.Rating`)

### How it works

Silo's personal rating is whole stars, 1 to 5 (`RatingSet.rating`, server table `user_ratings`), one per profile. Moonfin's is out of 10: the star style shows half stars (`rating / 2`), the numeric style the number, and the thumbs style reads `Likes`, or a `Rating` of 6.5 or more as liked (`AggregatedItem.likedRatingThreshold`).

- **Writing.** `updateNumericUserRating` sends `PUT /api/v2/ratings/{id}` with `{"rating": stars}`, where stars is the rating halved and rounded, half a star up (`siloStarsFromRating`: 7 → 4, 8 → 4, 10 → 5), and at least 1 (Silo's lowest; Moonfin can send 0). `updateUserRating` (thumbs) sends 5 stars for up and 1 for down. `deleteUserRating` sends `DELETE`.
- **Reading.** An item's detail carries `user_rating` (the acting profile's stars); the mapper turns it into `UserData.Rating` out of 10 (4 stars → 8). There is no `Likes`, so thumbs follow the rating: 4 and 5 stars show as liked, 1 to 3 as disliked. Cards in lists carry no rating, as with Emby, so the rating shows on the detail page.
- **Half stars** aren't kept: 3½ stars is saved as 4 and shows as 4 after a reload. `supportsNumericUserRatings` stays true so the star and numeric styles remain on offer; Silo's own web app rates in whole stars.
- **Not retried.** Both writes are `non_retryable` in the contract (a repeat moves the rating time and refreshes recommendations again); the client sends each once, as in 9.2.
- `GET /capabilities/ratings` (listed in the plan) turned out to be about the external rating sources (IMDb, TMDB, Rotten Tomatoes) a title page shows, not personal ratings, so it isn't needed here.
- The last `SiloNotImplementedError` placeholder in `SiloUserLibraryApi` is gone.

### Testing

**Automated tests** (`silo_user_library_api_test.dart`, 4 more)

- Thumbs up sends `{"rating":5}`, down `{"rating":1}`.
- 8 → 4 stars, 7 → 4 (half up); 10 → 5, 1 and 0 → 1, 12 → 5.
- Clearing sends `DELETE`.
- `user_rating: 4` maps to `Rating` 8.0; without it, no `Rating` and no `Likes`.
- `silo_items_api_detail_test.dart`: the not-implemented check is gone (nothing in `UserLibraryApi` is pending now).

**Manual test plan**

- Settings → personal rating style *Stars*: rate a film 4 stars on its detail page; Silo's web app shows 4 stars for that profile. Change it to 2½ stars: Silo shows 3; reopen the detail page in Moonfin: 3 stars. Clear the rating: Silo shows none.
- Style *Thumbs*: thumbs up a film; Silo shows 5 stars and Moonfin keeps the thumbs up after a reload. Thumbs down: Silo shows 1 star.
- Rate a film in Silo's web app; open it in Moonfin: the rating shows (stars, or a thumb).
- Another profile sees its own rating, not this one.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-16 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | ratings 4/4; `server_silo` 515/515; analyzer: no issues. Full app suite left to Brady |
| | | | | |

---

<a id="step-9-4"></a>
## 9.4 Refresh rows after a change

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Publish a local user-data change so rows update without a reload.

**Where in Moonfin**

- `silo_user_library_api.dart`
- `lib/data/services/user_data_sync.dart`

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

<a id="step-9-5"></a>
## 9.5 Personal collections: create, add, remove

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Silo v2 endpoints**

- `POST /collections`
- `PUT/DELETE /collections/{id}/items/{item_id}`

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

<a id="step-9-6"></a>
## 9.6 Watchlist *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Silo's watchlist as a context action and row.

**Silo v2 endpoints**

- `PUT/DELETE /watchlist/{item_id}`
- `GET /watchlist`

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

<a id="step-9-7"></a>
## 9.7 Hide from Continue Watching and Next Up

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | 8.1, 8.2 |

**Goal.** On Silo, Moonfin's "Hide from Continue Watching" context action (today a local, per-device list in `UserPreferences`) uses Silo's dismissals, so the card is hidden in Silo's web app and on other devices too. Silo drops a dismissed episode's or series' whole show from both Continue Watching and Next Up until the profile watches it again, and "show again" undoes it. Moonfin's local list already unhides when the item is played, so the behaviour lines up.

**Silo v2 endpoints**

- `PUT /home/dismissals/{surface}/{item_id}` (`surface`: `continue_watching` or `next_up`)
- `DELETE /home/dismissals/{surface}/{item_id}`

**Where in Moonfin**

- `lib/ui/widgets/focus/context_action.dart`
- `lib/preference/user_preferences.dart` (`hideFromContinueWatching`)

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Hide a show from Continue Watching in Moonfin; it disappears in Silo's web app. Watch it again; it comes back in both.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

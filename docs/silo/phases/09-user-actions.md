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
| ☑ Done | — | previous step |

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
| ☑ Done | — | previous step |

**Goal.** Publish a local user-data change so rows update without a reload.

**Where in Moonfin**

- `silo_user_library_api.dart`, `silo_items_api.dart` (`noteUserDataChanged`, `userDataMayHaveChanged`)
- `lib/data/services/user_data_sync.dart`
- `packages/server_core/lib/src/api/user_data_refresh_scope.dart` (new)

### How it works

The publishing half was already there for every server: `ItemMutationRepository` publishes each change to `userDataSync`, Home and the grids patch the cards they hold (the heart, the tick, the progress bar), and Home reloads its rows when it comes back into view. Two things kept that from working on Silo.

**1. Silo-side caches.** The Silo client keeps a few reads so rows loading together don't each ask Silo: Home's and the libraries' sections (Continue Watching, Next Up and Silo's own rows) for 5 s, the read-once lists (series status, random, last played) for 2 min, the runtime counts, and the pager's cursors and pages. A row reloaded right after a change could come back from those unchanged (a film marked watched still in Continue Watching). Every write in `SiloUserLibraryApi` now calls `SiloItemsApi.noteUserDataChanged(id)` once Silo has accepted it, which forgets all of them. A failed write forgets nothing.

**2. Refreshing user data one item at a time.** After a change, coming back to a grid or a detail page calls `userDataSync.refreshFromServer` with every item it holds, to pick up what the change did to parents (a show's unwatched count). Jellyfin and Emby answer that with one request per hundred ids. Silo has no batch read, so `getItems(ids:)` reads each item's detail: a library grid scrolled to 300 titles was 300 reads after any tap. A new optional `server_core` interface, `UserDataRefreshScope`, lets the items API narrow the list (`itemsApi is UserDataRefreshScope`, as with `LetterPositionApi`); servers without it get every id, as before. Silo's answer, `userDataMayHaveChanged`, keeps:

- an item this client changed in the last 10 minutes;
- every series, season and episode of a show that had anything changed (an episode's play moves its season's and show's counts; a show marked watched marks every episode).

Changes made on another device or in Silo's web app aren't seen this way; Jellyfin learns those from its socket, and Silo's live events are phase 13. Until then they show when a screen reloads.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_user_data_refresh_test.dart` (new, 6 tests): nothing changed → nothing to read again; an episode marked → its show, season and both its episodes, not another show's or a film; a favourite film → that film; a failed write → nothing; remembered 9 minutes, not 11; Continue Watching, read twice within 5 s, is read again after a change. `server_silo` 521/521.
- `test/data/services/user_data_sync_test.dart` (1 more): a server that narrows the refresh is asked only about what it keeps, and not at all when it keeps nothing.
- `server_core` 94/94.

**Manual test plan**

- From Home, mark a film in Continue Watching watched (context menu): the card shows watched at once; leave Home and come back (or pull to refresh): the card is gone, as on Silo's web app.
- On a show's detail page, mark one episode watched; go back to the TV library grid: the show's unwatched count went down by one, without waiting.
- Scroll a film library a few pages, open a film, favourite it, go back: the heart shows on that card, and the grid doesn't stall (it now reads one item, not every loaded one).
- Favourite a film in Silo's web app: Moonfin shows it once the screen reloads (not live; phase 13).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-16 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | refresh scope 6/6; `user_data_sync_test.dart` 19/19; `server_silo` 521/521; `server_core` 94/94; analyzer: no issues. Full app suite left to Brady |
| | | | | |

---

<a id="step-9-5"></a>
## 9.5 Personal collections: create, add, remove

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Silo v2 endpoints**

- `GET /collections` (the profile's own and shared collections)
- `POST /collections`
- `PUT/DELETE /collections/{id}/items/{item_id}`

**Where in Moonfin**

- `silo_items_api.dart` (`createCollection`, `addToCollection`, `removeFromCollection`, `getEditableCollections`, `canEditCollection`)
- `packages/server_core/lib/src/api/editable_collections_api.dart` (new)
- `lib/ui/widgets/add_to_collection_dialog.dart`, `lib/data/viewmodels/item_detail_view_model.dart` (`canRemoveFromCollection`) and the three collection pages that build the removal entry (`item_detail_screen.dart`, `modern_detail_content.dart`, `nouveau_collection_section.dart`)

### How it works

**Which collections can be edited.** Jellyfin lets a user with collection rights edit any collection, so Moonfin's "Add to collection" lists every `BoxSet` and every collection page offers "Remove from collection". On Silo a profile edits only **its own manual** collections: a library's collections are the administrator's, another profile's shared collection is read-only, and smart and imported ones (MDBList, TMDB, Trakt) fill themselves. That is the rule Silo's web app applies (`AddToCollectionDialog.tsx`: `collection_type === "manual"` and created by the acting profile), and since 8.6 `getItems([BoxSet])` lists all of them, so the dialog would have offered collections Silo refuses.

A new optional `server_core` interface, `EditableCollectionsApi`, lets the app ask (`itemsApi is EditableCollectionsApi`, as with `LetterPositionApi`; Jellyfin and Emby don't implement it and behave as before):

- `getEditableCollections()`: the add dialog lists these instead of every `BoxSet`. Silo's answer is `GET /collections` kept to the profile's own manual ones, by name. While the acting profile isn't known nothing is listed, as on Silo's web app.
- `canEditCollection(collection)`: `ItemDetailViewModel.canRemoveFromCollection` asks it with the collection page's item, and the three collection pages only pass a `CollectionRemovalContext` (the "Remove from collection" entry) when it says yes. Silo checks the mapped collection's original (`_silo`): a personal id, `collection_type` `manual`, `creator_profile_id` the acting profile (`SiloItemsApi` now gets the client's profile id).

**Writing.**

- `createCollection` sends `POST /collections` with the name and `collection_type: manual` (private to the profile, Silo's default) and answers the new collection as a `BoxSet`, whose `Id` the dialog reads; given `itemIds`, it adds them. Silo marks this `non_retryable` (a repeat makes a second collection); it is sent once.
- `addToCollection` sends `PUT /collections/{id}/items/{item_id}` with `{"position": 0}` per title, in turn, as Silo's web app does (a title already in the collection keeps its place). `removeFromCollection` sends `DELETE`. Silo has no batch change; the first refusal stops the rest.
- A library collection's id (`silo-libcollection:`) is refused before any request.
- Each change calls `noteUserDataChanged()` (9.4) so the collection's page reads Silo again.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_collection_edit_test.dart` (new, 7 tests): only own manual collections are editable, by name (smart, imported and another profile's are not); a library collection never is; nothing while the profile is unknown; create sends the name and `manual` and adds the titles at position 0, answering `silo-collection:c7`; add and remove send one request per title in order; a 409 stops the rest; a library collection is refused without a request.
- `silo_items_api_library_test.dart`: the not-implemented check moves to `getMediaSegments` (11.1).
- `test/viewmodels/item_detail_remove_from_collection_test.dart` (2 more): a server without the interface offers removal on any collection page; one with it decides per collection, given the collection's item.
- `server_silo` 528/528; analyzer: no errors or warnings in the changed app files (upstream's infos only).

**Manual test plan**

- From a film's menu, *Add to collection*: the list shows only your own manual collections (not the library's collections from the Collections row, not smart or imported ones, not another profile's shared ones). Pick one; Silo's web app shows the film in it.
- *Add to collection* → create "Test 9.5": Silo's web app shows a new private manual collection with the film in it.
- Open your own collection in Moonfin; a card's menu offers *Remove from collection*; remove it: the card leaves, and Silo's web app agrees.
- Open a library's collection (Home's Collections row) or another profile's shared one: card menus don't offer *Remove from collection*.
- Switch profile: the dialog lists that profile's own collections.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-16 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | collection editing 7/7; removal view model 7/7 and context action tests; `server_silo` 528/528; analyzer: no new issues. Full app suite left to Brady |
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

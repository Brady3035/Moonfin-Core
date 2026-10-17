# Phase 9: User actions

[← Roadmap](../ROADMAP.md)

Things a user changes on an item. One action per commit.

**Phase done when:** Each action shows the same result in Silo's web UI.

---

<a id="step-9-1"></a>
## 9.1 Favorite / unfavorite

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

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
| ☐ Not started | — | previous step |

**Goal.** Items, seasons and series.

**Silo v2 endpoints**

- `POST/DELETE /watched/{id}`

**Where in Moonfin**

- `silo_user_library_api.dart`

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

<a id="step-9-3"></a>
## 9.3 Ratings

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Like and numeric ratings mapped onto Silo's rating scale.

**Silo v2 endpoints**

- `GET /capabilities/ratings`
- `PUT/DELETE /ratings/{id}`

**Where in Moonfin**

- `silo_user_library_api.dart`

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

# Phase 7: Search

[← Roadmap](../ROADMAP.md)

Search screens on Silo.

**Phase done when:** Search returns movies, series, episodes and people like it does on Emby.

---

<a id="step-7-1"></a>
## 7.1 Title search

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `28b84a0`, fixture `618df11` | previous step |

**Goal.** `searchTerm` → catalog `q`, honouring the search capabilities.

**Silo v2 endpoints**

- `GET /catalog?q=`
- `GET /catalog/search/capabilities`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`: `getItems(searchTerm:)`, `searchCapabilities()`, `SiloSearchCapabilities`.
- `packages/server_silo/lib/src/mappers/silo_item_types.dart`: `siloSearchScopeFor`.
- `scripts/silo_probe.sh`, `packages/server_silo/test/fixtures/silo/catalog_search.json`: a search that finds something.

### How it works

Before this step `getItems` ignored `searchTerm`, so a search on Silo answered the unfiltered catalog. Moonfin's search screen (`SearchRepository`) asks `getItems` three ways:

- **suggestions** while typing: `includeItemTypes: [Movie, Series, Person]`, 5 results;
- **the search screen**: no types and 240 results, grouped into Movies, Series, Episodes… by `Type` in the view model;
- **a library-scoped search** (book libraries): one request per group with its type and the library as `parentId`.

On Silo:

- **`searchTerm` → `q`**, trimmed; a blank term is a plain browse. `q` is a query parameter like any other, so it is part of the pager's signature (5.12) and two searches never share cursors.
- **Relevance order.** With `q` and no `sort`, Silo ranks by relevance (its default for a text search). Moonfin's searches ask no sort, so none is sent. A caller that asks for one keeps it (Silo accepts any sort with `q`).
- **Capabilities first.** A search reads `GET /catalog/search/capabilities` once (kept ten minutes). When it says search is not `available` or not `allowed` for this profile, the search answers empty **without a request**. When the document can't be read (an error, an older server) the search goes ahead without the optional scope below, and the document is read again next time.
- **Movies, series and episodes in one list.** Silo keeps episodes apart from films and series; only a text search can mix them, through the search-only scope `type=video_with_episodes`, offered when the capabilities say `video_with_episodes_scope`. `siloSearchScopeFor` uses it for the search screen (no type, while Moonfin shows only video) and for a type list that mixes episodes with films or series. Other lists use the browse scope (5.1): `[Movie, Series]` → `video`, `[Episode]` → `episode`. Without the capability, a search with no type is unscoped and Moonfin keeps the types it can show.
- **Mapping.** Search results are ordinary catalog cards (5.x mappers). An episode card carries `series_id`, `series_title`, `season_number` and `episode_number`, so it arrives with `SeriesId`, `SeriesName`, `ParentIndexNumber` and `IndexNumber` like Emby's. Types Moonfin can't show (podcasts, and books until phase 16) are dropped, and so is anything the asked types don't include (`video_with_episodes` returns series for a `[Movie, Episode]` search).
- **No people yet.** `Person` in the suggestion types matches no Silo type and is left out of the request. People come from their own endpoint in 7.2.
- **The jump bar** (6.11) is not offered on a search: a query with `q` is not remembered for `letterPosition`.
- **Paging.** The search screen's 240 results are three requests of 100 through the pager. Moonfin never pages a search further. A Meilisearch server bounds how far a ranking can be paged (`result_window_limit`, at least hundreds) and expires it (`session_ttl_seconds`); an expired cursor is retried from the start by the pager.
- **Callers by provider id.** The home screen and Seerr pages search by an IMDb or TMDB id to find a local copy. On Silo those now find nothing, instead of the first titles of the catalog.

**Not covered here:** Silo's search has no seasons and no collections, so Moonfin's Seasons and Collections groups stay empty on Silo (Emby lists both). Collections are listed whole whatever the `searchTerm` (6.15); the add-to-collection dialog that searches them by name comes with 9.5.

The old `silo/catalog_search.json` capture searched for "the", which Silo's PostgreSQL search treats as a stop word, so it held no items. The probe now searches for `SILO_SEARCH` (default "justice") with `type=video_with_episodes`. The step was built against a hand-written fixture; Brady's capture after testing (Silo `bd9d59ea`: a film and four "Justice" episodes, 118 results) replaced it and confirmed the episode card fields (`series_id`, `series_title`, `season_number`, `episode_number`). The probe script is now executable (`chmod +x`); before, it had to be run with `bash`.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_search_test.dart` (new, 16 tests):
  - the search screen: `q` trimmed, `type=video_with_episodes`, no `sort`; series and episodes mapped with their series fields; the podcast dropped; Silo's total;
  - capabilities read once for several searches;
  - suggestions: `type=video`, people left out;
  - per-type groups: `[Episode]` → `episode`; `[Movie, Episode]` → `video_with_episodes` without the series;
  - without `video_with_episodes_scope`: unscoped, unsupported types dropped;
  - no request when the capabilities say not allowed, disabled or not configured;
  - an unreadable capabilities document doesn't block search, and is read again;
  - a blank term is a plain browse, with no capabilities read;
  - a search for types Silo lacks (a book library) sends nothing;
  - a search inside a library: `library_id` and `q`, an asked-for sort kept, no letter position;
  - two searches page separately;
  - `siloSearchScopeFor` with and without the capability; the capabilities document.
- `server_silo`: 442/442; 449/449 with the real capture (on top of 7.2).

**Manual test plan**

Search for the same words on Silo and on Emby (same library on both):

- **A title word** (e.g. "justice"): Movies, Series and Episodes groups fill in; results look like Emby's for the same query (Emby may also list seasons and collections; Silo has neither in search).
- **An episode title** (e.g. "Independence Day" from Young Justice): the episode appears under Episodes with its series name and SxEy, its still, and opens the episode page. Play stays phase 10.
- **Suggestions while typing**: the dropdown suggests film and series titles (no person names yet: 7.2).
- **Open results**: a film opens its detail page, a series its series page with seasons.
- **Nothing found** (e.g. "zzzzqx"): "no results", not the start of the catalog.
- **A stop word alone** ("the"): Silo finds nothing, as its search ignores stop words. Note what Emby shows.
- **Typing fast** ("j", "ju", "jus"…): no errors; the final results match the final text.
- **Emby unchanged**: the same searches on Emby as before.
- With both servers signed in, a search shows each server's results (server names on the cards).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | search 16/16; `server_silo` 442/442; analyzer: no issues |
| 2026-10-15 | macOS | `bd9d59ea` | Pass | Brady: every check passed. "the" alone shows only people: Silo's title search drops the stop word, its people search matches names with a word starting "the" |
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | real search capture: search tests on the film and four episodes; `server_silo` 449/449; analyzer: no issues |
| | | | | |

---

<a id="step-7-2"></a>
## 7.2 People search

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `290e1b9`, fixture `ada37e7` | 7.1 |

**Goal.** Person results.

**Silo v2 endpoints**

- `GET /catalog/people?q=`
- `GET /catalog/search/capabilities` (read in 7.1)

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_items_api.dart`: `getPersons`.
- `scripts/silo_probe.sh`, `packages/server_silo/test/fixtures/silo/people_search.json`.

### How it works

People don't come back from Moonfin's item search on Jellyfin either: `SearchRepository.searchPeople` asks `ItemsApi.getPersons(searchTerm, limit: 24)` and the search screen fills its People group with the answer (waiting a moment for it, 10 seconds at most). The movie detail page also uses it to find the local person behind a Seerr cast member, by matching `ProviderIds.Tmdb`.

On Silo `getPersons` (until now `SiloNotImplementedError` naming 7.2) calls `GET /catalog/people`:

- **`q`**: the trimmed term. Silo matches each word against the start of a word of the name, ignoring case, and lists exact matches first. A blank term sends no `q` and lists the first people, as Jellyfin does.
- **`media_scope`**: limits people to credits the profile can see in that scope. Moonfin shows video, so it asks `video_with_episodes` (films, series and episodes, so guest stars are found) when the capabilities have `video_with_episodes_scope`, else `video`, and nothing when they lack `people_media_scope`. Without a scope Silo would also return audiobook narrators and authors.
- **The capabilities** gate it like 7.1: when search isn't available or allowed for the profile, the answer is empty and no request is made.
- **`limit`**: capped at Silo's 100; none leaves Silo's default (20). `fields` and `enableImageTypes` are ignored: Silo's person is always whole.
- **Mapping**: each person goes through `siloPersonToBaseItemDto` (6.14), so a result is a Jellyfin `Person` with `ProviderIds` and its photo registered, and opening it shows the person page from 6.14 (photo, biography, filmography). Entries without an id are skipped. The total is the number returned (Silo's people search has no total).

**Ranking is Silo's.** Silo matches each word against word starts, as documented, but lists the matches by name: "vin" gives Alex Vincent, Allen Vincent… and Vin Diesel only once his last name is typed, and "chris" isn't led by people named Chris. Silo's web search behaves the same. This is an improvement to raise with Silo (rank exact word matches first), not something Moonfin reorders: it only sees the first page.

**Not covered here:** Moonfin's suggestion list asks `getItems` for `[Movie, Series, Person]`. Silo's catalog has no person items, so on Silo suggestions list titles only. Adding the people search to suggestions would mean a Silo-specific second call from the app's `SearchRepository`; Brady decided to leave it (2026-10-15). The same goes for the book author lookup in `item_detail_screen.dart` (`getItems(includeItemTypes: [Person])`), which comes with books in phase 16.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_items_api_people_search_test.dart` (new, 7 tests):
  - people by name: `q` trimmed, `limit`, `media_scope=video_with_episodes`; names, `Person` type, TMDB id, registered photo, no photo for a person without one;
  - `media_scope` from the capabilities (`video`, or none);
  - `limit` capped at 100, or left out;
  - a blank term sends no `q`;
  - no request when search isn't allowed;
  - entries without an id skipped;
  - errors reach the caller (the view model drops the People group then).
- `silo_items_api_library_test.dart`: `getPersons` no longer names a later step.
- The step was built against a hand-written fixture; Brady's capture after testing (Silo `bd9d59ea`, "Vin") replaced it, and the first test now checks the real five people.
- `server_silo`: 449/449. App search tests (view model, late people, multi-server, library jump search): 89/89.

**Manual test plan**

Same searches on Silo and on Emby:

- **An actor's name** (e.g. "vin" or "Vin Diesel"): a People group with round photos; the exact name comes first. Compare with Emby's People group.
- **A first name shared by several people** (e.g. "chris"): several people; only people with credits in films or series show.
- **A guest star** known only from an episode: found on Silo (episodes scope).
- **Open a person**: their page shows photo, biography and filmography (6.14); titles open.
- **A title-only search** (e.g. "justice"): no People group, or people named Justice only.
- **Seerr person** (if Seerr is set up): a person page opened from Seerr, for someone who is also on the Silo server, shows the local person's details and filmography (found through `ProviderIds.Tmdb`).
- **Emby unchanged**: the People group on Emby as before.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | people search 7/7; `server_silo` 449/449; app search tests 89/89; analyzer: no issues |
| 2026-10-15 | macOS | `bd9d59ea` | Pass | Brady: people listed, photos, person pages, Seerr person, Emby all pass. Silo note: "vin" doesn't bring up Vin Diesel until his last name is typed, and "chris" isn't led by people named Chris; Silo's web search does the same (raise with Silo, see How it works) |
| 2026-10-15 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | real people capture; people search 7/7; `server_silo` 449/449; analyzer: no issues |
| | | | | |

---

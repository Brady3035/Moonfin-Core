# Phase 7: Search

[← Roadmap](../ROADMAP.md)

Search screens on Silo.

**Phase done when:** Search returns movies, series, episodes and people like it does on Emby.

---

<a id="step-7-1"></a>
## 7.1 Title search

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

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

The old `silo/catalog_search.json` capture searched for "the", which Silo's PostgreSQL search treats as a stop word, so it held no items. The fixture is rebuilt by hand from the real Young Justice cards (see the fixtures README) and the probe now searches for `SILO_SEARCH` (default "justice") with `type=video_with_episodes`.

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
- `server_silo`: 442/442.

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
| | | | | |

---

<a id="step-7-2"></a>
## 7.2 People search

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Person results.

**Silo v2 endpoints**

- `GET /catalog/people?q=`

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

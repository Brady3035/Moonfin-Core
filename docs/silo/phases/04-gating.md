# Phase 4: Hide what Silo doesn't have

[← Roadmap](../ROADMAP.md)

Silo never serves Live TV, music, playlists, instant mix or Jellyfin admin, and has no Moonfin server plugin. Hide each entry point instead of letting it fail. One area per commit.

**Phase done when:** With a Silo user active, no menu, row, tab or button leads to an error caused by a missing feature.

---

<a id="step-4-1"></a>
## 4.1 Hide Live TV

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `4645ebe` | 3.7 |

**Goal.** Tab, home rows and guide entry points via `supportsLiveTv`.

**Where in Moonfin**

- `lib/util/signed_in_server_features.dart` (new)
- `lib/ui/screens/settings/home_sections_screen.dart`
- `lib/ui/screens/settings/home_rows_image_type_screen.dart`
- `lib/ui/screens/settings/settings_side_panel.dart` (import only) and its parts in `panel/`: `navigation_category_screen.dart`, `bottom_nav_tabs_screen.dart`, `quality_decoding_screen.dart`, `settings_search_index.dart`

### How it works

**What was already hidden.** Checking every Live TV entry point with a Silo user showed that the tab, the sidebar and toolbar buttons and the home rows were already hidden, and that nothing errors:
- the tab and the sidebar and toolbar buttons appear only when a server has a Live TV library (`isLiveTvLibrary`), and Silo never lists one;
- the Live TV, On Now and Favourite channels home rows load only when the server has channels (`RowDataSource.hasLiveTvChannels`). `SiloLiveTvApi` (phase 1) answers every read with an empty list without touching the network, so they never appear;
- with Silo and Emby both signed in, Emby's Live TV library brings the tab and rows back, which is right.

So no screen or row needed gating. What a Silo-only user still saw was **settings that can do nothing**: "Show Live TV button", Live TV in the bottom navbar's tab picker, "Live TV direct play", the Live TV and Active recordings Home sections, their entries in Home rows image type, and the settings search results for these. Brady chose to hide those too.

**When a setting is hidden.** These settings apply to every server, not to the one in use, so they are hidden only when **no signed-in server** supports Live TV. A new helper answers that:
- `anySignedInServerSupports(feature)` reads the stored servers that have a signed-in user and asks `FeatureDetector` for each server type. It never touches the network.
- With no signed-in server at all it answers true, so nothing is hidden before sign-in.
- `liveTvOnAnySignedInServer()` is the Live TV case. Later phase 4 steps (music, playlists) will reuse the general form.

**Where it applies:**
- Navigation settings: the "Show Live TV button" switch.
- Bottom navbar tabs: Live TV is no longer offered to pin. A Live TV pin synced from another device stays in the pinned list (marked off as before) so it can be removed.
- Quality & decoding: "Live TV direct play".
- Home sections: the Live TV and Active recordings sections join the screen's other visibility gates (`_isHiddenByRowVisibilityGates`). Their saved on/off state is untouched, so signing in to an Emby server later brings them back as they were.
- Home rows image type: those two sections aren't listed.
- Settings search: the two Live TV settings aren't indexed, so a search can't lead to a hidden setting.

Kids Mode's own Live TV hiding is unchanged.

### Testing

**Automated tests**

- `test/util/signed_in_server_features_test.dart` (new, 7 tests): no servers hides nothing; Silo alone lacks Live TV; Silo plus Emby or Jellyfin has it; a server with no signed-in user doesn't count; nobody signed in anywhere hides nothing.
- Existing: `test/preference` and `test/ui/widgets/bottom_nav` (117) still pass.

**Manual test plan**

Setup: sign out of Emby so only Silo is signed in (or use a fresh install signed in to Silo only).

1. **No Live TV anywhere.** No Live TV tab, sidebar or toolbar button, and no Live TV row on Home.
2. **Settings.** Navigation has no "Show Live TV button". Quality & decoding has no "Live TV direct play". Home sections has no Live TV or Active recordings. Searching settings for "live tv" finds neither setting.
3. **Mobile bottom navbar** (iOS or Android phone, if handy): the tab picker doesn't offer Live TV.
4. **Compare with Emby.** Sign in to Emby as well: all of the above come back, and Emby's Live TV tab and rows show as before. Sign out of Emby again: the settings disappear again.
5. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | new test 7/7; `test/preference` + `test/ui/widgets/bottom_nav` 117/117; analyzer: no new issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | tests 1, 2, 4, 5 pass. Test 3 (phone bottom navbar) deferred to 17.5 |
| | | | | |

---

<a id="step-4-2"></a>
## 4.2 Hide music, instant mix and lyrics

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | `d4cfe27` | 4.1 |

**Goal.** Music libraries, artist/album rows, instant mix actions, lyrics.

**Where in Moonfin**

- `lib/util/signed_in_server_features.dart`
- `lib/ui/screens/settings/home_row_toggles_screen.dart`
- `lib/ui/screens/settings/home_sections_screen.dart`
- `lib/ui/screens/settings/home_rows_image_type_screen.dart`
- `lib/ui/screens/settings/panel/detail_sections_screen.dart`
- `lib/ui/screens/settings/panel/settings_search_index.dart`

### How it works

Same approach as 4.1: check what is already hidden, then hide the settings that can do nothing.

**Already hidden by data:**
- **Music libraries.** Silo's libraries are only `movies` and `series`, so no music library ever appears.
- **Instant mix.** It is offered only from the audio player, and Silo never plays audio. `SiloInstantMixApi` answers empty anyway.
- **Lyrics.** The detail screen shows them only when an item has lyrics, and a Silo item never does. The player's lyrics view is part of the audio player.
- **Music rows** (Continue listening, artists, albums, audio playlists, music favourites). These ask the items API for music types (`MusicArtist`, `MusicAlbum`, `Audio`, `mediaTypes=Audio`). For Silo that API is still a placeholder until phase 5. They stay empty as long as Silo's items translation answers a query for types Silo doesn't have with an empty result, instead of ignoring the filter. That belongs with 5.1's reverse type map (see the note in `HANDOFF.md`).

**Hidden by this step**, when no signed-in server has music (`musicOnAnySignedInServer()`, the 4.1 helper with `FeatureDetector.supportsMusic`):
- Home rows: the whole Audio group ("Display audio rows" and its sorting options).
- Home sections: Continue listening, Artists, Albums, Audio playlists, and the music favourites (artists, albums, songs, music videos). Their saved on/off state is untouched.
- Home rows image type: the same sections.
- Detail sections: Lyrics.
- Settings search: "Display audio rows".

**Why `supportsMusic` and not `supportsLyrics`.** `supportsLyrics` is already false for Emby, so gating the Lyrics section on it would hide it for Emby users too. No music means no lyrics, so `supportsMusic` is the right test and Emby is unchanged.

Audio *track* settings (passthrough, downmix, audio language) are about video soundtracks and stay.

### Testing

**Automated tests**

- `test/util/signed_in_server_features_test.dart`: one new test (music: off with Silo alone, on once Jellyfin is signed in), 8/8.
- Existing: `test/preference` and `test/ui/widgets/bottom_nav` still pass.

**Manual test plan**

Setup: only Silo signed in.

1. **Home rows** (Settings › Home): no Audio group.
2. **Home sections:** no Continue listening, Artists, Albums, Audio playlists, or favourite artists, albums, songs or music videos.
3. **Home rows image type:** none of those sections listed.
4. **Detail sections** (classic detail style): no Lyrics.
5. **Search settings** for "music" or "audio rows": no "Display audio rows".
6. **Compare with Emby.** Sign in to Emby as well: all of the above come back, and Emby's music rows and lyrics show as before. Sign out of Emby: hidden again.
7. Regression: full `flutter test`.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | helper tests 8/8; with `test/preference` and `test/ui/widgets/bottom_nav`: 165/165; analyzer: no new issues |
| 2026-10-14 | macOS | `4b2e921c` | Pass | Brady tested before committing. The music rows' type filter is checked in 5.1 |
| | | | | |

---

<a id="step-4-3"></a>
## 4.3 Hide playlists

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | 4.2 |

**Goal.** "Add to playlist", playlist rows and screens via `supportsPlaylists`.

**Where in Moonfin**

- `lib/util/signed_in_server_features.dart`
- `lib/ui/widgets/focus/context_action.dart`
- `lib/ui/screens/detail/detail_buttons.dart`
- `lib/ui/screens/detail/item_detail_screen.dart`
- `lib/ui/screens/settings/home_row_toggles_screen.dart`, `home_sections_screen.dart`, `home_rows_image_type_screen.dart`
- `lib/ui/screens/settings/panel/settings_search_index.dart`

### How it works

Unlike Live TV and music, playlists have an entry point on items Silo **does** have: "Add to playlist" sits on every film and episode, in the detail screen's buttons and in the item context menu. On a Silo item it would open the playlist dialog against Silo, which has no playlists. So this step gates per item as well as in settings.

**Per item.** `itemServerSupports(serverId, feature)` (new, in the helper file) asks `FeatureDetector` about the server an item came from. It picks that server the same way the item's actions do (`MediaServerClientFactory.clientForServerOrActive`: the item's loaded server, else the active one), so it agrees with the server the dialog would have talked to. With nothing set up it answers true.
- Context menu: "Add to playlist" is left out for an item whose server has no playlists.
- Detail screen: the Add to playlist button likewise. With Silo and Emby signed in, an Emby film keeps the button and a Silo film doesn't.

**Settings**, when no signed-in server has playlists (`playlistsOnAnySignedInServer()`):
- Detail buttons: Add to playlist isn't offered (`DetailButton.isOffered`, which the detail screen also reads).
- Home rows: the Playlists group ("Display playlists rows" and its sorting).
- Home sections and Home rows image type: the Playlists section (Audio playlists went with music in 4.2).
- Settings search: "Display playlists rows".

**Already hidden by data:** playlist screens open only from a playlist, and Silo has none. The album and track "Add to playlist" actions belong to music. Playlist rows, like music rows, rely on Silo's items translation answering a `Playlist`-only query with nothing; that check is in 5.1's test plan. The Android media browser (car / Android Auto) is a music tree with its own Playlists tab; it catches failures and is listed in 17.5's deferred checks.

### Testing

**Automated tests**

- `test/util/signed_in_server_features_test.dart`: new group for `itemServerSupports` (3 tests): a Silo item has no playlists and an Emby item does; an unknown or missing server falls back to the active one; with no client set up nothing is hidden. 11/11.
- Existing tests that cover the context menu, detail buttons and detail screen, plus `test/preference` and `test/ui/widgets/bottom_nav`: 289/289.

**Manual test plan**

Setup: only Silo signed in. (Silo items don't load until phase 6, so the per-item checks use Emby plus Silo.)

1. **Settings:** Detail buttons doesn't offer Add to playlist. Home rows has no Playlists group. Home sections and Home rows image type have no Playlists. Searching settings for "playlists rows" finds nothing.
2. **Compare with Emby:** sign in to Emby as well. All of the above come back; an Emby film's detail screen and context menu offer Add to playlist, and adding to a playlist works as before.
3. Regression: full `flutter test`.
4. Deferred to 6.4 (needs Silo items): with Silo and Emby signed in, a Silo film's detail screen and context menu have no Add to playlist.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-14 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | helper tests 11/11; detail, context menu, preference and bottom-nav tests 289/289; analyzer: no new issues |
| | | | | |

---

<a id="step-4-4"></a>
## 4.4 Hide SyncPlay and remote control

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** SyncPlay menu and "control another device" (Silo's Watch Together is a different protocol).

**Where in Moonfin**

- `lib/syncplay/*`
- `lib/ui/widgets/bottom_nav/*`

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

<a id="step-4-5"></a>
## 4.5 Hide the admin panel

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Admin entry points via `supportsAdmin` (Silo's admin lives in its web UI).

**Where in Moonfin**

- `lib/ui/screens/admin/*`
- `detail admin actions`

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

<a id="step-4-6"></a>
## 4.6 Gate Moonfin-plugin services: settings sync, messages, themes

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Return early from plugin sync, server messages and theme sync on Silo.

**Where in Moonfin**

- `plugin_sync_service.dart`
- `server_messages_service.dart`
- `theme_store_service.dart`
- `settings_side_panel.dart`

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

<a id="step-4-7"></a>
## 4.7 Gate Moonfin-plugin services: TMDB, MDBList, anime markers, custom lists

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** These proxies live in the plugin. Hide or skip their rows and badges on Silo.

**Where in Moonfin**

- `tmdb_repository.dart`
- `mdblist_repository.dart`
- `anime_marker_repository.dart`
- `custom_external_lists_service.dart`
- `upcoming_episode_service.dart`

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

<a id="step-4-8"></a>
## 4.8 Gate Moonfin-plugin services: ratings, bookmarks, notes

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Personal ratings store, audiobook bookmarks and notes go through the plugin.

**Where in Moonfin**

- `user_ratings_api.dart`
- `audiobook_bookmarks_service.dart`
- `audiobook_notes_service.dart`

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

<a id="step-4-9"></a>
## 4.9 Seerr: proxy mode off, direct mode allowed

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** The plugin's Seerr proxy doesn't exist on Silo. Direct Seerr (your own Seerr URL and per-user login) can still work.

**Where in Moonfin**

- `lib/data/services/seerr/seerr_http_client.dart`
- `Seerr settings`

### How it works

_Fill in when the step is built: what the code does, the main classes and why it is shaped this way, so a Moonfin maintainer can review it without reading the Silo docs._

### Testing

**Automated tests**

- _None planned; add any that were written._

**Manual test plan**

- Point Moonfin's direct Seerr setting at your Seerr; discovery rows load for a Silo user.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| | | | | |

---

<a id="step-4-10"></a>
## 4.10 Hide retro games

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Moonbase games need the Jellyfin plugin.

**Where in Moonfin**

- `games screens and nav`

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

# Silo support roadmap

152 steps in 18 phases (9 optional). **One step = one commit.** Tick a box when the step is committed and tested, and put its commit hash in the phase file.

Status key: ☐ not started · ◐ in progress · ☑ done and tested · ⊘ skipped (say why in the phase file)

| Phase | Steps | Phase done when |
|---|---|---|
| [0. Preparation](phases/00-prep.md) | 4 | The OpenAPI snapshot and fixtures match the server you run, and the probe script refreshes them. |
| [1. Groundwork](phases/01-groundwork.md) | 17 | Adding your Silo server is recognised as Silo and lands on a sign-in screen that can't sign in yet. Jellyfin and Emby behave exactly as before. |
| [2. Sign-in API (package only)](phases/02-auth-api.md) | 8 | `server_silo` can sign in, refresh, list profiles, check a PIN and describe the current user, all covered by tests. |
| [3. Sign-in and household profiles in the app](phases/03-signin-app.md) | 12 | You can sign in, pick a profile (with PIN if locked), switch profiles without re-entering the password, restart the app and stay signed in. Home is still empty until phase 5. |
| [4. Hide what Silo doesn't have](phases/04-gating.md) | 10 | With a Silo user active, no menu, row, tab or button leads to an error caused by a missing feature. |
| [5. Translation layer](phases/05-translation.md) | 13 | Every fixture maps to a BaseItemDto whose fields match the Emby fixture for the keys `AggregatedItem` reads. |
| [6. Browsing](phases/06-browsing.md) | 19 | You can open each library, scroll a full grid with artwork, open a movie, a series, its seasons and episodes, and the detail screen looks like it does on Emby. |
| [7. Search](phases/07-search.md) | 2 | Search returns movies, series, episodes and people like it does on Emby. |
| [8. Home screen](phases/08-home.md) | 7 | Home looks like it does on Emby for the same account, minus the rows Silo can't provide. |
| [9. User actions](phases/09-user-actions.md) | 6 | Each action shows the same result in Silo's web UI. |
| [10. Playback (first backend: media_kit on macOS)](phases/10-playback.md) | 16 | On the Mac: play, pause, seek anywhere, resume, stop, and see the right position in Silo afterwards. Same files compared on Emby. |
| [11. Player features](phases/11-player-features.md) | 7 | Skip intro, trickplay, chapters and up-next behave as they do on Emby/Jellyfin. |
| [12. Other platforms and casting](phases/12-platforms.md) | 7 | Plays on every platform you own (Android TV, Fire TV, iOS, Apple TV, web) and casts. |
| [13. Realtime events and app services](phases/13-realtime.md) | 6 | Watching on Silo web updates Moonfin's rows within seconds, and a server restart is handled. |
| [14. Sign in with a code (QuickConnect equivalent)](phases/14-device-signin.md) | 3 | A TV can sign in by approving a code from a phone, and the phone can approve another device. |
| [15. Downloads and offline](phases/15-downloads.md) | 7 | Download a movie and an episode, play them offline, and the progress syncs back. |
| [16. Books and audiobooks (Silo beta)](phases/16-books.md) | 2 | An audiobook plays with chapters and resumes; an EPUB opens and keeps its place. |
| [17. Polish and launch](phases/17-launch.md) | 6 | Silo appears in the README's supported-server table and passes the full regression run. |

## 0. [Preparation](phases/00-prep.md)

- [x] **0.1** [Add the Silo support docs](phases/00-prep.md#step-0-1)
- [x] **0.2** [Pin the Silo v2 contract for build 4b2e921c](phases/00-prep.md#step-0-2) · ↺ port
- [x] **0.3** [Probe script for refreshing fixtures](phases/00-prep.md#step-0-3) · ↺ port
- [x] **0.4** [Capture Silo and Emby fixture pairs](phases/00-prep.md#step-0-4) · ↺ port

## 1. [Groundwork](phases/01-groundwork.md)

- [x] **1.1** [`ServerType.silo`](phases/01-groundwork.md#step-1-1) · ↺ port
- [x] **1.2** [Silo capabilities in `FeatureDetector`](phases/01-groundwork.md#step-1-2) · ↺ port
- [x] **1.3** [Silo request headers](phases/01-groundwork.md#step-1-3) · ↺ port
- [x] **1.4** [`server_silo` package skeleton](phases/01-groundwork.md#step-1-4) · ↺ port
- [x] **1.5** [Silo error responses (Problem Details)](phases/01-groundwork.md#step-1-5) · ↺ port
- [x] **1.6** [`SiloSystemApi`](phases/01-groundwork.md#step-1-6) · ↺ port
- [x] **1.7** [`playback_silo` package skeleton](phases/01-groundwork.md#step-1-7) · ↺ port
- [x] **1.8** [Wire Silo into the app's factories](phases/01-groundwork.md#step-1-8) · ↺ port
- [x] **1.9** [Detect Silo in the server probe](phases/01-groundwork.md#step-1-9) · ↺ port
- [ ] **1.10** [Add the Silo packages to CI](phases/01-groundwork.md#step-1-10)
- [ ] **1.11** [Silo server icon](phases/01-groundwork.md#step-1-11) · ↺ port
- [ ] **1.12** [Shared auth headers for hand-built requests](phases/01-groundwork.md#step-1-12) · ↺ port
- [ ] **1.13** [Skip the bandwidth probe on Silo](phases/01-groundwork.md#step-1-13) · ↺ port
- [ ] **1.14** [Safer redirects for Silo sessions](phases/01-groundwork.md#step-1-14) · ↺ port
- [ ] **1.15** [No public user list on Silo](phases/01-groundwork.md#step-1-15) · ↺ port
- [ ] **1.16** [Skip Moonfin plugin sync at sign-in for Silo](phases/01-groundwork.md#step-1-16) · ↺ port
- [ ] **1.17** [Web discovery hint and add-server wording](phases/01-groundwork.md#step-1-17) · ↺ port

## 2. [Sign-in API (package only)](phases/02-auth-api.md)

- [ ] **2.1** [Token pair and single-flight refresh (`SiloSession`)](phases/02-auth-api.md#step-2-1) · ↺ port
- [ ] **2.2** [Session interceptor](phases/02-auth-api.md#step-2-2) · ↺ port
- [ ] **2.3** [Password sign-in](phases/02-auth-api.md#step-2-3) · ↺ port
- [ ] **2.4** [Sign out](phases/02-auth-api.md#step-2-4) · ↺ port
- [ ] **2.5** [List household profiles](phases/02-auth-api.md#step-2-5) · ↺ port
- [ ] **2.6** [Profile PIN check](phases/02-auth-api.md#step-2-6) · ↺ port
- [ ] **2.7** [Current user (account + profile → user)](phases/02-auth-api.md#step-2-7) · ↺ port
- [ ] **2.8** [User playback settings](phases/02-auth-api.md#step-2-8) · ↺ port

## 3. [Sign-in and household profiles in the app](phases/03-signin-app.md)

- [ ] **3.1** [Silo fields on the stored user](phases/03-signin-app.md#step-3-1) · ↺ port
- [ ] **3.2** [One token record per Silo account](phases/03-signin-app.md#step-3-2) · ↺ port
- [ ] **3.3** [Password sign-in from the login screen](phases/03-signin-app.md#step-3-3) · ↺ port
- [ ] **3.4** [Store the household as users](phases/03-signin-app.md#step-3-4) · ↺ port
- [ ] **3.5** ["Who's watching" picker](phases/03-signin-app.md#step-3-5) · ↺ port
- [ ] **3.6** [PIN entry for locked profiles](phases/03-signin-app.md#step-3-6) · ↺ port
- [ ] **3.7** [Switch profile without signing in again](phases/03-signin-app.md#step-3-7) · ↺ port
- [ ] **3.8** [Sign out of one profile vs the account](phases/03-signin-app.md#step-3-8) · ↺ port
- [ ] **3.9** [Restore the session on app start](phases/03-signin-app.md#step-3-9) · ↺ port
- [ ] **3.10** [Refused refresh → back to sign-in](phases/03-signin-app.md#step-3-10) · ↺ port
- [ ] **3.11** [Password change required](phases/03-signin-app.md#step-3-11)
- [ ] **3.12** [Which profile feeds cross-server rows](phases/03-signin-app.md#step-3-12) · ↺ port

## 4. [Hide what Silo doesn't have](phases/04-gating.md)

- [ ] **4.1** [Hide Live TV](phases/04-gating.md#step-4-1)
- [ ] **4.2** [Hide music, instant mix and lyrics](phases/04-gating.md#step-4-2)
- [ ] **4.3** [Hide playlists](phases/04-gating.md#step-4-3)
- [ ] **4.4** [Hide SyncPlay and remote control](phases/04-gating.md#step-4-4)
- [ ] **4.5** [Hide the admin panel](phases/04-gating.md#step-4-5)
- [ ] **4.6** [Gate Moonfin-plugin services: settings sync, messages, themes](phases/04-gating.md#step-4-6)
- [ ] **4.7** [Gate Moonfin-plugin services: TMDB, MDBList, anime markers, custom lists](phases/04-gating.md#step-4-7)
- [ ] **4.8** [Gate Moonfin-plugin services: ratings, bookmarks, notes](phases/04-gating.md#step-4-8)
- [ ] **4.9** [Seerr: proxy mode off, direct mode allowed](phases/04-gating.md#step-4-9)
- [ ] **4.10** [Hide retro games](phases/04-gating.md#step-4-10)

## 5. [Translation layer](phases/05-translation.md)

- [ ] **5.1** [Time, ID and type helpers](phases/05-translation.md#step-5-1)
- [ ] **5.2** [Image URL registry](phases/05-translation.md#step-5-2)
- [ ] **5.3** [Item mapper: core fields](phases/05-translation.md#step-5-3)
- [ ] **5.4** [Item mapper: series, seasons and episodes](phases/05-translation.md#step-5-4)
- [ ] **5.5** [Item mapper: user data](phases/05-translation.md#step-5-5)
- [ ] **5.6** [Item mapper: people](phases/05-translation.md#step-5-6)
- [ ] **5.7** [Library mapper](phases/05-translation.md#step-5-7)
- [ ] **5.8** [Versions and streams → MediaSources/MediaStreams](phases/05-translation.md#step-5-8)
- [ ] **5.9** [Chapters mapper](phases/05-translation.md#step-5-9)
- [ ] **5.10** [Markers mapper](phases/05-translation.md#step-5-10)
- [ ] **5.11** [Trickplay mapper](phases/05-translation.md#step-5-11)
- [ ] **5.12** [Cursor pager](phases/05-translation.md#step-5-12)
- [ ] **5.13** [Sort map](phases/05-translation.md#step-5-13)

## 6. [Browsing](phases/06-browsing.md)

- [ ] **6.1** [Image API on the registry](phases/06-browsing.md#step-6-1)
- [ ] **6.2** [Image cache keyed by path](phases/06-browsing.md#step-6-2)
- [ ] **6.3** [Image registry misses](phases/06-browsing.md#step-6-3)
- [ ] **6.4** [Libraries (`UserViewsApi`)](phases/06-browsing.md#step-6-4)
- [ ] **6.5** [Library grid (`getItems` for a library)](phases/06-browsing.md#step-6-5)
- [ ] **6.6** [Movie detail (`getItem`)](phases/06-browsing.md#step-6-6)
- [ ] **6.7** [Series detail and seasons](phases/06-browsing.md#step-6-7)
- [ ] **6.8** [Season episodes](phases/06-browsing.md#step-6-8)
- [ ] **6.9** [Ancestors](phases/06-browsing.md#step-6-9)
- [ ] **6.10** [Library filters](phases/06-browsing.md#step-6-10)
- [ ] **6.11** [Alphabet jump](phases/06-browsing.md#step-6-11)
- [ ] **6.12** [Genres](phases/06-browsing.md#step-6-12)
- [ ] **6.13** [Studios and networks](phases/06-browsing.md#step-6-13)
- [ ] **6.14** [People](phases/06-browsing.md#step-6-14)
- [ ] **6.15** [Collections (browse)](phases/06-browsing.md#step-6-15)
- [ ] **6.16** [Similar items](phases/06-browsing.md#step-6-16)
- [ ] **6.17** [Trailers and extras](phases/06-browsing.md#step-6-17)
- [ ] **6.18** [Detail-screen media info without starting playback](phases/06-browsing.md#step-6-18)
- [ ] **6.19** [Display preferences](phases/06-browsing.md#step-6-19)

## 7. [Search](phases/07-search.md)

- [ ] **7.1** [Title search](phases/07-search.md#step-7-1)
- [ ] **7.2** [People search](phases/07-search.md#step-7-2)

## 8. [Home screen](phases/08-home.md)

- [ ] **8.1** [Continue Watching](phases/08-home.md#step-8-1)
- [ ] **8.2** [Next Up](phases/08-home.md#step-8-2)
- [ ] **8.3** [Latest per library](phases/08-home.md#step-8-3)
- [ ] **8.4** [Recently released](phases/08-home.md#step-8-4)
- [ ] **8.5** [Favorites row](phases/08-home.md#step-8-5)
- [ ] **8.6** [Collections and genre rows](phases/08-home.md#step-8-6)
- [ ] **8.7** [Server-curated home sections](phases/08-home.md#step-8-7) *(optional)*

## 9. [User actions](phases/09-user-actions.md)

- [ ] **9.1** [Favorite / unfavorite](phases/09-user-actions.md#step-9-1)
- [ ] **9.2** [Mark played / unplayed](phases/09-user-actions.md#step-9-2)
- [ ] **9.3** [Ratings](phases/09-user-actions.md#step-9-3)
- [ ] **9.4** [Refresh rows after a change](phases/09-user-actions.md#step-9-4)
- [ ] **9.5** [Personal collections: create, add, remove](phases/09-user-actions.md#step-9-5)
- [ ] **9.6** [Watchlist](phases/09-user-actions.md#step-9-6) *(optional)*

## 10. [Playback (first backend: media_kit on macOS)](phases/10-playback.md)

- [ ] **10.1** [`playback_core`: timeline offset](phases/10-playback.md#step-10-1)
- [ ] **10.2** [`playback_core`: optional replan](phases/10-playback.md#step-10-2)
- [ ] **10.3** [Codec capabilities translator](phases/10-playback.md#step-10-3)
- [ ] **10.4** [Playback context](phases/10-playback.md#step-10-4)
- [ ] **10.5** [Installation id](phases/10-playback.md#step-10-5)
- [ ] **10.6** [Start playback](phases/10-playback.md#step-10-6)
- [ ] **10.7** [Stream authorisation](phases/10-playback.md#step-10-7)
- [ ] **10.8** [Unplayable media message](phases/10-playback.md#step-10-8)
- [ ] **10.9** [Progress reporting](phases/10-playback.md#step-10-9)
- [ ] **10.10** [Stop](phases/10-playback.md#step-10-10)
- [ ] **10.11** [Resume vs start over](phases/10-playback.md#step-10-11)
- [ ] **10.12** [Seek outside the produced window](phases/10-playback.md#step-10-12)
- [ ] **10.13** [Switch audio track](phases/10-playback.md#step-10-13)
- [ ] **10.14** [Subtitles: embedded and sidecar](phases/10-playback.md#step-10-14)
- [ ] **10.15** [Change quality / bitrate](phases/10-playback.md#step-10-15)
- [ ] **10.16** [Pick a version](phases/10-playback.md#step-10-16)

## 11. [Player features](phases/11-player-features.md)

- [ ] **11.1** [Skip intro, credits and recap](phases/11-player-features.md#step-11-1)
- [ ] **11.2** [Trickplay scrubbing](phases/11-player-features.md#step-11-2)
- [ ] **11.3** [Chapters and chapter images](phases/11-player-features.md#step-11-3)
- [ ] **11.4** [Next episode and autoplay](phases/11-player-features.md#step-11-4)
- [ ] **11.5** [Theme music](phases/11-player-features.md#step-11-5)
- [ ] **11.6** [Per-series audio and subtitle choice](phases/11-player-features.md#step-11-6) *(optional)*
- [ ] **11.7** [Shuffle](phases/11-player-features.md#step-11-7) *(optional)*

## 12. [Other platforms and casting](phases/12-platforms.md)

- [ ] **12.1** [Android / Android TV / Fire TV (Media3)](phases/12-platforms.md#step-12-1)
- [ ] **12.2** [Apple: iOS, tvOS, macOS native (AVPlayer/Aether)](phases/12-platforms.md#step-12-2)
- [ ] **12.3** [Web](phases/12-platforms.md#step-12-3)
- [ ] **12.4** [Chromecast](phases/12-platforms.md#step-12-4)
- [ ] **12.5** [AirPlay](phases/12-platforms.md#step-12-5)
- [ ] **12.6** [DLNA](phases/12-platforms.md#step-12-6)
- [ ] **12.7** [Trickplay and image headers in the player screens](phases/12-platforms.md#step-12-7)

## 13. [Realtime events and app services](phases/13-realtime.md)

- [ ] **13.1** [Connectivity ping through the API](phases/13-realtime.md#step-13-1)
- [ ] **13.2** [Events socket: connect and reconnect](phases/13-realtime.md#step-13-2)
- [ ] **13.3** [Events → user data and library changes](phases/13-realtime.md#step-13-3)
- [ ] **13.4** [Access changed](phases/13-realtime.md#step-13-4)
- [ ] **13.5** [Client log upload](phases/13-realtime.md#step-13-5) *(optional)*
- [ ] **13.6** [Household now playing](phases/13-realtime.md#step-13-6) *(optional)*

## 14. [Sign in with a code (QuickConnect equivalent)](phases/14-device-signin.md)

- [ ] **14.1** [Sign in on a TV with a code](phases/14-device-signin.md#step-14-1)
- [ ] **14.2** [Approve another device](phases/14-device-signin.md#step-14-2)
- [ ] **14.3** [Enable the entry points](phases/14-device-signin.md#step-14-3)

## 15. [Downloads and offline](phases/15-downloads.md)

- [ ] **15.1** [Download permission and capability](phases/15-downloads.md#step-15-1)
- [ ] **15.2** [Original-file downloads](phases/15-downloads.md#step-15-2)
- [ ] **15.3** [Transcoded downloads](phases/15-downloads.md#step-15-3)
- [ ] **15.4** [Offline metadata and artwork](phases/15-downloads.md#step-15-4)
- [ ] **15.5** [Offline progress sync](phases/15-downloads.md#step-15-5)
- [ ] **15.6** [Offline subtitles and trickplay](phases/15-downloads.md#step-15-6)
- [ ] **15.7** [Auto-download via subscriptions](phases/15-downloads.md#step-15-7) *(optional)*

## 16. [Books and audiobooks (Silo beta)](phases/16-books.md)

- [ ] **16.1** [Audiobooks](phases/16-books.md#step-16-1) *(optional)*
- [ ] **16.2** [Ebooks and comics](phases/16-books.md#step-16-2) *(optional)*

## 17. [Polish and launch](phases/17-launch.md)

- [ ] **17.1** [Native port hint](phases/17-launch.md#step-17-1)
- [ ] **17.2** [Local network discovery](phases/17-launch.md#step-17-2)
- [ ] **17.3** [Error and update messages](phases/17-launch.md#step-17-3)
- [ ] **17.4** [Translations](phases/17-launch.md#step-17-4)
- [ ] **17.5** [Full regression pass](phases/17-launch.md#step-17-5)
- [ ] **17.6** [README and wiki](phases/17-launch.md#step-17-6)

↺ port = code for this step already exists on `silo-1-groundwork`, `silo-2-signin-api` or the `Add_silo` stash and gets re-reviewed and re-tested rather than written from scratch.

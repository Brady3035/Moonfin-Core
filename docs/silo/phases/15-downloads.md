# Phase 15: Downloads and offline

[← Roadmap](../ROADMAP.md)

Read Silo's downloads design before step 15.3; it is a full server-managed download system.

**Phase done when:** Download a movie and an episode, play them offline, and the progress syncs back.

---

<a id="step-15-1"></a>
## 15.1 Download permission and capability

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Goal.** Show download actions only when the account may download.

**Silo v2 endpoints**

- `GET /capabilities/downloads`

**Where in Moonfin**

- `packages/server_silo/lib/src/api/silo_downloads_api.dart` (new): `SiloDownloadsApi` (the capability, read at most once a minute), `SiloDownloadCapability`, `SiloDownloadQualityOption`; `SiloMediaServerClient.downloadsApi`
- `packages/server_silo/lib/src/api/silo_users_api.dart`: `getCurrentUser` folds the capability into the policy's `EnableContentDownloading`

**Also in this commit: the phase 14 bookkeeping.** 14.2's fix hash `8cc18adc0` and Brady's macOS Pass row after the fix; 14.2 ticked in the roadmap. 15.7 moved to the roadmap's new [Later](../ROADMAP.md#later) list (Brady, 2026-10-18), with offline trickplay (left out of 15.6).

### How it works

Moonfin offers a download only when `userCanDownload()` says so: a platform that keeps downloads, the TV setting, and the signed-in user's `canDownload`, which comes from the server's user policy (`EnableContentDownloading`). On Silo that flag was the account's `download_allowed` (2.6). The account flag isn't the whole answer: Silo's guide says to hide download actions unless the downloads capability says they are `enabled` and `allowed`. A server can switch downloads off as a whole, and a demo server refuses them to every non-admin while their accounts still say `download_allowed: true`. An empty `quality_presets` list means the same ("downloads unavailable for this account").

So `SiloUsersApi.getCurrentUser` now reads `GET /capabilities/downloads` next to the account and the profiles (it needs `X-Profile-Id`, which the client sends), and switches `EnableContentDownloading` off when the capability doesn't permit downloads: not `available`, not `enabled`, not `allowed`, or no quality. It only ever switches the flag off; an account that may not download stays so. A capability that can't be read (an older server, a network blip) leaves the account's flag and is logged.

`getCurrentUser` runs at sign-in, when a stored login is restored, and when Silo says the login's access changed (13.4), and the app stores `canDownload` from it each time, so every download button follows a change made on the server at the next of these. The capability is read afresh at each of them; `SiloDownloadsApi.capability()` otherwise keeps an answer for a minute (concurrent callers share one read), for the quality choice in 15.3.

No app code changes: every download entry point already asks `userCanDownload()`.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_downloads_api_test.dart` (new, 13 tests): the captured capability (`silo/downloads_capabilities.json`) fits the contract and reads back, sent as the profile and the device; quality options keep their bitrate and height; switched off, refused for this login, not configured and no quality are not permitted; read once a minute, concurrent reads share one, invalidation reads again; a failed read isn't kept. The user's permission: on when both say so; off when the server has downloads off; never on when the account may not; an unreadable capability keeps the account flag; each `getCurrentUser` asks again.
- `packages/server_silo/test/silo_users_api_test.dart`: the profile check now lists the capability read too. `server_silo` 633/633; `test/auth` 138/138 (their fake Silo has no capability route, so the account flag stands).

**Manual test plan**

On the Mac, signed in to Silo:

- a. A film's detail page offers Download (as before, since your account may download and the server allows it). The network log shows `GET …/api/v2/capabilities/downloads` at sign-in or start, next to `GET …/account/me`.
- b. In Silo's admin, switch downloads off for the server (or turn off your account's download permission), then restart Moonfin: no Download action on the detail page, the season page or the context menu. Switch it back on and restart: it's back.
- c. Regression on Emby: Download still shows for an account that may download.
- d. Full suite (`flutter test` at the repo root).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | downloads API 13/13, `server_silo` 633/633, `test/auth` 138/138; analyzer: no issues in the changed files |
| | | | | |

---

<a id="step-15-2"></a>
## 15.2 Original-file downloads

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Goal.** Download the original file through Silo's download registry (managed downloads). *Changed from signed direct-download links (Brady, 2026-10-18): Silo's guide says apps use managed downloads for every quality and keeps direct links for browsers.*

**Silo v2 endpoints**

- `GET /downloads` (the device's entries)
- `POST /downloads` (register a download)
- `GET /downloads/{id}/file`
- `PATCH /downloads/{id}` (completed)
- `DELETE /downloads/{id}`
- `POST /direct-download/links`, `GET /direct-download` (the web build only)

**Where in Moonfin**

- `packages/server_core/lib/src/api/server_downloads_api.dart` (new): `ServerDownloadsApi`, `ServerDownloadsProvider`, `ServerDownloadRequest`, `ServerDownloadTicket`, `ServerDownloadRefused`
- `packages/server_silo/lib/src/api/silo_downloads_api.dart`: `SiloDownloadsApi` implements it (`prepareDownload`, `browserDownloadUrl`, `downloadFinished`, `downloadsRemoved`, `existingEntry`), `SiloDownloadEntry`; `SiloMediaServerClient` is a `ServerDownloadsProvider`
- `lib/data/services/download_service.dart`: asks the server for the file when its client provides `ServerDownloadsApi`; tells it when a file is finished or deleted

### How it works

**Silo's model.** Silo keeps a registry of the files each device holds (`docs/downloads-api.md`, "managed device entries"). A request carrying `X-Silo-Device-Id`, which Moonfin's Silo client sends on every request, registers an entry for that device and profile. The entry names the file, and its `GET /downloads/{id}/file` serves the bytes (with ranges, so a transfer can resume). The device reports when it has the whole file, and deletes the entry when it deletes its copy. The registry is what Silo's manifest (15.4), subtitles (15.6) and offline progress (15.5) build on, and what lets an admin see or revoke a device's downloads.

**The seam.** Moonfin's download service (upstream code) builds Jellyfin and Emby URLs (`/Items/{id}/Download`, `/Videos/{id}/stream`) and sends a `MediaBrowser` token. A new optional `server_core` interface, `ServerDownloadsApi`, lets a server hand over the file instead. Silo's client provides it (`ServerDownloadsProvider`). The service unwraps the app's connectivity wrapper to find it, and then:

1. **before the transfer**, after the storage checks, asks `prepareDownload` (the item, its series for an episode, the version, the quality). The answer is a ticket: the file's URL, the headers it needs, its size;
2. fetches the ticket's URL with the ticket's headers, through the same engines as any download (native background engine or the in-process one). The Jellyfin fallback URLs are skipped;
3. **when the file is complete**, calls `downloadFinished` (best effort);
4. **when downloads are deleted** (a movie, an episode, or a season or series with each of its downloaded episodes), and when a running download is cancelled, calls `downloadsRemoved` with their item ids (best effort: the local files go anyway).

A refusal (`ServerDownloadRefused`) becomes the download's error, with the server's words. Jellyfin and Emby clients don't provide the interface; their downloads are unchanged.

**Silo's side (`SiloDownloadsApi`).**

- **Registering.** `POST /downloads` with `content_id` (the movie, or an episode's series), `episode_id` (an episode), `media_file_id` (the version; Silo's file ids are Moonfin's media source ids) and `quality: original`. No `caps` are sent, so Silo hands over the source file as it is, as Moonfin's Jellyfin original downloads do. With a device header Silo also needs `expected_revision`: `0` when the device has no entry for the item, or the existing entry's revision with its id (`expected_download_id`), which reuses, revives or replaces it. So the device's entries are read first (`GET /downloads`, 100 at a time, at most 10 pages, newest first) and matched by item: this is the reconciliation Silo's guide asks for before creating. Creation is `non_retryable` and is sent once.
- **The answer.** A servable entry gives the ticket: `ready`, or `downloading` or `completed` (the state a device reports on a ready file; registering an item this device downloaded before can hand back its earlier entry). The ticket is `…/api/v2/downloads/{id}/file` with the client's headers (bearer token, `X-Profile-Id`, `X-Silo-Device-Id`) and `Accept: application/octet-stream`. Refusals: downloads off for this profile (from 15.1's capability, checked first, nothing sent); `skipped` with `no_file` or `quality_unavailable`; `403`/`404`/`422` with Silo's text (a refused policy, an original above the account's download quality ceiling). An entry Silo is still preparing (it does that for converted files, 15.3) isn't handed out yet. Other failures (network, `5xx`, a `409` from a stale revision) reach the service as errors; the person retries.
- **Finished.** `PATCH /downloads/{id}` with `status: completed`, the time, and the entry's revision.
- **Deleted.** The device's entries are read and those for the deleted items get `DELETE /downloads/{id}`; one already gone (`404`) is fine.
- **Web.** A browser download carries no headers, so the web build asks for a short-lived link instead (`POST /direct-download/links` with the file id): the link holds its own credential for five minutes. Original files only; it is what Silo's guide says browsers use.

**Known limits.**

- The transfer's headers are fixed when it starts, and Silo checks the token when a request arrives, so a long transfer runs on. But a transfer that resumes after the access token expired (an hour; for example the native engine retrying after a dropped network) is refused with `401` and fails; Retry starts it again with a fresh token.
- A download that finishes while Moonfin isn't running (the native engine in the background, finished on the next start) isn't reported completed to Silo; its entry stays `ready`. Nothing depends on it in Moonfin.
- Artwork and subtitles of a Silo download still go through the Jellyfin paths and mostly fail (best effort, the download itself is fine): 15.4 and 15.6.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_downloads_api_test.dart` (15 new, 28/28): the fixture (`silo/download_created.json`, hand-built) and every request body fit the contract (`DownloadCreated`, `DownloadCreateBody`, `DownloadStatusBody`, `DirectDownloadLinkBody`); a new download is registered after reading the device's entries, as the profile and device, and its ticket has the file URL, headers, revision and size; an episode is its series' content with the episode named; an existing entry is named with its revision and id; the entry scan follows the cursor; downloads switched off, no file, and a refused policy are refused with their reasons; a preparing file isn't handed out; an earlier, completed entry is served again; a server error is sent once; finished reports `completed`; deleted items delete their entries (`404` fine), others are kept; a browser gets a link for the original, and none without a file id or for a converted download.
- `test/offline/server_download_test.dart` (new, 5 tests): the download service fetches the server's file with its headers (no `X-Emby-Token`) and reports it finished; an episode names its series; a refusal is the download's error and nothing is fetched; deleting tells the server; deleting a season names each downloaded episode.

**Manual test plan**

On the Mac, signed in to Silo (the network log is in Moonfin's logs):

- a. Download a film at Original from its detail page. The log shows `GET …/api/v2/downloads?limit=100`, `POST …/api/v2/downloads` (`202`), then `GET …/api/v2/downloads/<id>/file`, and when it's done `PATCH …/api/v2/downloads/<id>` (`200`). The download completes; its size matches the file on the server.
- b. Turn the network off (or stop Silo) and play the downloaded film from Downloads: it plays from the file.
- c. Download an episode, then a whole season ("Download all"): each episode registers and completes.
- d. Delete the film from Downloads: `DELETE …/api/v2/downloads/<id>` (`204`). Download it again: it registers as new (`expected_revision` 0). Delete the season: one `DELETE` per episode.
- e. Start a download and cancel it while it runs: the entry is deleted on Silo too.
- f. In Silo's web admin, if it lists device downloads: Moonfin's entries appear as this device's, completed.
- g. Regression on Emby: an Original download still completes, from `/Items/<id>/Download`.
- h. Full suite (`flutter test` at the repo root).
- i. Deferred to 17.5 with the web build (12.3): on Moonfin for the web, Download opens the browser's download of the original through a `…/direct-download?dl=…` link.

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | downloads API 28/28, server download 5/5, `server_silo` 648/648, `server_core` 100/100, `test/offline` + `test/data/services` 614/614; analyzer: no new issues in the changed files |
| 2026-10-18 | Web | — | Deferred | check i in 17.5 |
| | | | | |

---

<a id="step-15-3"></a>
## 15.3 Transcoded downloads

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Goal.** Server download jobs: create, prepare, wait, file. Moonfin's qualities map onto Silo's presets (Brady, 2026-10-18).

**Silo v2 endpoints**

- `POST /downloads` with a bitrate `quality`
- `GET /downloads` (the entry's `preparation` while Silo makes the file)
- `POST /downloads/{id}/prepare` (a converted file Silo cleaned up)
- `GET /downloads/{id}/file`

(The roadmap also listed `GET /downloads/{id}/manifest`: that is 15.4's.)

**Where in Moonfin**

- `packages/server_core/lib/src/api/server_downloads_api.dart`: `prepareDownload` takes `onPreparing` and `isCancelled`; `ServerDownloadPreparation`, `ServerDownloadCancelled`
- `packages/server_silo/lib/src/api/silo_downloads_api.dart`: `siloDownloadPreset`, the wait (`_waitUntilServable`), prepare again
- `lib/data/services/download_service.dart`: shows the preparation, honours Cancel during it, and treats the prepared file as a plain one for the engines

### How it works

**Silo makes the file, then serves it.** Moonfin's own transcoded downloads (Jellyfin, Emby) stream a live transcode into the file as the server encodes it. Silo works differently: a converted download is a job on the server (`preparing`), which writes a finished MP4 (`ready`) that the device then fetches like any file, with ranges (`docs/downloads-api.md` §1, §5). So a Silo download with a converted quality has two phases: waiting while Silo prepares, then an ordinary transfer.

**Qualities (`siloDownloadPreset`).** Moonfin offers Original, 1080p (4 Mbit/s), 720p (2), 480p (1) and 360p (0.5). Silo's presets are `20mbps`, `10mbps`, `5mbps` (all up to 1080p or 2160p, as the server allows), `2mbps` (720p) and `1mbps` (480p), and the capability (15.1) lists those the account may use now. Moonfin's quality picks the smallest preset whose cap reaches its bitrate: 1080p is `5mbps`, 720p `2mbps`, 480p and 360p `1mbps`. If the account may not use that preset, the next lower one it may; never a higher one, which would be a bigger file than asked for. When none fits (a server with converted downloads off offers only `original`), the download is refused: "This server offers only original-quality downloads to this account." Silo itself never enlarges the picture and never encodes above the source's bitrate; with no `caps` sent it makes H.264/AAC MP4, which every player plays.

**Waiting.** The create answers the entry, `preparing` for a converted file. Moonfin then reads the device's entries every 5 seconds (Silo refreshes its numbers at most that often) and follows the entry until it is servable. The listed entry carries `preparation`: its place in Silo's queue, or once running the encoded fraction and the time left. The download's row shows these as a server transcode's (the time left, or "time remaining unavailable", and the fraction while Silo reports it). Ends of the wait:

- `ready` (or `downloading`/`completed`): the ticket, as in 15.2; the file is an MP4 (`delivery_format` `transcode` or `remux`);
- `failed` (Silo's job gave up), `revoked` or `cancelled`: refused with that reason;
- the entry gone from the list: refused (`not_found`);
- Cancel pressed: the wait stops at the next check (`ServerDownloadCancelled`), the download is dropped as if cancelled while queued, and the entry is deleted on Silo, so Silo stops preparing a file nobody wants.

There is no time limit: a long film on a busy server can take a while, and the person can cancel.

**A file Silo cleaned up.** Silo keeps a converted file only while some download needs it, plus a few days, then deletes its copy (the device's is the one that matters). Registering the item again can then answer a `completed` entry whose file is gone. For a converted entry in that state Moonfin asks `POST /downloads/{id}/prepare` (when the capability reports `prepare_again`), which returns it to `preparing` and the wait follows; for one whose file is still there it changes nothing.

**The transfer.** Once Silo has the file, the download service treats it as an original: the native background engine (resumable, with notifications) where it would run an original, byte progress against the known size, no live-transcode handling (no transmux engine, no transcode status polling, no "activity" reports). The file is named `.mp4`, as Moonfin's transcoded downloads are, and is checked to be one.

**Known limits.**

- If Silo deletes the prepared file between the wait and the transfer (`409 prepared_file_expired` from the file route), the download fails; Retry registers it again and Silo prepares the file once more.
- Moonfin's quality picker still describes its own presets ("MP4 • HEVC/AAC" and its size estimates); Silo's file is H.264, of the preset's size.
- On Brady's server converted downloads are off (`transcode_enabled: false`, only `original` offered), so on it every converted quality is refused until that is switched on in Silo's settings.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_downloads_api_test.dart` (7 new, 35/35): Moonfin's qualities map onto the allowed presets (next lower when not allowed, never higher, none when only `original`); the wait reports the queue place, then progress and time left, and ends with an `mp4` ticket; a failed preparation and an entry that disappears are refused; Cancel stops the wait; a quality the account may not use is refused before anything is created; a converted file Silo cleaned up is prepared again; a remux of an original is waited for too (replaces 15.2's "not handed out yet").
- `test/offline/server_download_test.dart` (2 new, 7/7): a converted quality shows the server's progress and time left while it prepares, asks for its bitrate, then downloads the file; Cancel while it prepares tells the server to forget it and fetches nothing.

**Manual test plan**

Converted downloads must be on in Silo first (server settings: transcode to file; the capability then lists the bitrate presets). On the Mac, signed in to Silo:

- a. Download a film at 720p. The log shows `POST …/api/v2/downloads` with `quality: 2mbps`, then `GET …/api/v2/downloads?limit=100` every 5 seconds. The Downloads screen shows the film with Silo's time left (or "unavailable" while it waits in Silo's queue). When Silo is done: `GET …/downloads/<id>/file`, then `PATCH` completed. The file is an `.mp4` and plays offline.
- b. 1080p on a 4K or 1080p film: `quality: 5mbps`. 360p: `quality: 1mbps`.
- c. Start a 720p download and cancel it while Silo prepares: `DELETE …/api/v2/downloads/<id>`, and Silo's admin shows no preparation left for it.
- d. With converted downloads off on Silo (as now): a 720p download fails with "This server offers only original-quality downloads to this account." Original still works.
- e. Delete a finished 720p download and download it again a few days later (or after Silo cleaned up its file): `POST …/downloads/<id>/prepare`, then the wait.
- f. Regression on Emby: a 720p download still streams the transcode as before.
- g. Full suite (`flutter test` at the repo root).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | downloads API 35/35, server download 7/7, `server_silo` 655/655, `server_core` 100/100, `test/offline` + `test/data/services` 616/616; analyzer: no new issues in the changed files |
| | | | | |

---

<a id="step-15-4"></a>
## 15.4 Offline metadata and artwork

| Status | Commit | Depends on |
|---|---|---|
| ☑ Done | — | previous step |

**Goal.** Store the translated item and the image bytes; offline images must not depend on the registry.

**Silo v2 endpoints**

- `GET /downloads/{id}/manifest`
- `GET /downloads/{id}/artwork/{kind}` (`poster`, `backdrop`, `logo`, `series_poster`)

**Where in Moonfin**

- `packages/server_core/lib/src/api/server_downloads_api.dart`: `downloadArtwork`, `ServerDownloadArtworkKind`
- `packages/server_silo/lib/src/api/silo_downloads_api.dart`: `manifest` (read once per download), `downloadArtwork`
- `lib/data/services/download_service.dart`: `_downloadServerArtwork`, `_saveServerSeriesPoster`, `_fetchServerArtwork`

### How it works

**The item.** Every download already stores the item as Moonfin reads it: the `BaseItemDto` map the Silo client translated (title, overview, people, runtime, user data, the playing version's media source and chapters), as the row's `metadataJson`. Offline screens read that, on every server. Nothing changes there.

**The images.** Offline screens read images from files beside the download, by item id (`OfflineImageApi`), so offline they never touch the image registry. The weak point was fetching them: Moonfin downloads them through the client's image URLs, and on Silo an image URL only exists for an item this session has read (5.2, 6.3); for any other the URL is a stand-in that only Moonfin's image cache knows how to resolve, and a plain download of it fails. An automatic download in the background, or a series' poster for an episode downloaded from a list, could end up without art.

Silo's manifest is the way it means apps to get them (`docs/downloads-api.md` §4.6, §4.8): for each download it names authenticated artwork links, `/api/v2/downloads/{id}/artwork/{kind}`, served to this device and profile with the same headers as the file, whether or not anything was read before. So for a server-registered download (`ServerDownloadsApi`), after the file:

1. `downloadArtwork` reads the manifest (`GET /downloads/{id}/manifest`, once per download; it stays in memory for the subtitles, 15.6) and answers its `artwork_urls`, made absolute;
2. the service fetches each with the ticket's headers into the files the other servers' downloads use: `poster.jpg`, `backdrop.jpg`, `logo.png` in the item's image folder. For an episode Silo's `poster` is the episode still, which is what Moonfin shows as an episode's primary image, and `backdrop` the series' backdrop;
3. an episode's `series_poster` goes to the series' row when that row has none of its own (its own images still come through the client's URLs as before, which can fail for a series never read). It gets its own file name, `series_poster.jpg`, so it never collides with the series' own `poster.jpg` download running at the same time.

A kind the item has no art for is absent and left out; a fetch that fails leaves that image out (best effort, as on the other servers). Jellyfin and Emby downloads still use `_downloadImages`.

**Not used:** the manifest's thumbhashes (Moonfin draws no blurred placeholders), and its other fields (chapters, markers, audio tracks, codecs), which the stored item already has.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_downloads_api_test.dart` (4 new, 39/39): the episode manifest fixture (`silo/download_manifest_episode.json`, hand-built) fits the contract; its artwork links come back absolute, read once, as the device and profile; kinds without art are left out; a manifest that failed is read again next time.
- `test/offline/server_download_test.dart` (1 new, 8/8): an episode's artwork comes from the server's links with the ticket's credentials into `poster.jpg` and `backdrop.jpg`, and its series poster goes to the series' row as `series_poster.jpg`.

**Manual test plan**

On the Mac, signed in to Silo:

- a. Download a film. After the file, the log shows `GET …/downloads/<id>/manifest` and `GET …/downloads/<id>/artwork/poster`, `…/backdrop` and `…/logo` (each `200`, or a `404` for art the film has none of).
- b. Turn the network off (or stop Silo): the film's card in Downloads, its detail page and the player show the poster, backdrop and logo.
- c. Download a single episode of a show you haven't opened since starting Moonfin (for example from Search, or straight from Next Up): offline, the episode shows its still and the show its poster in Downloads.
- d. Regression on Emby: a download's artwork still shows offline.
- e. Full suite (`flutter test` at the repo root).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | downloads API 39/39, server download 8/8, `server_silo` 659/659, `server_core` 100/100, `test/offline` + `test/data/services` 617/617; analyzer: no new issues in the changed files |
| | | | | |

---

<a id="step-15-5"></a>
## 15.5 Offline progress sync

| Status | Commit | Depends on |
|---|---|---|
| ◐ Ready for testing | — | previous step |

**Goal.** Replay queued progress through bulk progress sync.

**Silo v2 endpoints**

- `POST /sync/progress`

**Where in Moonfin**

- `packages/server_core/lib/src/api/offline_progress_sync_api.dart` (new): `OfflineProgressSyncApi`, `OfflineProgressEntry`
- `packages/server_silo/lib/src/api/silo_user_library_api.dart`: `SiloUserLibraryApi` implements it
- `lib/data/services/sync_service.dart`: `syncPlaybackProgress` sends the pushes in bulk when the server takes them
- (`lib/data/services/offline_playback_tracker.dart`, which the roadmap named: unchanged; it records offline progress the same way on every server.)

### How it works

While offline, Moonfin's player records each downloaded item's position in the download's row (`OfflinePlaybackTracker`: every 10 seconds, and 0 once past 90%, meaning played) and marks it unsynced. When the server is reachable again, `SyncService.syncPlaybackProgress` reads the server's user data for those items in one request and settles each: a played item on the server, or a server position further along, is adopted locally; otherwise the local progress is pushed. On Jellyfin and Emby the push is a stop report (`reportPlaybackStopped`) or "mark played", one call per item.

On Silo a stop report needs a playback session (10.10), which an offline play never had, so offline progress didn't reach Silo. Silo's guide has a route for exactly this: `POST /sync/progress` takes up to 100 queued writes in one request (`docs/downloads-api.md` §7.1). A new optional `server_core` interface, `OfflineProgressSyncApi`, carries it. Silo's user-library API provides it, and the sync service, finding it on the client's `userLibraryApi`, collects the pushes and sends them together after the comparison loop, in batches of the server's limit. Jellyfin and Emby don't provide it and are unchanged.

**What is sent.** Per item: `media_item_id`, `position_ms`, `duration_ms` (from the stored item's runtime), `updated_at`, and a `client_ref` (its place in the batch). A played item is sent as having reached its end (`position_ms` = runtime); Silo's own watched threshold then marks it watched, and Silo never lets a later lower position unwatch it. A played item whose runtime isn't known can't be said that way and is marked played as before (`POST /watched/{id}`). `updated_at` is the time of the sync: the store keeps no time for offline progress, and the server's own newer progress was already preferred by the comparison. Silo answers per item with its `index`; each one taken is marked synced (and noted as changed for the Silo caches, 9.4), each refused one stays queued for the next sync, and a request that fails as a whole leaves its batch queued. The route is `non_retryable` and is sent once.

**Known limit.** As on the other servers, the comparison favours whichever side got further: rewinding on another device while this one was offline is overridden by the offline position when it is further along.

### Testing

**Automated tests**

- `packages/server_silo/test/silo_offline_progress_test.dart` (new, 5 tests): the queued progress goes in one request as milliseconds, a played item at its end, and the body fits the contract (`ProgressSyncInputBody`); a refused item is false by its index; Silo's answer shapes fit the contract; a failed request is sent once; an empty queue sends nothing, batches of at most 100.
- `test/offline/offline_progress_sync_test.dart` (6 new, 20/20): with a bulk-capable server, local progress (partial and played) goes in one request and no stop reports; a server ahead is adopted and nothing sent; batches follow the server's limit; a refused item stays queued; a failed request keeps everything queued; played without a runtime is marked played instead.

**Manual test plan**

On the Mac, with a Silo film and an episode downloaded (15.2):

- a. Turn the network off (or stop Silo). Play the film for a few minutes and stop; play the episode to its end (past 90%).
- b. Network back on (or Silo started): within the reconnect sync, the log shows one `POST …/api/v2/sync/progress` (`200`), and no `…/playback/…/stop`. In Silo's web app the film shows the resume point from offline, and the episode is watched.
- c. Repeat a, but before reconnecting play the film further on Silo's web app: after the sync, Moonfin shows the web app's position (adopted), and no progress is sent for the film.
- d. Regression on Emby: offline progress still syncs (as a stop report).
- e. Full suite (`flutter test` at the repo root).

**Results**

| Date | Platform | Server build | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | Linux (Claude workspace, Flutter 3.47.2) | — | Pass | offline progress 5/5, progress sync 20/20, `server_silo` 664/664, `server_core` 100/100, `test/offline` + `test/data/services` 623/623; analyzer: no issues in the changed files |
| | | | | |

---

<a id="step-15-6"></a>
## 15.6 Offline subtitles and trickplay

| Status | Commit | Depends on |
|---|---|---|
| ☐ Not started | — | previous step |

**Goal.** Download sheets and sidecars (signed URLs expire).

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

<a id="step-15-7"></a>
## 15.7 Auto-download via subscriptions *(optional)*

| Status | Commit | Depends on |
|---|---|---|
| ⏸ Later (Brady, 2026-10-18) | — | previous step |

Not part of this phase: Brady moved it to the roadmap's [Later](../ROADMAP.md#later) list (2026-10-18). Moonfin's own auto-download keeps working on Silo through the ordinary downloads of 15.2 and 15.3.

**Goal.** Map Moonfin's auto-download to Silo download subscriptions.

**Silo v2 endpoints**

- `/downloads/subscriptions`

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

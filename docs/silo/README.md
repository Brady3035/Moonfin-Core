# Native Silo support in Moonfin

This folder documents adding [Silo Media Server](https://github.com/Silo-Server/silo-server) as a third server type next to Jellyfin and Emby, using Silo's native **`/api/v2`** API (not its Jellyfin-compat listener on port 8096).

| File | What it is |
|---|---|
| [ROADMAP.md](ROADMAP.md) | The full checklist: every step, one commit each |
| [phases/](phases/) | One file per phase. Each step has its goal, the Silo endpoints and Moonfin files involved, and the **How it works** and **Testing** sections we fill in as we go |
| [DECISIONS.md](DECISIONS.md) | Design choices: decided ones with their reasons, and open ones waiting on a decision |
| [reference/design-2026-10-08.md](reference/design-2026-10-08.md) | The detailed design notes from the first pass (mapping tables, playback protocol, live-server findings). The roadmap step IDs replace its old step numbers |

## How the work is shaped

- **Silo is a new backend, not a fork of the UI.** New packages `packages/server_silo` and `packages/playback_silo` mirror `server_emby`/`playback_emby`. The Silo client translates every Silo response into the Jellyfin/Emby `BaseItemDto` shape the app already reads, so screens and view models stay unchanged.
- **Developed on a fork, no build flag.** Silo is a normal server type in Brady's fork from step 1.1 on. Every commit must build and leave Jellyfin and Emby untouched.
- **Three things have no Jellyfin equivalent** and get their own design: signed artwork URLs (image registry, 5.2), cursor pagination (5.12), and server-decided playback plans (phase 10).
- **Out of scope** (Silo doesn't have them): Live TV/DVR, music, playlists, SyncPlay, Jellyfin admin, and the Moonfin server plugin features. Phase 4 hides their entry points.

## Workflow for each step

1. Claude marks the step ◐ in its phase file and builds it. Only that step's change is in the working tree.
2. Claude runs the automated tests in a private copy of the repo (see below) and fills in **How it works**.
3. Brady runs the step's manual test plan on the Mac against the Silo server, comparing with Emby where the step says so, and the results go in the **Results** table.
4. Brady commits once the step passes, titled `silo(<id>): <title>` (for example `silo(1.9): Detect Silo in the server probe`), with the step's doc update in the same commit.
5. The commit hash goes in the step's table and the box gets ticked in ROADMAP.md (done at the start of the next step, so it lands in the next commit).

## Running and testing

- Run: `flutter run -d macos` (no extra defines needed).
- Package tests: `cd packages/server_silo && flutter test` (same for `playback_silo`, `server_core`).
- Test servers: Silo at `https://silo.snowystreams.com` (build `4b2e921c`, `api_major` 2 on 2026-10-13); Emby at `https://emby.snowystreams.com` for comparisons.
- **Don't run `pub get` inside the working folder from the Linux VM.** It writes Linux paths into `.dart_tool/package_config.json` and breaks the Mac build until `flutter pub get` runs again. Analyse and test in a copy: `rsync -a --delete --exclude .dart_tool --exclude build --exclude .git ~/mnt/Moonfin-Core/ ~/work/moonfin/`.

## Upstream

The Moonfin maintainers prefer small PRs. Steps group naturally into PRs by phase (phases 1–3 may each be one PR; phase 6 may split). Open a tracking issue on `Moonfin-Client/Moonfin-Core` that links this plan before the first PR, and raise the `server_core`/`playback_core` interface additions (profile headers, `timelineOffset`, optional `replan`) there first.

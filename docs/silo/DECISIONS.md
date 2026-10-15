# Silo support decisions

[← README](README.md)

## Decided

### D1. A Silo household profile is a Moonfin user (2026-10-08; deferred to phase 18 by D9)
Each profile shows as its own user, so the existing user switcher, per-user settings, offline data and "last user" work per household member. Profiles of one account share one token pair. Rules for sign-out, refresh, multi-server rows and PINs are in [reference §4.2.1](reference/design-2026-10-08.md#421-design-note-households-inside-moonfins-multi-server-model).

### D4. Native `/api/v2` only (2026-10-13)
Silo's `/api/v1` is a frozen alpha and its Jellyfin-compat listener is a different product path. Silo's `server_version` is a git hash, so compatibility is checked with `api_major` and the `contract_digest` is logged.

### D5. One step per commit, docs in the same commit (2026-10-13)
Each roadmap step is one commit titled `silo(<id>): <title>` and includes its own doc update.

### D0. Port the earlier branches, split finer (2026-10-13)
The code on `silo-1-groundwork`, `silo-2-signin-api` and the `Add_silo` stash is rebuilt on `Silo-Support` one roadmap step per commit (steps marked ↺). Each ported step is re-reviewed, re-tested against the current server build and documented like a new step.

### D8. No build flag; develop on the fork (2026-10-13)
Silo isn't hidden behind `MOONFIN_SILO`/`siloSupportEnabled`. The work lives on Brady's fork until it is proposed upstream, so the flag (and its step) is dropped, and the flag is stripped from code ported from the earlier branches. If the maintainers want the work merged in pieces before it can play, a flag can be added back as one commit at that point.

### D9. Household profiles are optional and come last (2026-10-13)
Profile support (picker, PINs, switching, one Moonfin user per profile) moves to an optional phase 18, so the core client ships without it. Until then Moonfin signs in to the account and **acts as its main (primary) profile**: every request carries that profile's `X-Profile-Id`, because Silo keeps progress, favourites and home rows per profile and refuses requests without the header once any profile on the account has a PIN or restrictions. The Moonfin user id is the main profile's id, so phase 18 adds the other profiles as users without migrating anyone. A PIN-locked main profile can't sign in until 18.4; step 3.7 explains that instead of failing with a generic error.

### D10. Missing features are hidden through `FeatureDetector`, one flag each (2026-10-14)
Phase 4 hides what Silo doesn't have without testing for Silo anywhere in the UI. Every gate asks a `FeatureDetector` flag. Settings that apply to every server are hidden only when **no signed-in server** supports the feature (`anySignedInServerSupports`). Actions on one item or on the active server ask that server (`itemServerSupports`, `activeServerSupports`). Code that calls the Moonfin plugin directly checks `serverHasMoonfinPlugin` first. So a feature comes back by changing its flag: if Silo ever gets a Moonfin plugin, making `supportsMoonfinPlugin` true for Silo (or deciding it from a Silo ping) brings back settings sync, server messages, themes, TMDB, MDBList, anime markers, custom rows, personal ratings, audiobook bookmark sync and (with `supportsJellyseerr`) Seerr. The plugin would need to serve `/Moonfin/*` with Silo's bearer token, or `server_silo` would need a small adapter. Live TV, music, playlists and the admin panel stay off, because Silo itself lacks them, not the plugin.

### D2. Artwork when nothing is registered: resolve by loading the item (2026-10-14)
Cold start, deep links and parent ids can ask for an image the registry has never seen, and Silo has no image URL that can be built from an id. Brady chose the **resolver**: `SiloImageApi` hands out a placeholder URL for an item not read this session, and the image cache (a small `urlResolver` hook in `cached_network_image_fork`) asks the Silo client to load that item, which registers its artwork, before downloading. Artwork always appears; an item read once is not loaded again, and missing art is not retried for ten minutes. Step 6.3.

### D3. Display preferences stay on the device (2026-10-14)
Per-library view settings (image type, sort, view) are kept locally for Silo. Silo's per-profile settings store only takes keys from its own contract; the only comparable key, `ui.library_page_state`, is its web app's state for one profile on one device, so it would never sync anything. Moonfin already keeps these settings in its own preferences and only mirrors them to the server, so `SiloDisplayPreferencesApi` keeps the mirror in memory and sends nothing (step 6.19). Library order and hidden libraries do use Silo's settings (`ui.library_order`, `ui.disabled_library_ids`, step 2.7). Still open, for phase 8: "hide from Latest" has no Silo setting.

## Open

### D6. Track changes: replan or stop and restart
Replan keeps the session and is faster; stop + start is simpler. Replan is needed anyway for far seeks on progressive remux (step 10.12), so the plan uses replan for tracks too.

### D7. Thumbhash placeholders
Silo sends `*_thumbhash` for artwork. Moonfin doesn't show blur placeholders today. Ignore for now; revisit after phase 6.

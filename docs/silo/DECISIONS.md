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

## Open

### D2. Artwork when nothing is registered for an item
Cold start, deep links and offline can ask for an image the registry has never seen. Options: a resolver image provider that fetches the item and then loads its artwork (artwork always appears, more code in `cached_network_image_fork`), or an empty URL and the placeholder (simple, but artwork is missing until the item is loaded again). Needed by step 6.3.

### D3. Where display preferences live
Silo has a per-profile settings store (`/settings/values/{key}`), but it only accepts keys defined in its settings contract, so a private `moonfin.` key isn't possible. **Partly answered in 2.7 (2026-10-13):** library order and hidden libraries use Silo's own `ui.library_order` and `ui.disabled_library_ids`. Still open for step 6.19: per-library view settings in Silo's `ui.library_page_state` (profile + device), or local only. Also open, for phase 8: "hide from Latest" has no Silo setting.

### D6. Track changes: replan or stop and restart
Replan keeps the session and is faster; stop + start is simpler. Replan is needed anyway for far seeks on progressive remux (step 10.12), so the plan uses replan for tracks too.

### D7. Thumbhash placeholders
Silo sends `*_thumbhash` for artwork. Moonfin doesn't show blur placeholders today. Ignore for now; revisit after phase 6.

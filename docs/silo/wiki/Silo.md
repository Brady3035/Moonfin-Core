# Silo

*Draft of a wiki page for [Moonfin-Core's wiki](https://github.com/Moonfin-Client/Moonfin-Core/wiki), written with step 17.6. The wiki isn't part of the repository; a maintainer copies this page there once Silo support is merged.*

Moonfin supports [Silo Media Server](https://github.com/Silo-Server/silo-server) as a third server type next to Jellyfin and Emby. It uses Silo's native API (`/api/v2`), so Silo's own features (its playback decisions, sign-in codes, live updates, managed downloads) work as Silo intends.

## Connecting

1. **Add server** and enter Silo's address, the one you open Silo's web app with: `https://silo.example.com`, or on your network `http://192.168.1.20:8090` (8090 is the port Silo's Docker Compose file publishes; a Silo started without Docker listens on 8080).
2. If you enter the address you use for Jellyfin apps (Silo's Jellyfin-compatible service, usually port 8096), Moonfin asks **"Connect to Silo directly?"**. Choose **Use Silo**. **Keep Jellyfin** adds it as a Jellyfin server, which works but without Silo's own features.
3. On your local network, Silo servers that advertise themselves appear under **Discovered servers**. Silo advertises when it listens on all of the machine's addresses and `server.lan_discovery` is on (the default). A Silo in Docker on a bridge network can't be discovered: add it by address.
4. Sign in with a code (shown with a QR code: scan it with a phone signed in to Silo and approve), or with your password.

Moonfin signs in as your account's main profile. Household profiles (picking another profile, profile PINs) aren't supported yet; if the main profile is locked with a PIN, Moonfin can't sign in until the PIN is removed in Silo's web app.

## What's different from Jellyfin and Emby

- Hidden on Silo, because Silo doesn't have them: Live TV and DVR, music, playlists, SyncPlay, remote control of other devices, the admin panel (use Silo's web app), Seerr, retro games, and the features of the Moonfin server plugin.
- **Quick Connect** is Silo's sign-in with a code: eight digits instead of six. To sign another device in, use **Approve a sign-in** in the account menu.
- **Ratings** are Silo's 1 to 5 stars; Moonfin's 0–10 rating is halved and rounded.
- **Hiding from Continue Watching** hides the title on Silo itself, so it is hidden in Silo's web app too.
- **Downloads** go through Silo's managed downloads and show on Silo's dashboard. Converted qualities need transcode-to-file switched on in Silo.
- Books, audiobooks and Silo's server-side download subscriptions aren't supported yet.

## Messages you may see

| Message | What it means |
|---|---|
| This Silo server needs a newer version of Moonfin. | Silo moved to a newer API than this Moonfin speaks. Update Moonfin. |
| This Silo server is too old for this version of Moonfin. | Update Silo. |
| Too many attempts. Try again in … | Silo limits sign-in attempts and code approvals. Wait the time shown. |
| The server is busy or still starting. | Silo is starting up or one of its services is unavailable. Try again shortly. |
| Downloads are switched off on this server. | Your Silo account isn't allowed to download, or downloads are off on the server. |
| Playback isn't available on this Silo server. | Playback is switched off for your account on Silo. |

## For developers

The design, every step and how it was tested are in [`docs/silo/`](https://github.com/Moonfin-Client/Moonfin-Core/tree/main/docs/silo) (roadmap, phases, decisions). The Silo client lives in `packages/server_silo` and `packages/playback_silo`.

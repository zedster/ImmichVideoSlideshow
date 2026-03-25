# Immich Video Slideshow

A lightweight slideshow player for videos stored in an Immich library.

Preview/screenshots at: https://bananasystems.co.uk/home-video-channel
## Platforms Supported

- Apple TV (tvOS)
- Web browser

## Features

- Continuous video playback
- Shuffle playback
- Minimum duration filter (default 10 seconds)
- Designed for large libraries
- Tested with 26k videos in Immich

## Web vs tvOS Feature Comparison

| Capability | Web Player (`web-player`) | tvOS App (`tvos-app`) |
|---|---|---|
| Platform | Browser (desktop/mobile/kiosk) | Native Apple TV (SwiftUI) |
| Core playback | Continuous shuffled playback | Continuous playback with additional native flow control |
| Minimum duration filter | Yes | Yes |
| Favorites mode | Yes (runtime toggle in Admin panel) | Yes (config + in-player control) |
| Hide forever | Yes (archives in Immich via `hide.php`, with confirmation) | Yes (archive/hide flow in native client) |
| Watch count increment | Yes (`watch.php` from playback transitions) | Yes (native/local watch tracking) |
| Info overlay | Full metadata + watched count + QR link | Rich native info fields |
| Stats overlay | Session + SQLite stats in player | Extended library/session stats in native UI |
| Playback controls | Back, skip, pause/play, mute, favorite, fullscreen | Apple TV remote-optimized controls |
| Admin controls | Force resync, favorites-only mode toggle, hide action | Native settings and sync controls |
| Crossfade/preload | Yes (web transition pipeline) | Yes (native playback tuning options) |
| Deployment | PHP web server or Docker | Xcode build/run on Apple TV |

## Project Structure

- `tvos-app/` - Native Apple TV app (Swift/tvOS)
- `web-player/` - PHP web slideshow player
- `docs/screenshots/` - Documentation screenshots

## Installation

### tvOS App

1. Open the tvOS project in Xcode from `tvos-app/HomeVideoChannel/HomeVideoChannel.xcodeproj`.
2. Configure your Immich server URL and API key in the app setup screen.

### Web Player

1. Copy the PHP web player files from `web-player/` to your web server.
2. Configure your Immich API endpoint and credentials.
3. Optional: run with Docker via `web-player/docker-compose.yml`.

## Usage

- Launch the tvOS app on Apple TV to start continuous shuffled playback.
- Open the web player in a browser to run slideshow playback.
- Set a minimum duration to avoid short clips (default is 10 seconds).

## Screenshots

- Apple TV player: `docs/screenshots/appletv-player.png`
- Web player: `docs/screenshots/web-player.png`

## Contributing

See `CONTRIBUTING.md` for contribution workflow.
Mainly created using Codex/GPT 5.3

## Security

See `SECURITY.md` for reporting security issues and deployment hardening notes.

## License

This project is licensed under the Apache License 2.0. See `LICENSE` for details.

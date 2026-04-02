# Immich Video Slideshow

A lightweight slideshow player for videos stored in an Immich library.

Preview/screenshots: https://bananasystems.co.uk/home-video-channel

## Platforms Supported

- Apple TV (tvOS)
- Web browser

## Current Feature Highlights

### tvOS (`tvos-app`)

- Native Apple TV SwiftUI experience optimized for Siri Remote
- Continuous playback with random and sequential playback modes
- Minimum-duration filtering to skip short clips
- Favorites support and hide-forever workflow (archives in Immich)
- Channel selector with tabs for:
  - Time & Place
  - Albums
  - People
  - Search
- Search-driven playback channels (Immich smart search)
- Rich metadata and info overlay
- Library stats screen (totals, activity, top values)
- Local SQLite cache + sync controls for large libraries
- Playback tuning options (crossfade, preload, queue target)
- Feedback screen with QR flow + diagnostics summary
- **Support the App** screen with QR handoff to website support page
- Localisation-ready UI using String Catalogs (`Localizable.xcstrings`)

### Web Player (`web-player`)

- Continuous slideshow playback in browser
- Favorites mode and hide controls
- Metadata/stats overlays
- Admin and sync controls
- Optional Docker deployment

## Web vs tvOS Feature Comparison

| Capability | Web Player (`web-player`) | tvOS App (`tvos-app`) |
|---|---|---|
| Platform | Browser (desktop/mobile/kiosk) | Native Apple TV (SwiftUI) |
| Core playback | Continuous shuffled playback | Continuous playback with native flow control |
| Minimum duration filter | Yes | Yes |
| Favorites mode | Yes (runtime toggle in admin panel) | Yes (settings + in-player control) |
| Hide forever | Yes | Yes |
| Watch count increment | Yes | Yes |
| Info overlay | Metadata + watched count + QR links | Rich native info fields |
| Stats overlay | Session + SQLite stats | Extended library/session stats UI |
| Search channel support | Basic web search flow | Native search tab + channel loop |
| Support/donation flow | Website-only | Dedicated tvOS support QR screen |
| Deployment | PHP server or Docker | Xcode build/run on Apple TV |

## Version History (tvOS)

### 2.5

- Added **Support the App** in Settings with dedicated support screen
- Added large support QR flow to `https://bananasystems.co.uk/home-video-channel/support`
- Added optional non-sensitive support URL tracking parameters (`source`, `app`, `av`, `bn`)
- Migrated user-facing text to modern String Catalog localisation workflow
- Improved localisation readiness for dynamic labels, formatting, and accessibility text

### 2.4

- Expanded channel navigation with richer tabbed channel browsing
- Improved synced metadata presentation (albums/people context)
- Added and polished phone-based QR flows around support/feedback experience
- Playback and focus stability improvements

### 2.3

- UI and setup polish pass for better living-room readability
- Settings and onboarding refinements for easier first-time configuration
- Quality and reliability improvements across playback and navigation

### 2.2

- Improved library stats UX and data visibility
- Playback control/focus fixes (including seeking behavior)
- General stability improvements across everyday playback

## Project Structure

- `tvos-app/` - Native Apple TV app (Swift/tvOS)
- `web-player/` - PHP web slideshow player
- `docs/screenshots/` - Documentation screenshots

## Installation

### tvOS App

1. Open `tvos-app/HomeVideoChannel/HomeVideoChannel.xcodeproj` in Xcode.
2. Build and run on Apple TV simulator or device.
3. Configure Immich URL and API key in the app setup screen.

### Web Player

1. Copy `web-player/` files to your web server.
2. Configure Immich endpoint and credentials.
3. Optional: run with Docker via `web-player/docker-compose.yml`.

## Usage

- Launch the tvOS app to start channel-style playback from your Immich library.
- Use Settings to tune playback, sync behavior, diagnostics, feedback, and support options.
- Open the web player in a browser for web-based slideshow playback.

## Screenshots

- Apple TV player: `docs/screenshots/appletv-player.png`
- Web player: `docs/screenshots/web-player.png`

## Contributing

See `CONTRIBUTING.md` for contribution workflow.

## Security

See `SECURITY.md` for reporting security issues and deployment hardening notes.

## License

Apache License 2.0. See `LICENSE` for details.

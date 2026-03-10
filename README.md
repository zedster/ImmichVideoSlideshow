# Immich Video Slideshow

A lightweight slideshow player for videos stored in an Immich library.

Demo: https://bananasystems.co.uk/immich-video-slideshow

## Platforms Supported

- Apple TV (tvOS)
- Web browser

## Features

- Continuous video playback
- Shuffle playback
- Minimum duration filter (default 10 seconds)
- Designed for large libraries
- Tested with 26k videos

## Project Structure

- `tvos-app/` - Native Apple TV app (Swift/tvOS)
- `web-player/` - PHP web slideshow player
- `docs/screenshots/` - Documentation screenshots

## Installation

### tvOS App

1. Open the tvOS project in Xcode from `tvos-app/ImmichVideoChannel/ImmichVideoChannel.xcodeproj`.
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

## Security

See `SECURITY.md` for reporting security issues and deployment hardening notes.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
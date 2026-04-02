# Home Video Channel (tvOS)

Native Apple TV app for running an Immich video library as a continuous TV-style channel.

## Core Features

- Continuous playback with random and sequential modes
- Minimum clip duration filtering
- Channel selector tabs for:
  - Time & Place
  - Albums
  - People
  - Search
- Favorites and hide-forever controls
- Metadata/info overlay with rich video details
- Library stats screen (totals, activity, top values)
- SQLite cache + sync controls for large libraries
- Playback tuning (crossfade, preload, queue target)
- Feedback flow with QR code and diagnostics summary
- Support flow with dedicated **Support the App** screen and QR code
- String Catalog-based localisation readiness (`Localizable.xcstrings`)

## Run in Xcode

1. Open `tvos-app/HomeVideoChannel/HomeVideoChannel.xcodeproj` in Xcode.
2. Select scheme `HomeVideoChannel`.
3. Select an Apple TV simulator or physical Apple TV.
4. Build and run.
5. In app setup, add your Immich URL and API key.

## Version History

### 2.5

- Added **Support the App** Settings entry and dedicated support screen
- Added support QR handoff to:
  - `https://bananasystems.co.uk/home-video-channel/support`
- Added optional non-sensitive support URL tracking parameters (`source`, `app`, `av`, `bn`)
- Migrated and organized user-facing strings into String Catalog localisation flow

### 2.4

- Expanded channel experience with richer tabbed channel browsing
- Improved synced metadata presentation and browsing context
- Added/expanded QR-based support and feedback polish
- Playback and focus reliability improvements

### 2.3

- Setup and settings UX polish for better couch-distance readability
- Navigation and playback quality improvements
- General stability and product polish pass

### 2.2

- Improved library stats screen and data visibility
- Playback control and focus behavior fixes
- General stability improvements

## Notes

- Designed for large libraries; local SQLite cache is recommended.
- The support feature is optional and does not unlock or gate app features.
- Payments are not processed inside the tvOS app.

## License

Apache License 2.0. See root `LICENSE`.

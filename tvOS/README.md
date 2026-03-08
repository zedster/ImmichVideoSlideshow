# Immich Channel for tvOS (Swift)

This folder contains a SwiftUI/tvOS implementation of the Immich video channel experience.

## What it includes

- Initial setup screen for required config:
  - Immich URL
  - Immich API key
  - min duration
  - optional toggles/settings (`debug`, `onlyFavorites`, crossfade options, queue/preload)
  - SQLite cache settings (`useSQLiteCache`, `syncOnStartup`, `syncPageSize`, `syncMaxPages`)
  - `Force Sync Now` action in settings
  - live sync panel showing:
    - in-progress state
    - pages fetched
    - rows upserted
    - last sync timestamp
    - last sync error
- Dual-player channel playback model:
  - background fetch queue of upcoming videos
  - pre-buffer next video while current plays
  - crossfade or hard cut transitions (toggle in settings)
  - continuous playback with no page reload concept
- Local SQLite cache model:
  - metadata is synced from Immich into local SQLite
  - random selection can come from SQLite cache (same spirit as PHP app)
  - if cache has no qualifying videos and sync-on-startup is enabled, app triggers sync automatically
- Fallback retry behavior if no eligible video is found.

## Security model

- API key is stored locally on Apple TV (`UserDefaults`) and used only in app-side requests.
- API key is never sent to browser JS (this is a native app, no browser layer).

## Build in Xcode

1. Open Xcode and create a new **tvOS App** project (SwiftUI lifecycle).
2. Add all files from `ImmichChannelTV/` into the target.
3. Set minimum deployment target to tvOS 16+ (or newer).
4. Build and run on Apple TV or simulator.

## Runtime behavior notes

- Uses Immich endpoint: `POST /api/search/metadata` to find random video candidates.
- Uses Immich playback endpoint: `GET /api/assets/{id}/video/playback` via `AVURLAsset` with `x-api-key` header.
- Retries up to 20 attempts for eligible videos (`duration >= minDuration`, plus favorites filter if enabled).
- SQLite cache is stored in app support directory and includes `videos` and `sync_state` tables.

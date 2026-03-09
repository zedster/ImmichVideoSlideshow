# Immich Channel for tvOS (Swift)

This folder contains the native SwiftUI/tvOS app for fullscreen Immich video playback.

## Current feature set

- Setup and settings UI for:
  - Immich URL and API key
  - minimum duration, random batch size, picture quality
  - playback order:
    - `Random`
    - `Sequential Oldest -> Newest` (by capture date)
    - `Sequential Newest -> Oldest` (by capture date)
  - favorites-only mode
  - smooth playback tuning (crossfade, preload window, queue size)
  - SQLite cache and sync controls
  - debug logging
  - tvOS-friendly boolean `On/Off` pickers to keep focused selection readable
- Playback progress controls:
  - `Reset Playback Progress` in settings for sequential modes
  - sequential progress is persisted and resumed between launches
- Sync controls and status:
  - `Force Sync Now`
  - sync status panel (in progress, pages fetched, rows upserted, last sync at/error)
- Library Stats section in settings:
  - total videos
  - total watched plays
  - watched plays in last 7 and 30 days
  - videos watched at least once
  - current session watched count
  - favorites and hidden counts
  - most popular camera / codec / file type / place / year
  - top 5 camera / codec / file type / place / year summaries
- In-player actions:
  - skip
  - favorite/unfavorite
  - `Hide Forever` (with confirmation dialog)
    - warning clearly states this hides in Immich too
    - unhide is only available from Immich web interface
- Remote behavior:
  - controls auto-hide after inactivity and return on input
  - play/pause remote action always toggles playback

## Playback ordering details

- Sequential order is based on video capture date (`date taken`).
- In sequential modes, the app records the last played asset ID in local SQLite state and resumes from that point.
- Legacy config value `sequential` is treated as `sequential_oldest` for backward compatibility.

## Local SQLite model

- Cache lives in the app support directory.
- Tables include:
  - `videos`
  - `sync_state`
  - `watch_events`
- Synced/enriched metadata includes fields used for stats, such as camera, location/place, year, codec, and file type.
- `file_type` is inferred from file extension.
- `video_codec` is best-effort from Immich metadata (with MIME fallback when needed).

## Security model

- API key is stored locally on Apple TV (`UserDefaults`) and used only for app-side requests.
- API key is never exposed to browser JavaScript (native app only).

## Build in Xcode

1. Open `tvOS/xCodeProj/ImmichVideoChannel/ImmichVideoChannel.xcodeproj`.
2. Select scheme `ImmichVideoChannel`.
3. Build/run for Apple TV device or tvOS simulator (tvOS 16+).

## Git version bump hook

- Commits can auto-bump tvOS app versions via `.githooks/pre-commit`.
- The hook runs `tvOS/scripts/bump_tvos_version.sh` and updates:
  - `CURRENT_PROJECT_VERSION` (+1 each commit)
  - `MARKETING_VERSION` (patch component +1 each commit)
- Ensure hooks are enabled in your clone:

```bash
git config core.hooksPath .githooks
```

## Runtime behavior notes

- Video discovery/sync uses `POST /api/search/metadata`.
- Playback uses `GET /api/assets/{id}/video/playback` via `AVURLAsset` with `x-api-key`.
- If no eligible cached videos are available and startup sync is enabled, the app triggers sync automatically.
- If no eligible video is found, retry logic is applied before surfacing a playback error.

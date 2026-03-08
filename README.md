# Immich Video Kiosk

Small Dockerized PHP app that continuously plays random Immich videos in a fullscreen browser slideshow.

## 1) Generate an Immich API key

1. Open Immich in your browser.
2. Go to your user account settings.
3. Open the API keys section.
4. Create a new key and copy it.

Note: Menu labels can vary slightly by Immich version, but API key creation is in your account/user settings.

## 2) Configure environment variables

Copy `.env.example` to `.env` and set your values:

```bash
cp .env.example .env
```

Required variables:

- `IMMICH_URL` - Base URL of your Immich server, e.g. `http://immich:2283`
- `IMMICH_API_KEY` - Your Immich API key
- `MIN_DURATION` - Minimum video length in seconds (default `10`)
- `PRELOAD_SECONDS_BEFORE_END` - Seconds before end of current clip to begin preparing transition (default `4`)
- `CROSSFADE_ENABLED` - Enable smooth crossfade between clips (`true` or `false`, default `true`)
- `CROSSFADE_DURATION` - Crossfade duration in milliseconds (default `450`)
- `QUEUE_TARGET_SIZE` - Number of upcoming clips to keep queued in the browser (default `2`)
- `RANDOM_BATCH_SIZE` - Fallback live mode batch size if SQLite cache is disabled/unavailable (default `20`)
- `USE_SQLITE_CACHE` - Enable local SQLite metadata cache and random DB selection (default `true`)
- `SQLITE_PATH` - SQLite database path inside container (default `/var/www/html/data/videos.sqlite`)
- `SYNC_ON_STARTUP` - Automatically sync metadata when DB is empty/no qualifying videos (default `true`)
- `SHOW_SYNC_STATUS` - Show live sync/import status page when hitting backend sync endpoint directly (default `true`)
- `ONLY_FAVORITES` - Default to favorites-only playback (`true` or `false`, default `false`)
- `SHOW_QR_CODE` - Show/hide QR + "Open in Immich" panel (default `true`)
- `SYNC_PAGE_SIZE` - Number of videos to request per sync page from Immich (default `200`)
- `SYNC_MAX_PAGES` - Maximum pages to scan per sync run (default `200`)
- `DEBUG` - Set to `true` to include debug fields in `api.php` responses and enable PHP error display (default `false`)

## 3) Run

```bash
docker compose up -d
```

This uses the stock `php:8.2-apache` image and mounts `index.php`, `api.php`, `helpers.php`, `video.php`, `watch.php`, and `favorite.php` into Apache.
It also mounts `./data` for persistent SQLite cache storage.
SQLite must be writable at `SQLITE_PATH`; the app now errors clearly if it cannot create/open that exact path.

## 4) Open slideshow

Browse to:

- http://localhost:8095

## Logs and debug output

- Application logs are written with `error_log()` and go to container logs.
- View logs with:

```bash
docker compose logs -f
```

- Set `DEBUG=true` in `.env` for extra debug fields in `/api.php` JSON responses (request ID, attempts, sync diagnostics).
- Keep `DEBUG=false` for normal kiosk usage.

## Force a metadata resync

- Open:
  - `http://localhost:8095/?sync=1`

This triggers a fresh metadata sync from Immich into SQLite (videos + duration + exif/location + faces count), then picks a random qualifying video from DB through the frontend.
For a live sync progress page, open `/api.php?sync=1` directly when `SHOW_SYNC_STATUS=true`.

## How it works

- `api.php` syncs video metadata from `POST /api/search/metadata` into local SQLite.
- Cached fields include:
  - `id`, `duration`, `originalFileName`, `originalPath`
  - `is_favorite` (heart toggle, synced to Immich favorite state)
  - `watched_count` (incremented when a video reaches `ended`)
  - location fields from `exifInfo` (when present)
  - faces count from `people` (when present)
- Playback selection is:
  - `SELECT ... WHERE duration >= MIN_DURATION ORDER BY RANDOM() LIMIT 1`
- If SQLite is disabled/unavailable, it falls back to live random batch API selection.
- `index.php` is the frontend shell and fetches slideshow payloads from `/api.php?next=1`.
- Shared SQL/Immich utility helpers are centralized in `helpers.php` and reused by `api.php`, `video.php`, `watch.php`, and `favorite.php`.
- The browser plays `/video.php?id=<assetId>` fullscreen.
- The browser keeps two overlaid `<video>` players and preloads the next clip in the hidden player.
- UI controls include `Skip` and `Mute`.
- `video.php` proxies Immich playback from:
  - `GET /api/assets/{id}/video/playback`
- `video.php` sends `x-api-key` server-side, so the API key is never exposed to the browser.
- Playback continues without page reloads:
  - next clips are fetched in the background from `api.php?next=1`
  - queue is kept topped up in JS
  - transition is instant cut or crossfade depending on settings

## Architecture

- `index.php`: frontend UI/player shell, keyboard shortcuts, and client-side controls.
- `api.php`: slideshow orchestration endpoint (sync, selection, metadata/stats payloads).
- `helpers.php`: shared constants, API helpers, SQLite helpers, migrations, and response helpers.
- `video.php`: secure playback proxy to Immich.
- `favorite.php`: toggles favorite state in Immich and local SQLite cache.
- `watch.php`: increments local `watched_count`.

## API response format

- JSON endpoints (`api.php`, `favorite.php`, `watch.php`) return:
  - `ok` (`true`/`false`)
  - `error_code` on failures (stable machine-readable code)
  - `error` on failures (human-readable message)

## Endpoint reference

- `GET /api.php?next=1[&favOnly=1][&sync=1]`
  - Returns next playable video payload.
- `POST /favorite.php?id=<assetId>&favorite=<0|1>`
  - Updates Immich + local SQLite favorite state.
- `POST /watch.php?id=<assetId>`
  - Increments local watch counter.
- `GET /video.php?id=<assetId>`
  - Streams video playback proxied through server.

## SQLite schema migration changelog

- Migrations are tracked in `schema_migrations` and applied from `helpers.php::initSchema()`.
- Current migration versions:
  - `1` `create_videos_and_sync_state_tables`
  - `2` `add_capture_date_column`
  - `3` `add_watched_count_column`
  - `4` `add_is_favorite_column`
  - `5` `add_camera_codec_resolution_columns`

## Troubleshooting

- `error_code=E_MISSING_IMMICH_ENV`
  - Check `IMMICH_URL` and `IMMICH_API_KEY` in `.env`.
- `error_code=E_PDO_SQLITE_NOT_LOADED`
  - Verify PHP image has `pdo_sqlite` enabled.
- `error_code=E_SQLITE_INITIALIZATION_FAILED`
  - Confirm `SQLITE_PATH` parent directory is writable in container.
- Playback does not start
  - Check `docker compose logs -f` and verify `video.php?id=<assetId>` is reachable.

## Releases

- Follow SemVer tags (`vMAJOR.MINOR.PATCH`) for GitHub releases.
- Add release notes from `CHANGELOG.md`.

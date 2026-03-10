# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Frontend/backend split: `index.php` frontend shell + `api.php` JSON backend.
- Shared `helpers.php` for SQL, Immich, sync, and utility logic.
- Standardized JSON response helpers and stable `error_code` taxonomy.
- SQLite schema migration tracking table: `schema_migrations`.
- Keyboard shortcuts:
  - `ArrowLeft` back
  - `ArrowRight` skip
  - `f` favorite
  - `s` stats
  - `i` info
  - `Space` pause/play

### Changed

- Caption now uses month + year when available.
- Docker mounts include `api.php` and `helpers.php`.

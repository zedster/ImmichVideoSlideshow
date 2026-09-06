# Development Summary

## Short videos below 10 seconds

### Problem

The tvOS app correctly filters candidates using Immich's metadata duration, but it did not validate the duration of the media returned for playback. A metadata mismatch (for example, a 2–4 second transcoded asset reported as 10+ seconds) could therefore bypass the filter.

### Resolution

- Kept the default minimum duration at `10` seconds.
- Centralized the duration predicate so metadata-based selection rejects durations below 10 seconds.
- Validate the AVFoundation media duration after the playback item becomes ready, before playback or preload. Clips below the configured threshold (or with an unavailable duration) are skipped.
- Added tests for the default configuration and its 10-second boundary.

The setting remains configurable, but `10` seconds is the default and is now enforced against the actual playback asset as well as Immich metadata.

## Version

The tvOS app version and build number have been incremented from `2.5` to `2.6`.

## Time & Place channels

- Added Last month, Last 3 months, Last Year, and Last 5 years as rolling calendar periods through today, including the start date and excluding future dates after today. Month-end and leap-year boundaries use calendar arithmetic.
- Added Winter (December–February), Summer (June–August), Spring (March–May), and Autumn (September–November), across all years using meteorological seasons. Northern Hemisphere is the default; Settings → Playback → Season Hemisphere allows switching to Southern.
- Connected the channels to counts, random/sequential SQLite playback, direct API playback, and persisted selection. Selecting another channel or search clears the time filter; older saved configurations default to no time filter.
- Preserved the existing 10-second minimum-duration changes and version 2.6.
- Validation: tvOS simulator build and all five unit tests passed. Added unit coverage for rolling boundaries, future-date exclusion, season coverage, and configuration persistence.

## Season hemisphere setting

- Added a saved Northern/Southern Season Hemisphere choice under Settings → Playback. New installations and older saved configurations default to Northern.
- Southern seasons use Summer December–February, Autumn March–May, Winter June–August, and Spring September–November.
- The setting applies to season channel counts, random and sequential SQLite playback, and direct API playback. Changing it uses the existing automatic settings save and playback restart.
- Rolling date channels are unaffected. Season subtitles now refer to the hemisphere selected in Settings.
- Validation: tvOS simulator build and all seven unit tests passed, including hemisphere defaults/persistence and Southern season mappings; `git diff --check` passed.


## Apple TV resume recovery

- Observe scene activity explicitly. On suspension, cancel coordinator work, remove observers/timers, release playback items, and save the current position. On return, create fresh players and reload the current video at that position while preserving a deliberate pause, queue, history, and viewing-session start time.
- Replace the continuation/task-group loading race with a cancellation-aware, bounded readiness wait. Unknown items now time out after 12 seconds; already-failed items fail immediately.
- Track coordinator tasks and protect callbacks and cleanup with a playback generation. Stopping resets bootstrap, transition, preload, and queue-fetch state; cancelled work cannot overwrite the next session or surface cancellation as a playback error. Metadata sync also checks cancellation.
- Recover assigned videos that fail or stop advancing for 20 seconds. Resume unexpected player pauses and retry transitions after an ended video. Deliberate pauses remain paused.
- Prevent simultaneous bootstrap attempts and preload/transition collisions; bound duplicate candidate fetch attempts for small libraries.
- Regression coverage includes readiness timeout/cancellation, watchdog progress and seek handling, foreground player recreation/pause preservation, and cancellation of an in-flight network bootstrap.
- Validation: tvOS simulator build and all 13 unit tests passed, including six recovery regression tests; `git diff --check` passed.
- Physical Apple TV validation remains necessary: return from Home and sleep during playback, buffering, and crossfade; repeat with playback manually paused and with the Immich server temporarily unavailable.

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


## Settings crash mitigation and visual refresh

- Split Settings into six independently built cards and concrete field, toggle, choice, action, and row components. Each card has a type-erased boundary so the full layout no longer carries the deeply nested generic types implicated by the Apple TV crash trace.
- Put Playback and Smooth Channel first, followed by Connection / Local Cache and Feedback / Tools. Added a compact header, smaller help QR code, consistent spacing, darker cards, and teal headings and values while retaining white remote-focus highlights.
- Show settings errors near the top. Preserve existing controls, bindings, actions, navigation, and automatic saving; avoid publishing unchanged configuration on save.
- Added a simulator rendering regression test for the configured Settings screen. Physical Apple TV verification is still needed to confirm the reported stack-exhaustion crash is resolved.

- Settings now presents as a full-screen cover instead of a constrained sheet and expands to the available screen size. Added a Done button, root-screen Back/Menu dismissal, initial field focus, and focus sections for directional navigation between cards.


## Settings sidebar and opaque Library Stats

- Replaced the card grid with a fixed category sidebar and one scrollable settings panel. The header and prominent 220 × 68 Done button remain visible; existing settings, navigation destinations, and actions remain available.
- Settings and Library Stats share an opaque dark background that fills the screen and safe areas, preventing video from showing through Stats.
- Done and remote Back both validate and save before closing. Invalid input keeps Settings open, reveals the appropriate category, and focuses the offending field. Valid changes still save automatically; returning from a child screen preserves the current draft.
- Added server URL and finite-number validation, plus regression tests for validation and Library Stats rendering.
- Validation: a clean tvOS simulator build and all 17 unit tests passed, including Settings and Library Stats rendering; `git diff --check` passed. Physical Siri Remote navigation and the original hardware crash still need device verification.


## Buffering diagnostics and preload comparison

- Compact debug overlay identifies camera make/model (or unknown), filename, observed download throughput, advertised stream bitrate, playable buffer seconds, AVFoundation stall count, accumulated waiting time, format, and preload state. Download throughput is an aggregate access-log measurement, not an instantaneous speed test; waiting time includes startup waits and is distinct from AVFoundation's stall count.
- Reset format/history/wait counters immediately when the active media item changes, including next/back and foreground recovery. Late format lookups are ignored if the player has moved on.
- Refresh diagnostics from the recovery timer even when the playhead is frozen. Emit structured `[PlaybackDiagnostics]` JSON on wait changes, low-buffer/waiting intervals, periodic healthy samples, format completion, and stop. Logs include asset identification, waiting reason, buffer flags, transfer counters, dropped frames, error code, quality preference, preload/sync state, and per-item history. URLs and request headers are excluded from these snapshots.
- Settings → Tools → Preload Next Video is enabled by default, including for older saved configurations. Turning it off skips hidden-player preparation and early crossfade transitions; the next item loads at the end (or on manual navigation). Metadata queue selection continues. The existing settings restart releases any previously prepared item.
- To investigate DJI Mini 2 / GoPro Hero 11 clips, enable Debug Logging and compare the same file and quality preference with preloading on/off. Capture `[PlaybackDiagnostics]` lines before, during, and after a stall. Network connection type and whether the server URL uses a local or public/proxy route remain useful context for interpreting results.
- Validation: tvOS simulator build and all 20 unit tests passed; added preload preference persistence/default tests and wait timing/reset tests. `git diff --check` passed. Real-device buffering comparisons remain to be performed.

## Camera channels

- Added Albums → Automatic filters → By camera type. It lists all detected camera manufacturers (for example, All GoPro) followed by individual make/model channels (for example, GoPro HERO11 Black), with qualifying video counts.
- Camera selections are persisted and apply exact, case-insensitive make/model matching to cache-backed random and sequential playback. They respect the current duration threshold and hidden-video state, and selecting a different channel clears the camera filter.
- Older saved configurations default to no camera filter. Validation: tvOS simulator build and all 21 unit tests passed; `git diff --check` passed.

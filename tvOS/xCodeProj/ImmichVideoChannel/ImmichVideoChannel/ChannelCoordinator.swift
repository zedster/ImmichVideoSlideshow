import AVFoundation
import SwiftUI

struct VideoInfoField: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
}

@MainActor
final class ChannelCoordinator: ObservableObject {
    @Published var playerA = AVPlayer()
    @Published var playerB = AVPlayer()
    @Published var activeIndex: Int = 0
    @Published var opacityA: Double = 1
    @Published var opacityB: Double = 0
    @Published var title: String = "Loading..."
    @Published var captionText: String = ""
    @Published var dateLocationText: String = ""
    @Published var fallbackMessage: String = ""
    @Published var statusText: String = ""
    @Published var recentDebugMessages: [String] = []
    @Published var playbackProgress: Double = 0
    @Published var secondsLeftText: String = "--:--"
    @Published var elapsedText: String = "0:00"
    @Published var totalDurationText: String = "--:--"
    @Published var isBuffering: Bool = false
    @Published var currentInfoFields: [VideoInfoField] = []
    @Published var currentImmichAssetURL: String = ""
    @Published var canGoBack: Bool = false
    @Published var currentIsFavorite: Bool = false
    @Published var canHideToAlbum: Bool = false
    @Published var hideUpdateInProgress: Bool = false
    @Published var isPlaybackPaused: Bool = false
    @Published var favoriteUpdateInProgress: Bool = false
    @Published var isSyncing: Bool = false
    @Published var syncPagesFetched: Int = 0
    @Published var syncRowsUpserted: Int = 0
    @Published var syncLastSyncAt: String = "-"
    @Published var syncLastError: String = ""
    @Published var statsTotalVideos: Int = 0
    @Published var statsTotalWatchedPlays: Int = 0
    @Published var statsWatchedPlays7Days: Int = 0
    @Published var statsWatchedPlays30Days: Int = 0
    @Published var statsVideosWatchedAtLeastOnce: Int = 0
    @Published var statsFavoritesCount: Int = 0
    @Published var statsHiddenCount: Int = 0
    @Published var sessionVideosWatchedCount: Int = 0
    @Published var statsMostPopularCamera: String = "-"
    @Published var statsMostPopularCodec: String = "-"
    @Published var statsMostPopularFileType: String = "-"
    @Published var statsMostPopularPlace: String = "-"
    @Published var statsMostPopularYear: String = "-"
    @Published var statsTopCamerasSummary: String = "-"
    @Published var statsTopCodecsSummary: String = "-"
    @Published var statsTopFileTypesSummary: String = "-"
    @Published var statsTopPlacesSummary: String = "-"
    @Published var statsTopYearsSummary: String = "-"
    @Published var statsLastError: String = ""
    @Published var shouldOpenSetup: Bool = false
    @Published var setupErrorMessage: String = ""

    private let client: ImmichAPIClient
    private let configStore: ConfigStore
    private let store: SQLiteVideoStore
    private lazy var syncService = VideoSyncService(client: client, store: store)

    private var queue: [VideoCandidate] = []
    private var history: [VideoCandidate] = []
    private var currentItem: VideoCandidate?
    private var transitionInProgress = false
    private var preparingNext = false
    private var nextPreparedId = ""
    private var inflightQueueFetches = 0
    private var started = false
    private var consecutivePlaybackFailures = 0
    private let maxConsecutivePlaybackFailures = 5
    private var hiddenAlbumId = ""
    private var hiddenAssetIds = Set<String>()
    private var sequentialLastAssetId: String?
    private var sequentialStateLoaded = false

    private var timeObserver: Any?
    private var timeObserverPlayer: AVPlayer?
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private var queueTimer: Timer?
    private var recoveryTimer: Timer?

    init(configStore: ConfigStore, client: ImmichAPIClient = ImmichAPIClient(), store: SQLiteVideoStore = SQLiteVideoStore()) {
        self.configStore = configStore
        self.client = client
        self.store = store
    }

    deinit {
        Task { @MainActor in
            teardownObservers()
            queueTimer?.invalidate()
            recoveryTimer?.invalidate()
        }
    }

    func start() {
        guard configStore.config.isConfigured else {
            fallbackMessage = "Please complete setup first"
            addDebugMessage("Start blocked: app not configured")
            return
        }
        guard !started else { return }
        started = true
        addDebugMessage("Channel start")

        setupEndObserver()
        applyMuteState(readMutedPreference())
        updateStatus()
        Task {
            let startedAt = ISO8601DateFormatter().string(from: Date())
            try? await store.setSyncState(key: "session_started_at", value: startedAt)
        }
        Task {
            await checkHiddenAlbumAccessAtStartup()
        }

        Task {
            await bootstrapPlayback()
        }

        queueTimer?.invalidate()
        queueTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fillQueueIfNeeded()
            }
        }

        recoveryTimer?.invalidate()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.currentItem == nil, !self.transitionInProgress else { return }
                await self.bootstrapPlayback()
            }
        }
    }

    func stop() {
        addDebugMessage("Channel stop")
        started = false
        queueTimer?.invalidate()
        recoveryTimer?.invalidate()
        queueTimer = nil
        recoveryTimer = nil
        teardownObservers()
        playerA.pause()
        playerB.pause()
    }

    func restart() {
        addDebugMessage("Channel restart requested")
        stop()
        queue = []
        history = []
        currentItem = nil
        nextPreparedId = ""
        sequentialLastAssetId = nil
        sequentialStateLoaded = false
        hiddenAlbumId = ""
        hiddenAssetIds = []
        consecutivePlaybackFailures = 0
        statsTotalVideos = 0
        statsTotalWatchedPlays = 0
        statsWatchedPlays7Days = 0
        statsWatchedPlays30Days = 0
        statsVideosWatchedAtLeastOnce = 0
        statsFavoritesCount = 0
        statsHiddenCount = 0
        sessionVideosWatchedCount = 0
        statsMostPopularCamera = "-"
        statsMostPopularCodec = "-"
        statsMostPopularFileType = "-"
        statsMostPopularPlace = "-"
        statsMostPopularYear = "-"
        statsTopCamerasSummary = "-"
        statsTopCodecsSummary = "-"
        statsTopFileTypesSummary = "-"
        statsTopPlacesSummary = "-"
        statsTopYearsSummary = "-"
        statsLastError = ""
        shouldOpenSetup = false
        setupErrorMessage = ""
        fallbackMessage = ""
        title = "Loading..."
        captionText = ""
        dateLocationText = ""
        playbackProgress = 0
        secondsLeftText = "--:--"
        elapsedText = "0:00"
        totalDurationText = "--:--"
        isBuffering = false
        currentInfoFields = []
        currentImmichAssetURL = ""
        canGoBack = false
        currentIsFavorite = false
        canHideToAlbum = false
        hideUpdateInProgress = false
        isPlaybackPaused = false
        favoriteUpdateInProgress = false
        opacityA = 1
        opacityB = 0
        activeIndex = 0
        start()
    }

    func clearDebugMessages() {
        recentDebugMessages = []
    }

    func acknowledgeSetupOpenRequest() {
        shouldOpenSetup = false
    }

    func skip() {
        addDebugMessage("Skip requested")
        Task {
            await transitionToNext(reason: "manual_skip")
        }
    }

    func toggleMute() {
        let next = !activePlayer().isMuted
        applyMuteState(next)
        saveMutedPreference(next)
    }

    func seek(toNormalizedProgress progress: Double) {
        let clamped = max(0, min(1, progress))
        guard let item = activePlayer().currentItem else { return }
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite, duration > 0 else { return }

        let targetSeconds = clamped * duration
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        activePlayer().seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        onTick(current: targetSeconds)
    }

    func seek(bySeconds delta: Double) {
        guard let item = activePlayer().currentItem else { return }
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite, duration > 0 else { return }

        let current = CMTimeGetSeconds(activePlayer().currentTime())
        guard current.isFinite else { return }

        let targetSeconds = max(0, min(duration, current + delta))
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        activePlayer().seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        onTick(current: targetSeconds)
    }

    func muteButtonLabel() -> String {
        activePlayer().isMuted ? "Unmute" : "Mute"
    }

    func forceSyncNow() {
        addDebugMessage("Manual sync requested")
        Task {
            await runForceSync()
        }
    }

    func resetPlaybackProgress() {
        Task {
            await resetSequentialProgress()
        }
    }

    func refreshLibraryStats() {
        Task {
            await loadLibraryStats()
        }
    }

    func favoriteButtonLabel() -> String {
        currentIsFavorite ? "Unfavorite" : "Favorite"
    }

    func favoriteButtonSystemImage() -> String {
        currentIsFavorite ? "heart.fill" : "heart"
    }

    func hideButtonSystemImage() -> String {
        "eye.slash"
    }

    func playPauseButtonSystemImage() -> String {
        isPlaybackPaused ? "play.fill" : "pause.fill"
    }

    func togglePlayPause() {
        let player = activePlayer()
        if isPlaybackPaused {
            player.play()
            isPlaybackPaused = false
            updateBufferingState(for: player)
            addDebugMessage("Playback resumed")
        } else {
            player.pause()
            isPlaybackPaused = true
            isBuffering = false
            addDebugMessage("Playback paused")
        }
    }

    func goBack() {
        addDebugMessage("Back requested")
        Task {
            await transitionToPrevious(reason: "manual_back")
        }
    }

    func toggleFavorite() {
        guard let currentItem else {
            addDebugMessage("Favorite ignored: no current item")
            return
        }
        let nextValue = !currentItem.isFavorite
        Task {
            await setFavorite(for: currentItem, to: nextValue)
        }
    }

    func hideCurrentVideo() {
        guard let currentItem else {
            addDebugMessage("Hide ignored: no current item")
            return
        }
        guard canHideToAlbum else {
            addDebugMessage("Hide unavailable: archive access not ready")
            return
        }
        guard !hideUpdateInProgress else {
            addDebugMessage("Hide skipped: update in progress")
            return
        }

        hideUpdateInProgress = true
        let target = currentItem
        Task {
            defer { self.hideUpdateInProgress = false }
            addDebugMessage("Hide requested: \(target.title)")

            do {
                try await client.archiveAsset(assetId: target.id, isArchived: true, config: configStore.config)
                if configStore.config.useSQLiteCache {
                    try await store.initializeSchema()
                    try await store.setHidden(assetId: target.id, isHidden: true)
                }
                applyHiddenStateLocally(assetId: target.id, isHidden: true)
                fallbackMessage = "Hidden: \(target.title)"
                addDebugMessage("Archived (locked): \(target.title)")
                await transitionToNext(reason: "manual_hide")
            } catch {
                fallbackMessage = "Hide failed: \(error.localizedDescription)"
                if configStore.config.debug {
                    print("[ChannelCoordinator] hide failed: \(error)")
                }
                addDebugMessage("Hide failed: \(target.title)")
            }
        }
    }

    private func bootstrapPlayback() async {
        do {
            if shouldUseSQLiteSelection() {
                try await store.initializeSchema()
                syncLastSyncAt = (try await store.getSyncState(key: "last_sync_at")) ?? "-"
                if configStore.config.syncOnStartup {
                    let count = try await store.countQualifying(minDuration: configStore.config.minDuration, onlyFavorites: configStore.config.onlyFavorites)
                    if count == 0 {
                        await runForceSync(silent: true)
                    }
                }
            }

            let first = try await fetchNextCandidate()
            try await playOnActivePlayer(first)
            clearPlaybackFailureState()
            await fillQueueIfNeeded()
            await loadLibraryStats()
            addDebugMessage("Bootstrap playback started")
        } catch {
            registerPlaybackFailure("Could not load initial video. Retrying...", error: error)
            if configStore.config.debug {
                print("[ChannelCoordinator] bootstrap failed: \(error)")
            }
            addDebugMessage("Bootstrap failed: \(error.localizedDescription)")
        }
    }

    private func checkHiddenAlbumAccessAtStartup() async {
        canHideToAlbum = true
        hiddenAlbumId = ""
        addDebugMessage("Hide capability: archive/locked mode enabled")
    }

    private func runForceSync(silent: Bool = false) async {
        guard shouldUseSQLiteSelection() else {
            addDebugMessage("Sync skipped: SQLite cache disabled")
            return
        }
        guard !isSyncing else {
            addDebugMessage("Sync skipped: already in progress")
            return
        }

        isSyncing = true
        syncPagesFetched = 0
        syncRowsUpserted = 0
        syncLastError = ""
        updateStatus()
        if !silent {
            fallbackMessage = "Syncing metadata..."
        }
        addDebugMessage("Sync started")

        do {
            let result = try await syncService.forceSync(
                config: configStore.config,
                onProgress: { [weak self] pages, rows in
                    guard let self else { return }
                    self.syncPagesFetched = pages
                    self.syncRowsUpserted = rows
                    self.updateStatus()
                }
            )
            syncPagesFetched = result.pagesFetched
            syncRowsUpserted = result.rowsUpserted
            syncLastSyncAt = (try await store.getSyncState(key: "last_sync_at")) ?? "-"
            if configStore.config.debug {
                print("[ChannelCoordinator] sync done pages=\(result.pagesFetched) upserted=\(result.rowsUpserted)")
            }
            addDebugMessage("Sync done p\(result.pagesFetched) r\(result.rowsUpserted)")
            if !silent {
                fallbackMessage = "Sync complete"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self else { return }
                    if self.fallbackMessage == "Sync complete" {
                        self.fallbackMessage = ""
                    }
                }
            }
            await fillQueueIfNeeded()
            await loadLibraryStats()
        } catch {
            syncLastError = error.localizedDescription
            fallbackMessage = "Sync failed: \(error.localizedDescription)"
            if configStore.config.debug {
                print("[ChannelCoordinator] sync failed: \(error)")
            }
            addDebugMessage("Sync failed: \(error.localizedDescription)")
        }

        isSyncing = false
        updateStatus()
    }

    private func setupEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let item = note.object as? AVPlayerItem else { return }
            if item === self.activePlayer().currentItem {
                Task { @MainActor in
                    await self.transitionToNext(reason: "ended")
                }
            }
        }
    }

    private func teardownObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        removeTimeObserverIfNeeded()
    }

    private func installTimeObserver() {
        removeTimeObserverIfNeeded()

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        let player = activePlayer()
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.onTick(current: CMTimeGetSeconds(time))
        }
        timeObserverPlayer = player
        installPlaybackStateObserver()
    }

    private func installPlaybackStateObserver() {
        timeControlObservation?.invalidate()
        let player = activePlayer()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateBufferingState(for: observed)
            }
        }
    }

    private func updateBufferingState(for player: AVPlayer) {
        let next = !isPlaybackPaused && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        let changed = next != isBuffering
        isBuffering = next
        if changed {
            addDebugMessage(bufferingStateText(next))
        }
    }

    private func removeTimeObserverIfNeeded() {
        guard let observer = timeObserver, let player = timeObserverPlayer else { return }
        player.removeTimeObserver(observer)
        timeObserver = nil
        timeObserverPlayer = nil
    }

    private func onTick(current: Double) {
        guard let activeItem = activePlayer().currentItem else { return }
        let duration = CMTimeGetSeconds(activeItem.duration)
        guard duration.isFinite, duration > 0 else { return }

        let remaining = duration - current
        let clampedCurrent = max(0, min(duration, current))
        let clampedProgress = max(0, min(1, current / duration))
        playbackProgress = clampedProgress
        elapsedText = formatDuration(clampedCurrent)
        totalDurationText = formatDuration(duration)
        secondsLeftText = "-\(formatDuration(max(0, remaining)))"
        if remaining <= configStore.config.preloadSecondsBeforeEnd {
            Task { @MainActor in
                await maybePrepareNext()
            }
        }

        if configStore.config.crossfadeEnabled,
           remaining <= max(0.15, Double(configStore.config.crossfadeDurationMs) / 1000.0),
           !queue.isEmpty {
            Task { @MainActor in
                await transitionToNext(reason: "near_end_crossfade")
            }
        }
    }

    private func fetchNextCandidate() async throws -> VideoCandidate {
        let order = configStore.config.playbackOrder
        if isSequentialOrder(order) {
            let newestFirst = (order == "sequential_newest")
            await ensureSequentialStateLoaded()
            if let fromDB = try await store.selectSequential(
                afterAssetId: sequentialLastAssetId,
                newestFirst: newestFirst,
                minDuration: configStore.config.minDuration,
                onlyFavorites: configStore.config.onlyFavorites
            ) {
                return fromDB
            }
            await runForceSync(silent: true)
            if let fromDB = try await store.selectSequential(
                afterAssetId: sequentialLastAssetId,
                newestFirst: newestFirst,
                minDuration: configStore.config.minDuration,
                onlyFavorites: configStore.config.onlyFavorites
            ) {
                return fromDB
            }
        } else if configStore.config.useSQLiteCache {
            if let fromDB = try await store.selectRandom(minDuration: configStore.config.minDuration, onlyFavorites: configStore.config.onlyFavorites) {
                return fromDB
            }
            await runForceSync(silent: true)
            if let fromDB = try await store.selectRandom(minDuration: configStore.config.minDuration, onlyFavorites: configStore.config.onlyFavorites) {
                return fromDB
            }
        }

        for _ in 0..<10 {
            let candidate = try await client.fetchRandomEligibleVideo(config: configStore.config)
            if hiddenAssetIds.contains(candidate.id) {
                addDebugMessage("Skipped hidden candidate: \(candidate.title)")
                continue
            }
            return candidate
        }
        throw ImmichAPIError.noEligibleVideo
    }

    private func fillQueueIfNeeded() async {
        let target = max(1, min(configStore.config.queueTargetSize, 5))
        addDebugMessage("Queue check \(queue.count)/\(target)")
        while (queue.count + inflightQueueFetches) < target {
            inflightQueueFetches += 1
            defer { inflightQueueFetches -= 1 }

            do {
                let item = try await fetchNextCandidate()
                if currentItem?.id == item.id { continue }
                if hiddenAssetIds.contains(item.id) { continue }
                if queue.contains(where: { $0.id == item.id }) { continue }
                queue.append(item)
                updateStatus()
                await maybePrepareNext()
                if fallbackMessage == "Could not fetch next video. Retrying..." {
                    fallbackMessage = ""
                }
                addDebugMessage("Queued \(item.title)")
            } catch {
                if configStore.config.debug {
                    print("[ChannelCoordinator] queue fetch failed: \(error)")
                }
                registerPlaybackFailure("Could not fetch next video. Retrying...", error: error)
                addDebugMessage("Queue fetch failed: \(error.localizedDescription)")
                break
            }
        }
        updateStatus()
    }

    private func maybePrepareNext() async {
        guard !preparingNext, !transitionInProgress else { return }
        guard let next = queue.first else { return }
        guard nextPreparedId != next.id else { return }

        preparingNext = true
        defer { preparingNext = false }
        addDebugMessage("Preparing next: \(next.title)")

        do {
            try await prepareHiddenPlayer(with: next)
            nextPreparedId = next.id
            addDebugMessage("Prepared next: \(next.title)")
        } catch {
            addDebugMessage("Prepare failed: \(next.title)")
            if configStore.config.debug {
                print("[ChannelCoordinator] prepare failed: \(error)")
            }
        }
    }

    private func prepareHiddenPlayer(with candidate: VideoCandidate) async throws {
        let hidden = hiddenPlayer()
        let item = try client.makePlaybackItem(candidate: candidate, config: configStore.config)
        hidden.replaceCurrentItem(with: item)
        hidden.isMuted = activePlayer().isMuted
        _ = try await waitUntilReadyToPlay(item: item, timeoutSeconds: 12)
    }

    private func waitUntilReadyToPlay(item: AVPlayerItem, timeoutSeconds: TimeInterval) async throws -> AVPlayerItem {
        if item.status == .readyToPlay {
            return item
        }

        return try await withThrowingTaskGroup(of: AVPlayerItem.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    var observation: NSKeyValueObservation?
                    observation = item.observe(\.status, options: [.new]) { observed, _ in
                        switch observed.status {
                        case .readyToPlay:
                            observation?.invalidate()
                            continuation.resume(returning: observed)
                        case .failed:
                            observation?.invalidate()
                            continuation.resume(throwing: observed.error ?? ImmichAPIError.invalidResponse)
                        default:
                            break
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw ImmichAPIError.invalidResponse
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func playOnActivePlayer(_ candidate: VideoCandidate) async throws {
        let player = activePlayer()
        let item = try client.makePlaybackItem(candidate: candidate, config: configStore.config)
        player.replaceCurrentItem(with: item)
        player.isMuted = readMutedPreference()
        _ = try await waitUntilReadyToPlay(item: item, timeoutSeconds: 12)
        try await playWithAutoplayFallback(player: player)

        currentItem = candidate
        canGoBack = !history.isEmpty
        currentIsFavorite = candidate.isFavorite
        isPlaybackPaused = false
        playbackProgress = 0
        elapsedText = "0:00"
        totalDurationText = formatDuration(candidate.duration)
        secondsLeftText = "-\(formatDuration(candidate.duration))"
        currentImmichAssetURL = buildImmichAssetURL(for: candidate)
        currentInfoFields = buildInfoFields(for: candidate)
        let overlay = overlayTexts(for: candidate)
        dateLocationText = overlayDateLocationText(for: candidate)
        title = overlay.title
        captionText = overlay.caption
        clearPlaybackFailureState()
        await recordWatchStart(for: candidate)
        await persistSequentialProgress(for: candidate)
        installTimeObserver()
        updateStatus()
        addDebugMessage("Playing: \(candidate.title)")
    }

    private func playWithAutoplayFallback(player: AVPlayer) async throws {
        let wasMuted = player.isMuted
        do {
            try await player.playAsync()
        } catch {
            addDebugMessage("Autoplay fallback: mute and retry")
            player.isMuted = true
            do {
                try await player.playAsync()
                player.isMuted = wasMuted
            } catch {
                player.isMuted = wasMuted
                throw error
            }
        }
    }

    private func transitionToNext(reason: String) async {
        guard !transitionInProgress else {
            addDebugMessage("Transition skipped: already in progress")
            return
        }
        transitionInProgress = true
        defer { transitionInProgress = false }
        addDebugMessage("Transition start: \(reason)")

        if queue.isEmpty {
            await fillQueueIfNeeded()
        }

        guard !queue.isEmpty else {
            registerPlaybackFailure("No eligible videos right now. Retrying...")
            return
        }

        let next = queue.removeFirst()
        let previous = currentItem
        updateStatus()

        do {
            if nextPreparedId != next.id {
                try await prepareHiddenPlayer(with: next)
            }

            let outgoing = activePlayer()
            let incoming = hiddenPlayer()
            incoming.isMuted = outgoing.isMuted
            try await playWithAutoplayFallback(player: incoming)

            if configStore.config.crossfadeEnabled && configStore.config.crossfadeDurationMs > 0 {
                withAnimation(.linear(duration: Double(configStore.config.crossfadeDurationMs) / 1000.0)) {
                    if activeIndex == 0 {
                        opacityA = 0
                        opacityB = 1
                    } else {
                        opacityA = 1
                        opacityB = 0
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(Double(configStore.config.crossfadeDurationMs) * 1_000_000))
            } else {
                if activeIndex == 0 {
                    opacityA = 0
                    opacityB = 1
                } else {
                    opacityA = 1
                    opacityB = 0
                }
            }

            outgoing.pause()
            outgoing.replaceCurrentItem(with: nil)

            activeIndex = 1 - activeIndex
            if let previous {
                history.append(previous)
                if history.count > 100 {
                    history.removeFirst(history.count - 100)
                }
            }
            currentItem = next
            canGoBack = !history.isEmpty
            currentIsFavorite = next.isFavorite
            isPlaybackPaused = false
            playbackProgress = 0
            elapsedText = "0:00"
            totalDurationText = formatDuration(next.duration)
            secondsLeftText = "-\(formatDuration(next.duration))"
            currentImmichAssetURL = buildImmichAssetURL(for: next)
            currentInfoFields = buildInfoFields(for: next)
            let overlay = overlayTexts(for: next)
            dateLocationText = overlayDateLocationText(for: next)
            title = overlay.title
            captionText = overlay.caption
            nextPreparedId = ""
            clearPlaybackFailureState()
            await recordWatchStart(for: next)
            await persistSequentialProgress(for: next)

            installTimeObserver()
            await fillQueueIfNeeded()
            await maybePrepareNext()

            if configStore.config.debug {
                print("[ChannelCoordinator] transitioned: \(reason) -> \(next.id)")
            }
            addDebugMessage("Next: \(next.title)")
        } catch {
            registerPlaybackFailure("Transition failed. Skipping...", error: error)
            nextPreparedId = ""
            if configStore.config.debug {
                print("[ChannelCoordinator] transition failed: \(reason) error=\(error)")
            }
            addDebugMessage("Transition failed: \(error.localizedDescription)")
        }
    }

    private func transitionToPrevious(reason: String) async {
        guard !transitionInProgress else {
            addDebugMessage("Back skipped: transition already in progress")
            return
        }
        guard let previous = history.popLast() else {
            addDebugMessage("Back skipped: no history")
            return
        }
        addDebugMessage("Transition back start: \(reason)")

        transitionInProgress = true
        defer { transitionInProgress = false }

        let outgoingCurrent = currentItem

        do {
            try await prepareHiddenPlayer(with: previous)

            let outgoing = activePlayer()
            let incoming = hiddenPlayer()
            incoming.isMuted = outgoing.isMuted
            try await playWithAutoplayFallback(player: incoming)

            if configStore.config.crossfadeEnabled && configStore.config.crossfadeDurationMs > 0 {
                withAnimation(.linear(duration: Double(configStore.config.crossfadeDurationMs) / 1000.0)) {
                    if activeIndex == 0 {
                        opacityA = 0
                        opacityB = 1
                    } else {
                        opacityA = 1
                        opacityB = 0
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(Double(configStore.config.crossfadeDurationMs) * 1_000_000))
            } else {
                if activeIndex == 0 {
                    opacityA = 0
                    opacityB = 1
                } else {
                    opacityA = 1
                    opacityB = 0
                }
            }

            outgoing.pause()
            outgoing.replaceCurrentItem(with: nil)

            activeIndex = 1 - activeIndex
            currentItem = previous
            canGoBack = !history.isEmpty
            currentIsFavorite = previous.isFavorite
            isPlaybackPaused = false
            playbackProgress = 0
            elapsedText = "0:00"
            totalDurationText = formatDuration(previous.duration)
            secondsLeftText = "-\(formatDuration(previous.duration))"
            currentImmichAssetURL = buildImmichAssetURL(for: previous)
            currentInfoFields = buildInfoFields(for: previous)
            let overlay = overlayTexts(for: previous)
            dateLocationText = overlayDateLocationText(for: previous)
            title = overlay.title
            captionText = overlay.caption
            nextPreparedId = ""
            clearPlaybackFailureState()
            await recordWatchStart(for: previous)
            await persistSequentialProgress(for: previous)

            if let outgoingCurrent, !queue.contains(where: { $0.id == outgoingCurrent.id }) {
                queue.insert(outgoingCurrent, at: 0)
            }

            installTimeObserver()
            await fillQueueIfNeeded()
            await maybePrepareNext()

            if configStore.config.debug {
                print("[ChannelCoordinator] transitioned: \(reason) -> \(previous.id)")
            }
            addDebugMessage("Back: \(previous.title)")
        } catch {
            history.append(previous)
            canGoBack = !history.isEmpty
            fallbackMessage = "Back failed: \(error.localizedDescription)"
            if configStore.config.debug {
                print("[ChannelCoordinator] previous transition failed: \(reason) error=\(error)")
            }
            addDebugMessage("Back failed: \(error.localizedDescription)")
        }
    }

    private func activePlayer() -> AVPlayer {
        activeIndex == 0 ? playerA : playerB
    }

    private func hiddenPlayer() -> AVPlayer {
        activeIndex == 0 ? playerB : playerA
    }

    private func shouldUseSQLiteSelection() -> Bool {
        configStore.config.useSQLiteCache || isSequentialOrder(configStore.config.playbackOrder)
    }

    private func updateStatus() {
        let mode = configStore.config.crossfadeEnabled ? "fade \(configStore.config.crossfadeDurationMs)ms" : "cut"
        let orderLabel: String
        switch configStore.config.playbackOrder {
        case "sequential_oldest", "sequential":
            orderLabel = "seq old->new"
        case "sequential_newest":
            orderLabel = "seq new->old"
        default:
            orderLabel = "rand"
        }
        let syncText = isSyncing ? " · syncing p\(syncPagesFetched) r\(syncRowsUpserted)" : ""
        let debugQuality = configStore.config.debug ? " · q \(configStore.config.playbackQualityLabel)" : ""
        statusText = "Queue \(queue.count)/\(configStore.config.queueTargetSize) · \(orderLabel) · \(mode)\(syncText)\(debugQuality)"
    }

    private func applyMuteState(_ muted: Bool) {
        playerA.isMuted = muted
        playerB.isMuted = muted
        objectWillChange.send()
    }

    private func readMutedPreference() -> Bool {
        let key = "ImmichVideoChannel.Muted"
        if UserDefaults.standard.object(forKey: key) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func saveMutedPreference(_ muted: Bool) {
        UserDefaults.standard.set(muted, forKey: "ImmichVideoChannel.Muted")
    }

    private func setFavorite(for candidate: VideoCandidate, to isFavorite: Bool) async {
        guard !favoriteUpdateInProgress else { return }

        favoriteUpdateInProgress = true
        let previous = candidate.isFavorite
        addDebugMessage("\(isFavorite ? "Favorite" : "Unfavorite") requested: \(candidate.title)")
        applyFavoriteStateLocally(assetId: candidate.id, isFavorite: isFavorite)

        do {
            try await client.updateFavorite(assetId: candidate.id, isFavorite: isFavorite, config: configStore.config)
            try await store.initializeSchema()
            try await store.setFavorite(assetId: candidate.id, isFavorite: isFavorite)
            addDebugMessage("\(isFavorite ? "Favorited" : "Unfavorited"): \(candidate.title)")
        } catch {
            applyFavoriteStateLocally(assetId: candidate.id, isFavorite: previous)
            fallbackMessage = "Favorite update failed: \(error.localizedDescription)"
            if configStore.config.debug {
                print("[ChannelCoordinator] favorite update failed: \(error)")
            }
            addDebugMessage("Favorite failed (reverted): \(candidate.title)")
        }

        favoriteUpdateInProgress = false
    }

    private func applyFavoriteStateLocally(assetId: String, isFavorite: Bool) {
        if let item = currentItem, item.id == assetId {
            currentItem = item.withFavorite(isFavorite)
            currentIsFavorite = isFavorite
            currentInfoFields = buildInfoFields(for: item.withFavorite(isFavorite))
        }

        if let index = queue.firstIndex(where: { $0.id == assetId }) {
            queue[index] = queue[index].withFavorite(isFavorite)
        }
        for i in history.indices where history[i].id == assetId {
            history[i] = history[i].withFavorite(isFavorite)
        }
    }

    private func applyHiddenStateLocally(assetId: String, isHidden: Bool) {
        if isHidden {
            hiddenAssetIds.insert(assetId)
        } else {
            hiddenAssetIds.remove(assetId)
        }

        if let item = currentItem, item.id == assetId {
            let updated = item.withHidden(isHidden)
            currentItem = updated
            currentInfoFields = buildInfoFields(for: updated)
        }

        queue.removeAll(where: { $0.id == assetId })
        for i in history.indices where history[i].id == assetId {
            history[i] = history[i].withHidden(isHidden)
        }
    }

    private func applyWatchCountLocally(assetId: String, timesWatched: Int) {
        if let item = currentItem, item.id == assetId {
            let updated = item.withTimesWatched(timesWatched)
            currentItem = updated
            currentInfoFields = buildInfoFields(for: updated)
        }
        if let index = queue.firstIndex(where: { $0.id == assetId }) {
            queue[index] = queue[index].withTimesWatched(timesWatched)
        }
        for i in history.indices where history[i].id == assetId {
            history[i] = history[i].withTimesWatched(timesWatched)
        }
    }

    private func recordWatchStart(for candidate: VideoCandidate) async {
        guard shouldUseSQLiteSelection() else { return }
        do {
            let count = try await store.incrementWatchCount(assetId: candidate.id)
            sessionVideosWatchedCount += 1
            applyWatchCountLocally(assetId: candidate.id, timesWatched: count)
            if currentItem?.id == candidate.id {
                currentInfoFields = buildInfoFields(for: candidate.withTimesWatched(count))
            }
            addDebugMessage("Watch count \(count): \(candidate.title)")
        } catch {
            if configStore.config.debug {
                print("[ChannelCoordinator] watch count update failed: \(error)")
            }
            addDebugMessage("Watch count update failed: \(candidate.title)")
        }
    }

    private func ensureSequentialStateLoaded() async {
        guard !sequentialStateLoaded else { return }
        do {
            sequentialLastAssetId = try await store.getSequentialLastAssetId()
            sequentialStateLoaded = true
            if let sequentialLastAssetId {
                addDebugMessage("Seq resume at \(sequentialLastAssetId)")
            } else {
                addDebugMessage("Seq resume at start")
            }
        } catch {
            sequentialStateLoaded = true
            addDebugMessage("Seq state load failed: \(error.localizedDescription)")
        }
    }

    private func persistSequentialProgress(for candidate: VideoCandidate) async {
        guard isSequentialOrder(configStore.config.playbackOrder) else { return }
        sequentialLastAssetId = candidate.id
        sequentialStateLoaded = true
        do {
            try await store.setSequentialLastAssetId(candidate.id)
        } catch {
            addDebugMessage("Seq progress save failed: \(error.localizedDescription)")
        }
    }

    private func resetSequentialProgress() async {
        do {
            try await store.clearSequentialLastAssetId()
            sequentialLastAssetId = nil
            sequentialStateLoaded = true
            nextPreparedId = ""
            queue.removeAll()
            addDebugMessage("Sequential progress reset")
            await fillQueueIfNeeded()
            await loadLibraryStats()
        } catch {
            addDebugMessage("Seq progress reset failed: \(error.localizedDescription)")
        }
    }

    private func isSequentialOrder(_ order: String) -> Bool {
        order == "sequential_oldest" || order == "sequential_newest" || order == "sequential"
    }

    private func loadLibraryStats() async {
        guard shouldUseSQLiteSelection() else {
            statsLastError = "SQLite cache is disabled."
            return
        }

        do {
            try await store.initializeSchema()
            let stats = try await store.getLibraryStats()
            statsTotalVideos = stats.totalVideos
            statsTotalWatchedPlays = stats.totalWatchedPlays
            statsWatchedPlays7Days = stats.watchedPlays7Days
            statsWatchedPlays30Days = stats.watchedPlays30Days
            statsVideosWatchedAtLeastOnce = stats.videosWatchedAtLeastOnce
            statsFavoritesCount = stats.favoritesCount
            statsHiddenCount = stats.hiddenCount
            sessionVideosWatchedCount = stats.currentSessionWatched
            statsMostPopularCamera = stats.mostPopularCamera
            statsMostPopularCodec = stats.mostPopularCodec
            statsMostPopularFileType = stats.mostPopularFileType
            statsMostPopularPlace = stats.mostPopularPlace
            statsMostPopularYear = stats.mostPopularYear
            statsTopCamerasSummary = formatTop(stats.topCameras)
            statsTopCodecsSummary = formatTop(stats.topCodecs)
            statsTopFileTypesSummary = formatTop(stats.topFileTypes)
            statsTopPlacesSummary = formatTop(stats.topPlaces)
            statsTopYearsSummary = formatTop(stats.topYears)
            statsLastError = ""
            if let currentItem {
                currentInfoFields = buildInfoFields(for: currentItem)
            }
        } catch {
            statsLastError = error.localizedDescription
            addDebugMessage("Library stats failed: \(error.localizedDescription)")
        }
    }

    private func formatTop(_ rows: [SQLiteVideoStore.RankedStat]) -> String {
        guard !rows.isEmpty else { return "-" }
        return rows.map { "\($0.label) (\($0.count))" }.joined(separator: ", ")
    }

    private func clearPlaybackFailureState() {
        consecutivePlaybackFailures = 0
        fallbackMessage = ""
    }

    private func registerPlaybackFailure(_ message: String, error: Error? = nil) {
        consecutivePlaybackFailures += 1
        fallbackMessage = message
        addDebugMessage("Playback failure \(consecutivePlaybackFailures): \(message)")

        if consecutivePlaybackFailures < maxConsecutivePlaybackFailures || shouldOpenSetup {
            return
        }

        let details = error?.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let composedMessage = details.isEmpty ? message : "\(message) (\(details))"
        setupErrorMessage = composedMessage
        syncLastError = composedMessage
        shouldOpenSetup = true
        addDebugMessage("Failure threshold reached: opening settings")
        stop()
    }

    private func formatCaption(for candidate: VideoCandidate) -> String {
        let monthYear = formatMonthYear(candidate.captureDate)
        let location = formatLocation(city: candidate.city, country: candidate.country)

        if monthYear.isEmpty && location.isEmpty {
            return ""
        }
        if monthYear.isEmpty {
            return location
        }
        if location.isEmpty {
            return monthYear
        }
        return "\(monthYear)\n\(location)"
    }

    private func overlayDateLocationText(for candidate: VideoCandidate) -> String {
        guard configStore.config.showDateLocationOverlay else { return "" }
        return formatCaption(for: candidate)
    }

    private func overlayTexts(for candidate: VideoCandidate) -> (title: String, caption: String) {
        let dateAndLocation = formatCaption(for: candidate)
        if dateAndLocation.isEmpty {
            return (candidate.title, "")
        }
        return (dateAndLocation, candidate.title)
    }

    private func formatLocation(city: String, country: String) -> String {
        let c = normalizedLocationPart(city)
        let k = normalizedLocationPart(country)

        if !c.isEmpty && !k.isEmpty {
            let cLower = c.lowercased()
            let kLower = k.lowercased()
            if cLower == kLower || cLower.hasSuffix(", \(kLower)") || cLower.hasSuffix(kLower) {
                return c
            }
            return "\(c), \(k)"
        }
        if !c.isEmpty { return c }
        if !k.isEmpty { return k }
        return ""
    }

    private func normalizedLocationPart(_ raw: String) -> String {
        let parts = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }

    private func formatMonthYear(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM yyyy"
            return f.string(from: date)
        }

        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "en_US_POSIX")
        f1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = f1.date(from: value) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM yyyy"
            return f.string(from: date)
        }

        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = f2.date(from: value) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM yyyy"
            return f.string(from: date)
        }

        if value.count >= 7 {
            let prefix = String(value.prefix(7))
            let monthMap = [
                "01": "Jan", "02": "Feb", "03": "Mar", "04": "Apr",
                "05": "May", "06": "Jun", "07": "Jul", "08": "Aug",
                "09": "Sep", "10": "Oct", "11": "Nov", "12": "Dec"
            ]
            let parts = prefix.split(separator: "-")
            if parts.count == 2, parts[0].count == 4, let month = monthMap[String(parts[1])] {
                return "\(month) \(parts[0])"
            }
        }

        if value.count >= 4 {
            let year = String(value.prefix(4))
            if year.allSatisfy({ $0.isNumber }) {
                return year
            }
        }

        return ""
    }

    private func buildInfoFields(for candidate: VideoCandidate) -> [VideoInfoField] {
        let monthYear = formatMonthYear(candidate.captureDate)
        let location = formatLocation(city: candidate.city, country: candidate.country)
        let camera = [candidate.cameraMake, candidate.cameraModel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let dateTime = formatCaptureDateTime(candidate.captureDate)

        var fields: [VideoInfoField] = [
            VideoInfoField(id: "title", label: "Title", value: nonEmptyOrDash(candidate.title)),
            VideoInfoField(id: "id", label: "Asset ID", value: nonEmptyOrDash(candidate.id)),
            VideoInfoField(id: "duration", label: "Duration", value: formatDuration(candidate.duration)),
            VideoInfoField(id: "times_watched", label: "Times Watched", value: String(candidate.timesWatched)),
            VideoInfoField(id: "session_watched", label: "Session Watched", value: String(sessionVideosWatchedCount)),
            VideoInfoField(id: "favorite", label: "Favorite", value: candidate.isFavorite ? "Yes" : "No"),
            VideoInfoField(id: "hidden", label: "Hidden", value: candidate.isHidden ? "Yes" : "No")
        ]

        if !monthYear.isEmpty {
            fields.append(VideoInfoField(id: "month_year", label: "Year / Month", value: monthYear))
        }
        if !location.isEmpty {
            fields.append(VideoInfoField(id: "current_location", label: "Current Location", value: location))
        }

        fields.append(contentsOf: [
            VideoInfoField(id: "capture_raw", label: "Capture Date (Raw)", value: nonEmptyOrDash(candidate.captureDate)),
            VideoInfoField(id: "capture_fmt", label: "Capture Date (Parsed)", value: nonEmptyOrDash(dateTime)),
            VideoInfoField(id: "city", label: "City", value: nonEmptyOrDash(candidate.city)),
            VideoInfoField(id: "country", label: "Country", value: nonEmptyOrDash(candidate.country)),
            VideoInfoField(id: "location", label: "Location", value: nonEmptyOrDash(location)),
            VideoInfoField(id: "camera_make", label: "Camera Make", value: nonEmptyOrDash(candidate.cameraMake)),
            VideoInfoField(id: "camera_model", label: "Camera Model", value: nonEmptyOrDash(candidate.cameraModel)),
            VideoInfoField(id: "camera", label: "Camera (Combined)", value: nonEmptyOrDash(camera)),
            VideoInfoField(id: "lens", label: "Lens", value: nonEmptyOrDash(candidate.lensModel)),
            VideoInfoField(id: "fnumber", label: "Aperture", value: nonEmptyOrDash(candidate.fNumber)),
            VideoInfoField(id: "focal", label: "Focal Length", value: nonEmptyOrDash(candidate.focalLength)),
            VideoInfoField(id: "iso", label: "ISO", value: nonEmptyOrDash(candidate.iso)),
            VideoInfoField(id: "shutter", label: "Exposure", value: nonEmptyOrDash(candidate.exposureTime)),
            VideoInfoField(id: "latitude", label: "Latitude", value: nonEmptyOrDash(candidate.latitude)),
            VideoInfoField(id: "longitude", label: "Longitude", value: nonEmptyOrDash(candidate.longitude)),
            VideoInfoField(id: "immich_url", label: "Immich URL", value: nonEmptyOrDash(currentImmichAssetURL))
        ])

        return fields
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "-" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatCaptureDateTime(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: date)
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss"
        ]
        for format in formats {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = format
            if let date = parser.date(from: value) {
                let out = DateFormatter()
                out.locale = Locale(identifier: "en_US_POSIX")
                out.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return out.string(from: date)
            }
        }
        return value
    }

    private func buildImmichAssetURL(for candidate: VideoCandidate) -> String {
        let encoded = candidate.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? candidate.id
        return "\(configStore.config.normalizedImmichBaseURL)/photos/\(encoded)"
    }

    private func addDebugMessage(_ message: String) {
        guard configStore.config.debug else {
            recentDebugMessages = []
            return
        }
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        recentDebugMessages.append("[\(timestamp)] \(message)")
        if recentDebugMessages.count > 3 {
            recentDebugMessages.removeFirst(recentDebugMessages.count - 3)
        }
    }

    private func bufferingStateText(_ buffering: Bool) -> String {
        buffering ? "Buffering..." : "Buffering ended"
    }

    private func nonEmptyOrDash(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }
}

private extension AVPlayer {
    func playAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if self.error != nil {
                    continuation.resume(throwing: self.error!)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

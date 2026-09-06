import AVFoundation
import SwiftUI

private enum PlaybackDurationValidationError: Error {
    case belowMinimum
}

struct PlaybackProgressWatchdog {
    private var position: Double = 0
    private var lastProgressAt: TimeInterval = 0

    mutating func reset(position: Double, now: TimeInterval) {
        self.position = position.isFinite ? position : 0
        lastProgressAt = now
    }

    mutating func isStalled(position: Double, now: TimeInterval) -> Bool {
        if position.isFinite, abs(position - self.position) > 0.1 {
            reset(position: position, now: now)
        }
        return now - lastProgressAt >= 20
    }
}

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
    @Published var title: String = L10n.tr("playback.loading", "Loading...", comment: "Loading state title")
    @Published var captionText: String = ""
    @Published var dateLocationText: String = ""
    @Published var fallbackMessage: String = ""
    @Published var statusText: String = ""
    @Published var debugTelemetryText: String = ""
    @Published var recentDebugMessages: [String] = []
    @Published var playbackProgress: Double = 0
    @Published var secondsLeftText: String = "--:--"
    @Published var elapsedText: String = "0:00"
    @Published var totalDurationText: String = "--:--"
    @Published var isBuffering: Bool = false
    @Published var currentInfoFields: [VideoInfoField] = []
    @Published var currentImmichAssetURL: String = ""
    @Published var currentCaptureDateRaw: String = ""
    @Published var currentPlaceCity: String = ""
    @Published var currentPlaceCountry: String = ""
    @Published var currentPlaceLabel: String = ""
    @Published var currentPeopleText: String = ""
    @Published var canGoBack: Bool = false
    @Published var currentIsFavorite: Bool = false
    @Published var canHideToAlbum: Bool = false
    @Published var hideUpdateInProgress: Bool = false
    @Published var isPlaybackPaused: Bool = false
    @Published var favoriteUpdateInProgress: Bool = false
    @Published var isSyncing: Bool = false
    @Published var syncPagesFetched: Int = 0
    @Published var syncRowsUpserted: Int = 0
    @Published var syncLastSyncAt: String = L10n.unknownDash
    @Published var syncLastError: String = ""
    @Published var statsTotalVideos: Int = 0
    @Published var statsTotalVideoDuration: Double = 0
    @Published var statsTotalWatchedPlays: Int = 0
    @Published var statsTotalWatchedDuration: Double = 0
    @Published var statsWatchedPlays7Days: Int = 0
    @Published var statsWatchedPlays30Days: Int = 0
    @Published var statsVideosWatchedAtLeastOnce: Int = 0
    @Published var statsFavoritesCount: Int = 0
    @Published var statsHiddenCount: Int = 0
    @Published var sessionVideosWatchedCount: Int = 0
    @Published var statsMostPopularCamera: String = L10n.unknownDash
    @Published var statsMostPopularCodec: String = L10n.unknownDash
    @Published var statsMostPopularFileType: String = L10n.unknownDash
    @Published var statsMostPopularPlace: String = L10n.unknownDash
    @Published var statsMostPopularYear: String = L10n.unknownDash
    @Published var statsTopCamerasSummary: String = L10n.unknownDash
    @Published var statsTopCodecsSummary: String = L10n.unknownDash
    @Published var statsTopFileTypesSummary: String = L10n.unknownDash
    @Published var statsTopPlacesSummary: String = L10n.unknownDash
    @Published var statsTopYearsSummary: String = L10n.unknownDash
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
    private var sceneIsActive = true
    private var playbackTasks: [UUID: Task<Void, Never>] = [:]
    private var playbackGeneration = UUID()
    private var bootstrapping = false
    private var sessionStartedAt: String?
    private var resumePosition: Double = 0
    private var progressWatchdog = PlaybackProgressWatchdog()

    private var consecutivePlaybackFailures = 0
    private let maxConsecutivePlaybackFailures = 5
    private var hiddenAlbumId = ""
    private var hiddenAssetIds = Set<String>()
    private var sequentialLastAssetId: String?
    private var sequentialStateLoaded = false
    private var searchLoadedQuery = ""
    private var searchPool: [VideoCandidate] = []
    private var searchSeenIDs = Set<String>()
    private var searchNextPage = 1
    private var searchHasMorePages = true

    private var timeObserver: Any?
    private var timeObserverPlayer: AVPlayer?
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private var queueTimer: Timer?
    private var recoveryTimer: Timer?
    private var debugHistorySamples: [String] = []
    private var lastDebugHistorySampleTime: Double = 0
    private var currentFormatDebugText: String = "-"

    init(configStore: ConfigStore, client: ImmichAPIClient = ImmichAPIClient(), store: SQLiteVideoStore = SQLiteVideoStore()) {
        self.configStore = configStore
        self.client = client
        self.store = store
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        if let observer = timeObserver, let player = timeObserverPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
            timeObserverPlayer = nil
        }
        queueTimer?.invalidate()
        recoveryTimer?.invalidate()
    }

    private func launch(requiresPlayback: Bool = true, _ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let generation = playbackGeneration
        playbackTasks[id] = Task { [weak self] in
            guard let self else { return }
            guard self.sceneIsActive, (!requiresPlayback || self.started),
                  self.playbackGeneration == generation else {
                self.playbackTasks[id] = nil
                return
            }
            await operation()
            self.playbackTasks[id] = nil
        }
    }

    // AVFoundation callbacks can arrive off the main actor. Only the enqueue
    // hop is unowned; all playback work is registered and cancelled by stop().
    private nonisolated func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        Task { @MainActor [weak self] in
            self?.launch(operation)
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        sceneIsActive = phase == .active
        if sceneIsActive {
            start()
        } else {
            stop()
        }
    }

    private func resetProgressWatchdog() {
        progressWatchdog.reset(position: CMTimeGetSeconds(activePlayer().currentTime()),
                               now: ProcessInfo.processInfo.systemUptime)
    }

    private func recoverPlaybackIfNeeded() async {
        guard started, !Task.isCancelled, !isPlaybackPaused, !bootstrapping else { return }
        let player = activePlayer()
        let position = CMTimeGetSeconds(player.currentTime())
        let now = ProcessInfo.processInfo.systemUptime
        let stalled = progressWatchdog.isStalled(position: position, now: now)
        if currentItem == nil {
            await bootstrapPlayback()
            guard !Task.isCancelled else { return }
        } else if player.error != nil || player.currentItem?.status == .failed || stalled {
            addDebugMessage("Recovering failed or stalled playback")
            stop()
            start()
        } else if !transitionInProgress,
                  let item = player.currentItem,
                  CMTimeGetSeconds(item.duration).isFinite,
                  position >= CMTimeGetSeconds(item.duration) - 0.1 {
            await transitionToNext(reason: "recovery_ended")
        } else if !transitionInProgress, player.timeControlStatus == .paused {
            player.play()
        }
    }

    private func resumePlayback() async {
        guard !Task.isCancelled else { return }
        guard let candidate = currentItem else { return }
        bootstrapping = true
        let generation = playbackGeneration
        defer { if generation == playbackGeneration { bootstrapping = false } }
        do {
            let player = activePlayer()
            let item = try client.makePlaybackItem(candidate: candidate, config: configStore.config)
            player.replaceCurrentItem(with: item)
            _ = try await waitUntilReadyToPlay(item: item, timeoutSeconds: 12)
            guard !Task.isCancelled else { return }
            try validatePlaybackDuration(item, for: candidate)
            let duration = CMTimeGetSeconds(item.duration)
            if resumePosition > 0, resumePosition < duration - 0.25 {
                await player.seek(to: CMTime(seconds: resumePosition, preferredTimescale: 600))
                guard !Task.isCancelled else { return }
            }
            installTimeObserver()
            resetProgressWatchdog()
            if !isPlaybackPaused { try await playWithAutoplayFallback(player: player) }
            try Task.checkCancellation()
            if isPlaybackPaused { player.pause() }
            clearPlaybackFailureState()
            addDebugMessage("Playback restored after suspension")
        } catch {
            guard !Task.isCancelled else { return }
            currentItem = nil
            resumePosition = 0
            registerPlaybackFailure(L10n.tr(
                "errors.playback.initial_load_retry",
                "Could not load initial video. Retrying...",
                comment: "Playback failure message when initial video loading fails"
            ), error: error)
        }
    }

    func start() {
        guard configStore.config.isConfigured else {
            fallbackMessage = L10n.tr(
                "errors.setup.complete_first",
                "Please complete setup first",
                comment: "Error shown when playback starts before setup is complete"
            )
            addDebugMessage("Start blocked: app not configured")
            return
        }
        guard sceneIsActive, !started else { return }
        started = true
        playerA = AVPlayer()
        playerB = AVPlayer()
        activeIndex = 0
        opacityA = 1
        opacityB = 0
        resetProgressWatchdog()
        addDebugMessage("Channel start")

        setupEndObserver()
        applyMuteState(readMutedPreference())
        updateStatus()
        let startedAt = sessionStartedAt ?? ISO8601DateFormatter().string(from: Date())
        sessionStartedAt = startedAt
        launch { [self] in
            try? await store.setSyncState(key: "session_started_at", value: startedAt)
        }
        launch { [self] in
            await checkHiddenAlbumAccessAtStartup()
        }

        launch { [self] in
            if currentItem != nil { await resumePlayback() }
            else { await bootstrapPlayback() }
        }

        let generation = playbackGeneration
        queueTimer?.invalidate()
        queueTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.enqueue { [self] in
                guard generation == self.playbackGeneration else { return }
                await self.fillQueueIfNeeded()
            }
        }

        recoveryTimer?.invalidate()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.enqueue { [self] in
                guard generation == self.playbackGeneration else { return }
                await self.recoverPlaybackIfNeeded()
            }
        }
    }

    func stop() {
        guard started || !playbackTasks.isEmpty else { return }
        addDebugMessage("Channel stop")
        if started {
            let position = CMTimeGetSeconds(activePlayer().currentTime())
            if position.isFinite { resumePosition = max(0, position) }
        }
        started = false
        playbackGeneration = UUID()
        playbackTasks.values.forEach { $0.cancel() }
        playbackTasks.removeAll()
        transitionInProgress = false
        preparingNext = false
        bootstrapping = false
        inflightQueueFetches = 0
        nextPreparedId = ""
        isSyncing = false
        favoriteUpdateInProgress = false
        hideUpdateInProgress = false
        isBuffering = false
        queueTimer?.invalidate()
        recoveryTimer?.invalidate()
        queueTimer = nil
        recoveryTimer = nil
        teardownObservers()
        playerA.pause()
        playerB.pause()
        playerA.replaceCurrentItem(with: nil)
        playerB.replaceCurrentItem(with: nil)
        debugTelemetryText = ""
    }

    func restart() {
        addDebugMessage("Channel restart requested")
        stop()
        queue = []
        history = []
        sessionStartedAt = nil
        currentItem = nil
        resumePosition = 0
        nextPreparedId = ""
        sequentialLastAssetId = nil
        sequentialStateLoaded = false
        hiddenAlbumId = ""
        hiddenAssetIds = []
        consecutivePlaybackFailures = 0
        statsTotalVideos = 0
        statsTotalVideoDuration = 0
        statsTotalWatchedPlays = 0
        statsTotalWatchedDuration = 0
        statsWatchedPlays7Days = 0
        statsWatchedPlays30Days = 0
        statsVideosWatchedAtLeastOnce = 0
        statsFavoritesCount = 0
        statsHiddenCount = 0
        sessionVideosWatchedCount = 0
        statsMostPopularCamera = L10n.unknownDash
        statsMostPopularCodec = L10n.unknownDash
        statsMostPopularFileType = L10n.unknownDash
        statsMostPopularPlace = L10n.unknownDash
        statsMostPopularYear = L10n.unknownDash
        statsTopCamerasSummary = L10n.unknownDash
        statsTopCodecsSummary = L10n.unknownDash
        statsTopFileTypesSummary = L10n.unknownDash
        statsTopPlacesSummary = L10n.unknownDash
        statsTopYearsSummary = L10n.unknownDash
        statsLastError = ""
        shouldOpenSetup = false
        setupErrorMessage = ""
        fallbackMessage = ""
        title = L10n.tr("playback.loading", "Loading...", comment: "Loading state title")
        captionText = ""
        dateLocationText = ""
        playbackProgress = 0
        secondsLeftText = "--:--"
        elapsedText = "0:00"
        totalDurationText = "--:--"
        isBuffering = false
        currentInfoFields = []
        currentImmichAssetURL = ""
        currentCaptureDateRaw = ""
        currentPlaceCity = ""
        currentPlaceCountry = ""
        currentPlaceLabel = ""
        currentPeopleText = ""
        canGoBack = false
        currentIsFavorite = false
        canHideToAlbum = false
        hideUpdateInProgress = false
        isPlaybackPaused = false
        resetSearchState()
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
        launch { [self] in
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
        activePlayer().isMuted
            ? L10n.tr("playback.controls.unmute", "Unmute", comment: "Unmute action label")
            : L10n.tr("playback.controls.mute", "Mute", comment: "Mute action label")
    }

    func forceSyncNow() {
        addDebugMessage("Manual sync requested")
        launch(requiresPlayback: false) { [self] in
            await runForceSync()
        }
    }

    func resetPlaybackProgress() {
        launch(requiresPlayback: false) { [self] in
            await resetSequentialProgress()
        }
    }

    func refreshLibraryStats() {
        launch(requiresPlayback: false) { [self] in
            await loadLibraryStats()
        }
    }

    func favoriteButtonLabel() -> String {
        currentIsFavorite
            ? L10n.tr("playback.controls.unfavorite", "Unfavorite", comment: "Remove favorite action label")
            : L10n.tr("playback.controls.favorite", "Favorite", comment: "Favorite action label")
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
        resetProgressWatchdog()
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
        launch { [self] in
            await transitionToPrevious(reason: "manual_back")
        }
    }

    func toggleFavorite() {
        guard let currentItem else {
            addDebugMessage("Favorite ignored: no current item")
            return
        }
        let nextValue = !currentItem.isFavorite
        launch { [self] in
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
        launch { [self] in
            let generation = playbackGeneration
            defer { if generation == playbackGeneration { self.hideUpdateInProgress = false } }
            addDebugMessage("Hide requested: \(target.title)")

            do {
                try await client.archiveAsset(assetId: target.id, isArchived: true, config: configStore.config)
                if configStore.config.useSQLiteCache {
                    try await store.initializeSchema()
                    try await store.setHidden(assetId: target.id, isHidden: true)
                }
                guard !Task.isCancelled else { return }
                applyHiddenStateLocally(assetId: target.id, isHidden: true)
                fallbackMessage = String(format: L10n.tr(
                    "playback.hide_forever.success",
                    "Hidden: %@",
                    comment: "Confirmation after hiding current video"
                ), target.title)
                addDebugMessage("Archived (locked): \(target.title)")
                await transitionToNext(reason: "manual_hide")
            } catch {
                guard !Task.isCancelled else { return }
                fallbackMessage = String(format: L10n.tr(
                    "errors.playback.hide_failed",
                    "Hide failed: %@",
                    comment: "Hide action failure message with reason"
                ), error.localizedDescription)
                if configStore.config.debug {
                    print("[ChannelCoordinator] hide failed: \(error)")
                }
                addDebugMessage("Hide failed: \(target.title)")
            }
        }
    }

    private func bootstrapPlayback() async {
        guard started, !Task.isCancelled, !bootstrapping, !transitionInProgress else { return }
        bootstrapping = true
        let generation = playbackGeneration
        defer { if generation == playbackGeneration { bootstrapping = false } }
        do {
            if shouldUseSQLiteSelection() {
                try await store.initializeSchema()
                guard !Task.isCancelled else { return }
                let loadedSyncAt = (try await store.getSyncState(key: "last_sync_at")) ?? L10n.unknownDash
                guard !Task.isCancelled else { return }
                syncLastSyncAt = loadedSyncAt
                if configStore.config.syncOnStartup {
                    let count = try await store.countQualifying(
                        minDuration: configStore.config.minDuration,
                        onlyFavorites: configStore.config.onlyFavorites,
                        timeChannel: configStore.config.timeChannel,
                        seasonHemisphere: configStore.config.seasonHemisphere,
                        onlyThisMonth: configStore.config.onlyThisMonth,
                        onlyThisDay: configStore.config.onlyThisDay,
                        onlyThisWeek: configStore.config.onlyThisWeek,
                        referenceCaptureDate: configStore.config.referenceCaptureDate,
                        placeCity: configStore.config.placeFilterCity,
                        placeCountry: configStore.config.placeFilterCountry,
                        albumID: configStore.config.albumFilterID,
                        personID: configStore.config.personFilterID
                    )
                    guard !Task.isCancelled else { return }
                    if count == 0 {
                        await runForceSync(silent: true)
                        guard !Task.isCancelled else { return }
                    }
                }
            }

            let first = try await fetchNextCandidate()
            guard !Task.isCancelled else { return }
            try await playOnActivePlayer(first)
            guard !Task.isCancelled else { return }
            clearPlaybackFailureState()
            await fillQueueIfNeeded()
            guard !Task.isCancelled else { return }
            await loadLibraryStats()
            guard !Task.isCancelled else { return }
            addDebugMessage("Bootstrap playback started")
        } catch {
            guard !Task.isCancelled else { return }
            registerPlaybackFailure(L10n.tr(
                "errors.playback.initial_load_retry",
                "Could not load initial video. Retrying...",
                comment: "Playback failure message when initial video loading fails"
            ), error: error)
            if configStore.config.debug {
                print("[ChannelCoordinator] bootstrap failed: \(error)")
            }
            addDebugMessage("Bootstrap failed: \(error.localizedDescription)")
        }
    }

    private func checkHiddenAlbumAccessAtStartup() async {
        guard !Task.isCancelled else { return }
        canHideToAlbum = true
        hiddenAlbumId = ""
        addDebugMessage("Hide capability: archive/locked mode enabled")
    }

    private func runForceSync(silent: Bool = false) async {
        guard !Task.isCancelled else { return }
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
            fallbackMessage = L10n.tr(
                "library.sync.in_progress",
                "Syncing metadata...",
                comment: "Message shown while metadata sync is running"
            )
        }
        addDebugMessage("Sync started")

        do {
            let result = try await syncService.forceSync(
                config: configStore.config,
                onProgress: { [weak self] pages, rows in
                    guard let self, !Task.isCancelled else { return }
                    self.syncPagesFetched = pages
                    self.syncRowsUpserted = rows
                    self.updateStatus()
                }
            )
            guard !Task.isCancelled else { return }
            syncPagesFetched = result.pagesFetched
            syncRowsUpserted = result.rowsUpserted
            let loadedSyncAt = (try await store.getSyncState(key: "last_sync_at")) ?? L10n.unknownDash
            guard !Task.isCancelled else { return }
            syncLastSyncAt = loadedSyncAt
            if configStore.config.debug {
                print("[ChannelCoordinator] sync done pages=\(result.pagesFetched) upserted=\(result.rowsUpserted)")
            }
            addDebugMessage("Sync done p\(result.pagesFetched) r\(result.rowsUpserted)")
            if !silent {
                fallbackMessage = L10n.tr("library.sync.complete", "Sync complete", comment: "Message shown when metadata sync is complete")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self else { return }
                    if self.fallbackMessage == L10n.tr("library.sync.complete", "Sync complete", comment: "Message shown when metadata sync is complete") {
                        self.fallbackMessage = ""
                    }
                }
            }
            await fillQueueIfNeeded()
            guard !Task.isCancelled else { return }
            await loadLibraryStats()
            guard !Task.isCancelled else { return }
        } catch {
            guard !Task.isCancelled else { return }
            syncLastError = error.localizedDescription
            fallbackMessage = String(format: L10n.tr(
                "errors.library.sync_failed",
                "Sync failed: %@",
                comment: "Metadata sync failure message with reason"
            ), error.localizedDescription)
            if configStore.config.debug {
                print("[ChannelCoordinator] sync failed: \(error)")
            }
            addDebugMessage("Sync failed: \(error.localizedDescription)")
        }

        isSyncing = false
        updateStatus()
    }

    private func setupEndObserver() {
        let generation = playbackGeneration
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let item = note.object as? AVPlayerItem else { return }
            self.enqueue { [self] in
                guard generation == self.playbackGeneration else { return }
                guard item === self.activePlayer().currentItem else { return }
                await self.transitionToNext(reason: "ended")
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
        let generation = playbackGeneration
        removeTimeObserverIfNeeded()

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        let player = activePlayer()
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.enqueue { [self] in
                guard generation == self.playbackGeneration else { return }
                guard player === self.activePlayer() else { return }
                self.onTick(current: CMTimeGetSeconds(time))
            }
        }
        timeObserverPlayer = player
        installPlaybackStateObserver()
    }

    private func installPlaybackStateObserver() {
        let generation = playbackGeneration
        timeControlObservation?.invalidate()
        let player = activePlayer()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
            guard let self else { return }
            self.enqueue { [self] in
                guard generation == self.playbackGeneration else { return }
                guard observed === self.activePlayer() else { return }
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
        if !isPlaybackPaused, remaining <= configStore.config.preloadSecondsBeforeEnd {
            launch { [self] in
                await maybePrepareNext()
            }
        }

        if !isPlaybackPaused, configStore.config.crossfadeEnabled,
           remaining <= max(0.15, Double(configStore.config.crossfadeDurationMs) / 1000.0),
           !queue.isEmpty {
            launch { [self] in
                await transitionToNext(reason: "near_end_crossfade")
            }
        }

        if configStore.config.debug {
            updateStatus()
            updateDebugTelemetry(current: clampedCurrent, item: activeItem)
        }
    }

    private func fetchNextCandidate() async throws -> VideoCandidate {
        try Task.checkCancellation()
        if configStore.config.hasSearchFilter {
            return try await fetchNextSearchCandidate()
        }

        let order = configStore.config.playbackOrder
        if isSequentialOrder(order) {
            let newestFirst = (order == "sequential_newest")
            await ensureSequentialStateLoaded()
            try Task.checkCancellation()
            if let fromDB = try await store.selectSequential(
                afterAssetId: sequentialLastAssetId,
                newestFirst: newestFirst,
                minDuration: configStore.config.minDuration,
                onlyFavorites: configStore.config.onlyFavorites,
                timeChannel: configStore.config.timeChannel,
                seasonHemisphere: configStore.config.seasonHemisphere,
                onlyThisMonth: configStore.config.onlyThisMonth,
                onlyThisDay: configStore.config.onlyThisDay,
                onlyThisWeek: configStore.config.onlyThisWeek,
                referenceCaptureDate: configStore.config.referenceCaptureDate,
                placeCity: configStore.config.placeFilterCity,
                placeCountry: configStore.config.placeFilterCountry,
                albumID: configStore.config.albumFilterID,
                personID: configStore.config.personFilterID
            ) {
                try Task.checkCancellation()
                return fromDB
            }
            await runForceSync(silent: true)
            try Task.checkCancellation()
            if let fromDB = try await store.selectSequential(
                afterAssetId: sequentialLastAssetId,
                newestFirst: newestFirst,
                minDuration: configStore.config.minDuration,
                onlyFavorites: configStore.config.onlyFavorites,
                timeChannel: configStore.config.timeChannel,
                seasonHemisphere: configStore.config.seasonHemisphere,
                onlyThisMonth: configStore.config.onlyThisMonth,
                onlyThisDay: configStore.config.onlyThisDay,
                onlyThisWeek: configStore.config.onlyThisWeek,
                referenceCaptureDate: configStore.config.referenceCaptureDate,
                placeCity: configStore.config.placeFilterCity,
                placeCountry: configStore.config.placeFilterCountry,
                albumID: configStore.config.albumFilterID,
                personID: configStore.config.personFilterID
            ) {
                try Task.checkCancellation()
                return fromDB
            }
        } else if configStore.config.useSQLiteCache {
            if let fromDB = try await store.selectRandom(
                minDuration: configStore.config.minDuration,
                onlyFavorites: configStore.config.onlyFavorites,
                timeChannel: configStore.config.timeChannel,
                seasonHemisphere: configStore.config.seasonHemisphere,
                onlyThisMonth: configStore.config.onlyThisMonth,
                onlyThisDay: configStore.config.onlyThisDay,
                onlyThisWeek: configStore.config.onlyThisWeek,
                referenceCaptureDate: configStore.config.referenceCaptureDate,
                placeCity: configStore.config.placeFilterCity,
                placeCountry: configStore.config.placeFilterCountry,
                albumID: configStore.config.albumFilterID,
                personID: configStore.config.personFilterID
            ) {
                try Task.checkCancellation()
                return fromDB
            }
            await runForceSync(silent: true)
            try Task.checkCancellation()
            if let fromDB = try await store.selectRandom(
                minDuration: configStore.config.minDuration,
                onlyFavorites: configStore.config.onlyFavorites,
                timeChannel: configStore.config.timeChannel,
                seasonHemisphere: configStore.config.seasonHemisphere,
                onlyThisMonth: configStore.config.onlyThisMonth,
                onlyThisDay: configStore.config.onlyThisDay,
                onlyThisWeek: configStore.config.onlyThisWeek,
                referenceCaptureDate: configStore.config.referenceCaptureDate,
                placeCity: configStore.config.placeFilterCity,
                placeCountry: configStore.config.placeFilterCountry,
                albumID: configStore.config.albumFilterID,
                personID: configStore.config.personFilterID
            ) {
                try Task.checkCancellation()
                return fromDB
            }
        }

        for _ in 0..<10 {
            let candidate = try await client.fetchRandomEligibleVideo(config: configStore.config)
            try Task.checkCancellation()
            if hiddenAssetIds.contains(candidate.id) {
                addDebugMessage("Skipped hidden candidate: \(candidate.title)")
                continue
            }
            return candidate
        }
        throw ImmichAPIError.noEligibleVideo
    }

    private func fetchNextSearchCandidate() async throws -> VideoCandidate {
        try Task.checkCancellation()
        let query = configStore.config.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw ImmichAPIError.noEligibleVideo
        }

        if query != searchLoadedQuery {
            resetSearchState()
            searchLoadedQuery = query
        }

        if searchPool.isEmpty {
            try await refillSearchPool(minimumCount: 12)
            try Task.checkCancellation()
        }

        if searchPool.isEmpty {
            resetSearchState()
            searchLoadedQuery = query
            try await refillSearchPool(minimumCount: 12)
            try Task.checkCancellation()
        }

        guard !searchPool.isEmpty else {
            throw ImmichAPIError.noEligibleVideo
        }

        let candidate: VideoCandidate
        if configStore.config.playbackOrder == "random" {
            let index = Int.random(in: 0..<searchPool.count)
            candidate = searchPool.remove(at: index)
        } else {
            candidate = searchPool.removeFirst()
        }
        searchSeenIDs.insert(candidate.id)
        return candidate
    }

    private func refillSearchPool(minimumCount: Int) async throws {
        try Task.checkCancellation()
        let target = max(1, minimumCount)
        let query = configStore.config.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        while searchPool.count < target && searchHasMorePages {
            let pageResults = try await client.searchSmartVideos(
                config: configStore.config,
                query: query,
                page: searchNextPage,
                size: 100
            )
            try Task.checkCancellation()
            searchNextPage += 1
            searchHasMorePages = !pageResults.isEmpty

            let filtered = pageResults.filter { candidate in
                guard configStore.config.includesDuration(candidate.duration) else { return false }
                guard !hiddenAssetIds.contains(candidate.id) else { return false }
                guard !searchSeenIDs.contains(candidate.id) else { return false }
                guard candidate.id != currentItem?.id else { return false }
                guard !queue.contains(where: { $0.id == candidate.id }) else { return false }
                return true
            }

            if filtered.isEmpty && pageResults.isEmpty {
                break
            }

            searchPool.append(contentsOf: filtered)
        }
    }

    private func resetSearchState() {
        searchLoadedQuery = ""
        searchPool = []
        searchSeenIDs = []
        searchNextPage = 1
        searchHasMorePages = true
    }

    private func fillQueueIfNeeded() async {
        guard started, !Task.isCancelled else { return }
        let generation = playbackGeneration
        let target = max(1, min(configStore.config.queueTargetSize, 5))
        addDebugMessage("Queue check \(queue.count)/\(target)")
        var attempts = 0
        while (queue.count + inflightQueueFetches) < target, attempts < target * 4 {
            attempts += 1
            inflightQueueFetches += 1
            defer { if generation == playbackGeneration { inflightQueueFetches -= 1 } }

            do {
                let item = try await fetchNextCandidate()
                guard !Task.isCancelled else { return }
                if currentItem?.id == item.id { continue }
                if hiddenAssetIds.contains(item.id) { continue }
                if queue.contains(where: { $0.id == item.id }) { continue }
                queue.append(item)
                updateStatus()
                await maybePrepareNext()
                guard !Task.isCancelled else { return }
                if fallbackMessage == L10n.tr(
                    "errors.playback.fetch_next_retry",
                    "Could not fetch next video. Retrying...",
                    comment: "Playback failure message when queue cannot fetch next video"
                ) {
                    fallbackMessage = ""
                }
                addDebugMessage("Queued \(item.title)")
            } catch {
                guard !Task.isCancelled else { return }
                if configStore.config.debug {
                    print("[ChannelCoordinator] queue fetch failed: \(error)")
                }
                registerPlaybackFailure(L10n.tr(
                    "errors.playback.fetch_next_retry",
                    "Could not fetch next video. Retrying...",
                    comment: "Playback failure message when queue cannot fetch next video"
                ), error: error)
                addDebugMessage("Queue fetch failed: \(error.localizedDescription)")
                break
            }
        }
        updateStatus()
    }

    private func maybePrepareNext() async {
        guard started, !Task.isCancelled else { return }
        let generation = playbackGeneration
        guard !preparingNext, !transitionInProgress, !bootstrapping else { return }
        guard let next = queue.first else { return }
        guard nextPreparedId != next.id else { return }

        preparingNext = true
        defer { if generation == playbackGeneration { preparingNext = false } }
        addDebugMessage("Preparing next: \(next.title)")

        do {
            try await prepareHiddenPlayer(with: next)
            guard !Task.isCancelled else { return }
            nextPreparedId = next.id
            addDebugMessage("Prepared next: \(next.title)")
        } catch {
            guard !Task.isCancelled else { return }
            addDebugMessage("Prepare failed: \(next.title)")
            if configStore.config.debug {
                print("[ChannelCoordinator] prepare failed: \(error)")
            }
        }
    }

    private func prepareHiddenPlayer(with candidate: VideoCandidate) async throws {
        try Task.checkCancellation()
        let hidden = hiddenPlayer()
        let item = try client.makePlaybackItem(candidate: candidate, config: configStore.config)
        hidden.replaceCurrentItem(with: item)
        hidden.isMuted = activePlayer().isMuted
        _ = try await waitUntilReadyToPlay(item: item, timeoutSeconds: 12)
        try Task.checkCancellation()
        try validatePlaybackDuration(item, for: candidate)
    }

    // Poll only during loading: a cancelled task or expired deadline always exits,
    // even if AVFoundation never emits another status notification.
    func waitUntilReadyToPlay(item: AVPlayerItem, timeoutSeconds: TimeInterval) async throws -> AVPlayerItem {
        let deadline = ProcessInfo.processInfo.systemUptime + timeoutSeconds
        while true {
            try Task.checkCancellation()
            switch item.status {
            case .readyToPlay: return item
            case .failed: throw item.error ?? ImmichAPIError.invalidResponse
            default: break
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw ImmichAPIError.invalidResponse
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func playOnActivePlayer(_ candidate: VideoCandidate) async throws {
        try Task.checkCancellation()
        let player = activePlayer()
        let item = try client.makePlaybackItem(candidate: candidate, config: configStore.config)
        player.replaceCurrentItem(with: item)
        player.isMuted = readMutedPreference()
        _ = try await waitUntilReadyToPlay(item: item, timeoutSeconds: 12)
        try Task.checkCancellation()
        try validatePlaybackDuration(item, for: candidate)
        try await playWithAutoplayFallback(player: player)
        try Task.checkCancellation()

        if isPlaybackPaused { player.pause() }
        resetProgressWatchdog()
        currentItem = candidate
        canGoBack = !history.isEmpty
        currentIsFavorite = candidate.isFavorite
        playbackProgress = 0
        elapsedText = "0:00"
        totalDurationText = formatDuration(candidate.duration)
        secondsLeftText = "-\(formatDuration(candidate.duration))"
        currentImmichAssetURL = buildImmichAssetURL(for: candidate)
        updateCurrentChannelContext(for: candidate)
        await refreshCurrentMetadata(for: candidate)
        try Task.checkCancellation()
        await resetDebugPlaybackTelemetry(for: item)
        try Task.checkCancellation()
        let overlay = overlayTexts(for: candidate)
        dateLocationText = overlayDateLocationText(for: candidate)
        title = overlay.title
        captionText = overlay.caption
        clearPlaybackFailureState()
        await recordWatchStart(for: candidate)
        try Task.checkCancellation()
        await persistSequentialProgress(for: candidate)
        try Task.checkCancellation()
        installTimeObserver()
        updateStatus()
        addDebugMessage("Playing: \(candidate.title)")
    }

    private func validatePlaybackDuration(_ item: AVPlayerItem, for candidate: VideoCandidate) throws {
        let actualDuration = CMTimeGetSeconds(item.duration)
        guard configStore.config.includesDuration(actualDuration) else {
            addDebugMessage("Skipped short playback: \(candidate.title) metadata=\(String(format: "%.2f", candidate.duration))s actual=\(actualDuration.isFinite ? String(format: "%.2f", actualDuration) : "unknown")s")
            throw PlaybackDurationValidationError.belowMinimum
        }
    }

    private func playWithAutoplayFallback(player: AVPlayer) async throws {
        try Task.checkCancellation()
        guard !isPlaybackPaused else { return }
        let wasMuted = player.isMuted
        do {
            try await player.playAsync()
            try Task.checkCancellation()
        } catch {
            try Task.checkCancellation()
            addDebugMessage("Autoplay fallback: mute and retry")
            player.isMuted = true
            do {
                try await player.playAsync()
                try Task.checkCancellation()
                player.isMuted = wasMuted
            } catch {
                try Task.checkCancellation()
                player.isMuted = wasMuted
                throw error
            }
        }
    }

    private func transitionToNext(reason: String) async {
        guard started, !Task.isCancelled else { return }
        let generation = playbackGeneration
        guard !transitionInProgress, !bootstrapping else {
            addDebugMessage("Transition skipped: already in progress")
            return
        }
        transitionInProgress = true
        defer { if generation == playbackGeneration { transitionInProgress = false } }
        addDebugMessage("Transition start: \(reason)")

        if queue.isEmpty {
            await fillQueueIfNeeded()
            guard !Task.isCancelled else { return }
        }

        guard !queue.isEmpty else {
            registerPlaybackFailure(L10n.tr(
                "errors.playback.no_eligible_videos_retry",
                "No eligible videos right now. Retrying...",
                comment: "Playback failure message when no qualifying videos are available"
            ))
            return
        }

        let next = queue.removeFirst()
        let previous = currentItem
        updateStatus()

        do {
            while preparingNext {
                try await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
            }
            if nextPreparedId != next.id {
                try await prepareHiddenPlayer(with: next)
                guard !Task.isCancelled else { return }
            }

            let outgoing = activePlayer()
            let incoming = hiddenPlayer()
            incoming.isMuted = outgoing.isMuted
            try await playWithAutoplayFallback(player: incoming)
            guard !Task.isCancelled else { return }

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
                try await Task.sleep(nanoseconds: UInt64(Double(configStore.config.crossfadeDurationMs) * 1_000_000))
                guard !Task.isCancelled else { return }
            } else {
                if activeIndex == 0 {
                    opacityA = 0
                    opacityB = 1
                } else {
                    opacityA = 1
                    opacityB = 0
                }
            }

            if isPlaybackPaused { incoming.pause() }
            outgoing.pause()
            outgoing.replaceCurrentItem(with: nil)

            activeIndex = 1 - activeIndex
            resetProgressWatchdog()
            if let previous {
                history.append(previous)
                if history.count > 100 {
                    history.removeFirst(history.count - 100)
                }
            }
            currentItem = next
            canGoBack = !history.isEmpty
            currentIsFavorite = next.isFavorite
            playbackProgress = 0
            elapsedText = "0:00"
            totalDurationText = formatDuration(next.duration)
            secondsLeftText = "-\(formatDuration(next.duration))"
            currentImmichAssetURL = buildImmichAssetURL(for: next)
            updateCurrentChannelContext(for: next)
            await refreshCurrentMetadata(for: next)
            guard !Task.isCancelled else { return }
            let overlay = overlayTexts(for: next)
            dateLocationText = overlayDateLocationText(for: next)
            title = overlay.title
            captionText = overlay.caption
            nextPreparedId = ""
            clearPlaybackFailureState()
            await recordWatchStart(for: next)
            guard !Task.isCancelled else { return }
            await persistSequentialProgress(for: next)
            guard !Task.isCancelled else { return }

            installTimeObserver()
            await fillQueueIfNeeded()
            guard !Task.isCancelled else { return }
            await maybePrepareNext()
            guard !Task.isCancelled else { return }

            if configStore.config.debug {
                print("[ChannelCoordinator] transitioned: \(reason) -> \(next.id)")
            }
            addDebugMessage("Next: \(next.title)")
        } catch {
            guard !Task.isCancelled else { return }
            if error is PlaybackDurationValidationError {
                addDebugMessage("Transition skipped short playback: \(next.title)")
                nextPreparedId = ""
                transitionInProgress = false
                await transitionToNext(reason: "short_duration_skip")
                guard !Task.isCancelled else { return }
                return
            }
            registerPlaybackFailure(L10n.tr(
                "errors.playback.transition_failed_skipping",
                "Transition failed. Skipping...",
                comment: "Playback failure message when transition to next video fails"
            ), error: error)
            nextPreparedId = ""
            if configStore.config.debug {
                print("[ChannelCoordinator] transition failed: \(reason) error=\(error)")
            }
            addDebugMessage("Transition failed: \(error.localizedDescription)")
        }
    }

    private func transitionToPrevious(reason: String) async {
        guard started, !Task.isCancelled else { return }
        let generation = playbackGeneration
        guard !transitionInProgress, !bootstrapping else {
            addDebugMessage("Back skipped: transition already in progress")
            return
        }
        guard let previous = history.popLast() else {
            addDebugMessage("Back skipped: no history")
            return
        }
        addDebugMessage("Transition back start: \(reason)")

        transitionInProgress = true
        defer { if generation == playbackGeneration { transitionInProgress = false } }

        let outgoingCurrent = currentItem

        do {
            while preparingNext {
                try await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
            }
            try await prepareHiddenPlayer(with: previous)
            guard !Task.isCancelled else { return }

            let outgoing = activePlayer()
            let incoming = hiddenPlayer()
            incoming.isMuted = outgoing.isMuted
            try await playWithAutoplayFallback(player: incoming)
            guard !Task.isCancelled else { return }

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
                try await Task.sleep(nanoseconds: UInt64(Double(configStore.config.crossfadeDurationMs) * 1_000_000))
                guard !Task.isCancelled else { return }
            } else {
                if activeIndex == 0 {
                    opacityA = 0
                    opacityB = 1
                } else {
                    opacityA = 1
                    opacityB = 0
                }
            }

            if isPlaybackPaused { incoming.pause() }
            outgoing.pause()
            outgoing.replaceCurrentItem(with: nil)

            activeIndex = 1 - activeIndex
            resetProgressWatchdog()
            currentItem = previous
            canGoBack = !history.isEmpty
            currentIsFavorite = previous.isFavorite
            playbackProgress = 0
            elapsedText = "0:00"
            totalDurationText = formatDuration(previous.duration)
            secondsLeftText = "-\(formatDuration(previous.duration))"
            currentImmichAssetURL = buildImmichAssetURL(for: previous)
            updateCurrentChannelContext(for: previous)
            await refreshCurrentMetadata(for: previous)
            guard !Task.isCancelled else { return }
            let overlay = overlayTexts(for: previous)
            dateLocationText = overlayDateLocationText(for: previous)
            title = overlay.title
            captionText = overlay.caption
            nextPreparedId = ""
            clearPlaybackFailureState()
            await recordWatchStart(for: previous)
            guard !Task.isCancelled else { return }
            await persistSequentialProgress(for: previous)
            guard !Task.isCancelled else { return }

            if let outgoingCurrent, !queue.contains(where: { $0.id == outgoingCurrent.id }) {
                queue.insert(outgoingCurrent, at: 0)
            }

            installTimeObserver()
            await fillQueueIfNeeded()
            guard !Task.isCancelled else { return }
            await maybePrepareNext()
            guard !Task.isCancelled else { return }

            if configStore.config.debug {
                print("[ChannelCoordinator] transitioned: \(reason) -> \(previous.id)")
            }
            addDebugMessage("Back: \(previous.title)")
        } catch {
            guard !Task.isCancelled else { return }
            history.append(previous)
            canGoBack = !history.isEmpty
            fallbackMessage = String(format: L10n.tr(
                "errors.playback.back_failed",
                "Back failed: %@",
                comment: "Back navigation failure message with reason"
            ), error.localizedDescription)
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
        configStore.config.useSQLiteCache ||
        isSequentialOrder(configStore.config.playbackOrder) ||
        configStore.config.hasCollectionFilter
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
        let bitrateText = configStore.config.debug ? " · \(currentBitrateStatus())" : ""
        statusText = "Queue \(queue.count)/\(configStore.config.queueTargetSize) · \(orderLabel) · \(mode)\(syncText)\(debugQuality)\(bitrateText)"
    }

    private func applyMuteState(_ muted: Bool) {
        playerA.isMuted = muted
        playerB.isMuted = muted
        objectWillChange.send()
    }

    private func readMutedPreference() -> Bool {
        let key = "HomeVideoChannel.Muted"
        if UserDefaults.standard.object(forKey: key) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func saveMutedPreference(_ muted: Bool) {
        UserDefaults.standard.set(muted, forKey: "HomeVideoChannel.Muted")
    }

    private func setFavorite(for candidate: VideoCandidate, to isFavorite: Bool) async {
        guard !Task.isCancelled else { return }
        guard !favoriteUpdateInProgress else { return }

        favoriteUpdateInProgress = true
        let previous = candidate.isFavorite
        addDebugMessage("\(isFavorite ? "Favorite" : "Unfavorite") requested: \(candidate.title)")
        applyFavoriteStateLocally(assetId: candidate.id, isFavorite: isFavorite)

        do {
            try await client.updateFavorite(assetId: candidate.id, isFavorite: isFavorite, config: configStore.config)
            guard !Task.isCancelled else { return }
            try await store.initializeSchema()
            guard !Task.isCancelled else { return }
            try await store.setFavorite(assetId: candidate.id, isFavorite: isFavorite)
            guard !Task.isCancelled else { return }
            addDebugMessage("\(isFavorite ? "Favorited" : "Unfavorited"): \(candidate.title)")
        } catch {
            guard !Task.isCancelled else { return }
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
            currentInfoFields = buildInfoFields(for: item.withFavorite(isFavorite), peopleText: currentPeopleText)
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
            currentInfoFields = buildInfoFields(for: updated, peopleText: currentPeopleText)
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
            currentInfoFields = buildInfoFields(for: updated, peopleText: currentPeopleText)
        }
        if let index = queue.firstIndex(where: { $0.id == assetId }) {
            queue[index] = queue[index].withTimesWatched(timesWatched)
        }
        for i in history.indices where history[i].id == assetId {
            history[i] = history[i].withTimesWatched(timesWatched)
        }
    }

    private func recordWatchStart(for candidate: VideoCandidate) async {
        guard !Task.isCancelled else { return }
        guard shouldUseSQLiteSelection() else { return }
        do {
            let count = try await store.incrementWatchCount(assetId: candidate.id)
            guard !Task.isCancelled else { return }
            sessionVideosWatchedCount += 1
            applyWatchCountLocally(assetId: candidate.id, timesWatched: count)
            if currentItem?.id == candidate.id {
                currentInfoFields = buildInfoFields(for: candidate.withTimesWatched(count), peopleText: currentPeopleText)
            }
            addDebugMessage("Watch count \(count): \(candidate.title)")
        } catch {
            guard !Task.isCancelled else { return }
            if configStore.config.debug {
                print("[ChannelCoordinator] watch count update failed: \(error)")
            }
            addDebugMessage("Watch count update failed: \(candidate.title)")
        }
    }

    private func ensureSequentialStateLoaded() async {
        guard !Task.isCancelled else { return }
        guard !sequentialStateLoaded else { return }
        do {
            let loadedAssetId = try await store.getSequentialLastAssetId()
            guard !Task.isCancelled else { return }
            sequentialLastAssetId = loadedAssetId
            sequentialStateLoaded = true
            if let sequentialLastAssetId {
                addDebugMessage("Seq resume at \(sequentialLastAssetId)")
            } else {
                addDebugMessage("Seq resume at start")
            }
        } catch {
            guard !Task.isCancelled else { return }
            sequentialStateLoaded = true
            addDebugMessage("Seq state load failed: \(error.localizedDescription)")
        }
    }

    private func persistSequentialProgress(for candidate: VideoCandidate) async {
        guard !Task.isCancelled else { return }
        guard isSequentialOrder(configStore.config.playbackOrder) else { return }
        sequentialLastAssetId = candidate.id
        sequentialStateLoaded = true
        do {
            try await store.setSequentialLastAssetId(candidate.id)
            guard !Task.isCancelled else { return }
        } catch {
            guard !Task.isCancelled else { return }
            addDebugMessage("Seq progress save failed: \(error.localizedDescription)")
        }
    }

    private func resetSequentialProgress() async {
        guard !Task.isCancelled else { return }
        do {
            try await store.clearSequentialLastAssetId()
            guard !Task.isCancelled else { return }
            sequentialLastAssetId = nil
            sequentialStateLoaded = true
            nextPreparedId = ""
            queue.removeAll()
            addDebugMessage("Sequential progress reset")
            await fillQueueIfNeeded()
            guard !Task.isCancelled else { return }
            await loadLibraryStats()
            guard !Task.isCancelled else { return }
        } catch {
            guard !Task.isCancelled else { return }
            addDebugMessage("Seq progress reset failed: \(error.localizedDescription)")
        }
    }

    private func isSequentialOrder(_ order: String) -> Bool {
        order == "sequential_oldest" || order == "sequential_newest" || order == "sequential"
    }

    private func loadLibraryStats() async {
        guard !Task.isCancelled else { return }
        guard shouldUseSQLiteSelection() else {
            statsLastError = L10n.tr(
                "errors.library.sqlite_cache_disabled",
                "SQLite cache is disabled.",
                comment: "Library stats error when cache-backed stats are unavailable"
            )
            return
        }

        do {
            try await store.initializeSchema()
            guard !Task.isCancelled else { return }
            let stats = try await store.getLibraryStats()
            guard !Task.isCancelled else { return }
            statsTotalVideos = stats.totalVideos
            statsTotalVideoDuration = stats.totalVideoDuration
            statsTotalWatchedPlays = stats.totalWatchedPlays
            statsTotalWatchedDuration = stats.totalWatchedDuration
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
                currentInfoFields = buildInfoFields(for: currentItem, peopleText: currentPeopleText)
            }
        } catch {
            guard !Task.isCancelled else { return }
            statsLastError = error.localizedDescription
            addDebugMessage("Library stats failed: \(error.localizedDescription)")
        }
    }

    private func formatTop(_ rows: [SQLiteVideoStore.RankedStat]) -> String {
        guard !rows.isEmpty else { return L10n.unknownDash }
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
        let people = configStore.config.showPeopleOverlay ? currentPeopleText : ""
        let parts = [monthYear, location, people].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return parts.joined(separator: "\n")
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
            return date.formatted(Date.FormatStyle().month(.abbreviated).year())
        }

        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "en_US_POSIX")
        f1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = f1.date(from: value) {
            return date.formatted(Date.FormatStyle().month(.abbreviated).year())
        }

        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = f2.date(from: value) {
            return date.formatted(Date.FormatStyle().month(.abbreviated).year())
        }

        if value.count >= 7 {
            let prefix = String(value.prefix(7))
            let parts = prefix.split(separator: "-")
            if parts.count == 2, parts[0].count == 4, let monthNumber = Int(parts[1]), (1...12).contains(monthNumber) {
                var comps = DateComponents()
                comps.year = Int(parts[0])
                comps.month = monthNumber
                comps.day = 1
                if let date = Calendar.current.date(from: comps) {
                    return date.formatted(Date.FormatStyle().month(.abbreviated).year())
                }
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

    private func updateCurrentChannelContext(for candidate: VideoCandidate) {
        currentCaptureDateRaw = candidate.captureDate
        currentPlaceCity = candidate.city.trimmingCharacters(in: .whitespacesAndNewlines)
        currentPlaceCountry = candidate.country.trimmingCharacters(in: .whitespacesAndNewlines)
        currentPlaceLabel = formatLocation(city: candidate.city, country: candidate.country)
    }

    private func refreshCurrentMetadata(for candidate: VideoCandidate) async {
        guard !Task.isCancelled else { return }
        let peopleText = await resolvePeopleText(for: candidate)
        guard !Task.isCancelled else { return }
        currentPeopleText = peopleText
        currentInfoFields = buildInfoFields(for: candidate, peopleText: peopleText)
    }

    private func resolvePeopleText(for candidate: VideoCandidate) async -> String {
        let directNames = sanitizedPeopleNames(candidate.peopleNames)
        if !directNames.isEmpty {
            return directNames.joined(separator: ", ")
        }

        guard shouldUseSQLiteSelection() else { return "" }
        let cachedNames = (try? await store.peopleNames(for: candidate.id)) ?? []
        return sanitizedPeopleNames(cachedNames).joined(separator: ", ")
    }

    private func sanitizedPeopleNames(_ names: [String]) -> [String] {
        Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func buildInfoFields(for candidate: VideoCandidate, peopleText: String) -> [VideoInfoField] {
        let monthYear = formatMonthYear(candidate.captureDate)
        let location = formatLocation(city: candidate.city, country: candidate.country)
        let camera = [candidate.cameraMake, candidate.cameraModel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let dateTime = formatCaptureDateTime(candidate.captureDate)

        var fields: [VideoInfoField] = [
            VideoInfoField(id: "title", label: L10n.tr("library.metadata.field.title", "Title", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.title)),
            VideoInfoField(id: "id", label: L10n.tr("library.metadata.field.asset_id", "Asset ID", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.id)),
            VideoInfoField(id: "duration", label: L10n.tr("library.metadata.field.duration", "Duration", comment: "Metadata field label"), value: formatDuration(candidate.duration)),
            VideoInfoField(id: "times_watched", label: L10n.tr("library.metadata.field.times_watched", "Times Watched", comment: "Metadata field label"), value: String(candidate.timesWatched)),
            VideoInfoField(id: "session_watched", label: L10n.tr("library.metadata.field.session_watched", "Session Watched", comment: "Metadata field label"), value: String(sessionVideosWatchedCount)),
            VideoInfoField(id: "favorite", label: L10n.tr("library.metadata.field.favorite", "Favorite", comment: "Metadata field label"), value: candidate.isFavorite ? L10n.tr("common.yes", "Yes", comment: "Yes value") : L10n.tr("common.no", "No", comment: "No value")),
            VideoInfoField(id: "hidden", label: L10n.tr("library.metadata.field.hidden", "Hidden", comment: "Metadata field label"), value: candidate.isHidden ? L10n.tr("common.yes", "Yes", comment: "Yes value") : L10n.tr("common.no", "No", comment: "No value"))
        ]

        if !monthYear.isEmpty {
            fields.append(VideoInfoField(id: "month_year", label: L10n.tr("library.metadata.field.year_month", "Year / Month", comment: "Metadata field label"), value: monthYear))
        }
        if !location.isEmpty {
            fields.append(VideoInfoField(id: "current_location", label: L10n.tr("library.metadata.field.current_location", "Current Location", comment: "Metadata field label"), value: location))
        }
        if !peopleText.isEmpty {
            fields.append(VideoInfoField(id: "people", label: L10n.tr("library.metadata.field.people", "People", comment: "Metadata field label"), value: peopleText))
        }

        fields.append(contentsOf: [
            VideoInfoField(id: "capture_raw", label: L10n.tr("library.metadata.field.capture_raw", "Capture Date (Raw)", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.captureDate)),
            VideoInfoField(id: "capture_fmt", label: L10n.tr("library.metadata.field.capture_parsed", "Capture Date (Parsed)", comment: "Metadata field label"), value: nonEmptyOrDash(dateTime)),
            VideoInfoField(id: "city", label: L10n.tr("library.metadata.field.city", "City", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.city)),
            VideoInfoField(id: "country", label: L10n.tr("library.metadata.field.country", "Country", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.country)),
            VideoInfoField(id: "location", label: L10n.tr("library.metadata.field.location", "Location", comment: "Metadata field label"), value: nonEmptyOrDash(location)),
            VideoInfoField(id: "camera_make", label: L10n.tr("library.metadata.field.camera_make", "Camera Make", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.cameraMake)),
            VideoInfoField(id: "camera_model", label: L10n.tr("library.metadata.field.camera_model", "Camera Model", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.cameraModel)),
            VideoInfoField(id: "camera", label: L10n.tr("library.metadata.field.camera_combined", "Camera (Combined)", comment: "Metadata field label"), value: nonEmptyOrDash(camera)),
            VideoInfoField(id: "lens", label: L10n.tr("library.metadata.field.lens", "Lens", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.lensModel)),
            VideoInfoField(id: "fnumber", label: L10n.tr("library.metadata.field.aperture", "Aperture", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.fNumber)),
            VideoInfoField(id: "focal", label: L10n.tr("library.metadata.field.focal_length", "Focal Length", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.focalLength)),
            VideoInfoField(id: "iso", label: L10n.tr("library.metadata.field.iso", "ISO", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.iso)),
            VideoInfoField(id: "shutter", label: L10n.tr("library.metadata.field.exposure", "Exposure", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.exposureTime)),
            VideoInfoField(id: "latitude", label: L10n.tr("library.metadata.field.latitude", "Latitude", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.latitude)),
            VideoInfoField(id: "longitude", label: L10n.tr("library.metadata.field.longitude", "Longitude", comment: "Metadata field label"), value: nonEmptyOrDash(candidate.longitude)),
            VideoInfoField(id: "immich_url", label: L10n.tr("library.metadata.field.immich_url", "Immich URL", comment: "Metadata field label"), value: nonEmptyOrDash(currentImmichAssetURL))
        ])

        return fields
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return L10n.unknownDash }
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
            return date.formatted(date: .numeric, time: .standard)
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
                return date.formatted(date: .numeric, time: .standard)
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
        buffering
            ? L10n.tr("playback.buffering", "Buffering...", comment: "Playback buffering status")
            : L10n.tr("playback.buffering_ended", "Buffering ended", comment: "Playback buffering ended status")
    }

    private func currentBitrateStatus() -> String {
        guard let event = activePlayer().currentItem?.accessLog()?.events.last else {
            return "br -"
        }

        let observed = event.observedBitrate
        let indicated = event.indicatedBitrate
        let observedText = observed > 0 ? formatBitrate(observed) : "-"
        let indicatedText = indicated > 0 ? formatBitrate(indicated) : "-"
        return "br \(observedText)/\(indicatedText)"
    }

    private func formatBitrate(_ bitsPerSecond: Double) -> String {
        let megabitsPerSecond = bitsPerSecond / 1_000_000
        if megabitsPerSecond >= 100 {
            return String(format: "%.0fMbps", megabitsPerSecond)
        }
        if megabitsPerSecond >= 10 {
            return String(format: "%.1fMbps", megabitsPerSecond)
        }
        return String(format: "%.2fMbps", megabitsPerSecond)
    }

    private func updateDebugTelemetry(current: Double, item: AVPlayerItem) {
        let bufferAheadSeconds = currentBufferAheadSeconds(current: current, item: item)
        let bitrateText = currentBitrateStatus()
        let modeText = currentPlaybackModeStatus(item: item)
        let historyText = historyStatus(current: current, bufferAheadSeconds: bufferAheadSeconds, item: item)

        debugTelemetryText = [
            "buf \(String(format: "%.1fs", bufferAheadSeconds))",
            bitrateText,
            "fmt \(currentFormatDebugText)",
            "src \(modeText)",
            historyText
        ].joined(separator: "\n")
    }

    private func currentBufferAheadSeconds(current: Double, item: AVPlayerItem) -> Double {
        for rangeValue in item.loadedTimeRanges {
            let range = rangeValue.timeRangeValue
            let start = CMTimeGetSeconds(range.start)
            let end = start + CMTimeGetSeconds(range.duration)
            if current >= start && current <= end {
                return max(0, end - current)
            }
        }
        return 0
    }

    private func historyStatus(current: Double, bufferAheadSeconds: Double, item: AVPlayerItem) -> String {
        if current - lastDebugHistorySampleTime >= 5 || debugHistorySamples.isEmpty {
            lastDebugHistorySampleTime = current
            debugHistorySamples.append("\(formatDuration(current)) \(shortBitrateStatus()) \(String(format: "%.1fs", bufferAheadSeconds))")
            if debugHistorySamples.count > 5 {
                debugHistorySamples.removeFirst(debugHistorySamples.count - 5)
            }
        }
        return "hist " + debugHistorySamples.joined(separator: " | ")
    }

    private func shortBitrateStatus() -> String {
        guard let event = activePlayer().currentItem?.accessLog()?.events.last else {
            return "-/-"
        }
        let observed = event.observedBitrate > 0 ? formatBitrate(event.observedBitrate) : "-"
        let indicated = event.indicatedBitrate > 0 ? formatBitrate(event.indicatedBitrate) : "-"
        return "\(observed)/\(indicated)"
    }

    private func currentPlaybackModeStatus(item: AVPlayerItem) -> String {
        if let eventURI = item.accessLog()?.events.last?.uri, let url = URL(string: eventURI) {
            return compactPlaybackPath(url)
        }
        if let urlAsset = item.asset as? AVURLAsset {
            return compactPlaybackPath(urlAsset.url)
        }
        return "-"
    }

    private func compactPlaybackPath(_ url: URL) -> String {
        let path = url.path
        if path.contains("/video/playback") {
            return "playback"
        }
        if path.contains("/original") {
            return "original"
        }
        return path.isEmpty ? url.host ?? "-" : path
    }

    private func resetDebugPlaybackTelemetry(for item: AVPlayerItem) async {
        guard !Task.isCancelled else { return }
        debugHistorySamples = []
        lastDebugHistorySampleTime = 0
        let formatText = await debugFormatText(for: item)
        guard !Task.isCancelled else { return }
        currentFormatDebugText = formatText
        if configStore.config.debug {
            updateStatus()
        }
    }

    private func debugFormatText(for item: AVPlayerItem) async -> String {
        do {
            let tracks = try await item.asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                return "-"
            }

            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let width = Int(abs(transformedSize.width))
            let height = Int(abs(transformedSize.height))
            let fps = try await track.load(.nominalFrameRate)
            let codec = await codecName(for: track)

            if fps > 0 {
                return "\(width)x\(height) \(codec) \(Int(fps.rounded()))fps"
            }
            return "\(width)x\(height) \(codec)"
        } catch {
            return "-"
        }
    }

    private func codecName(for track: AVAssetTrack) async -> String {
        guard let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first else {
            return "-"
        }

        let subtype = CMFormatDescriptionGetMediaSubType(description)
        switch subtype {
        case kCMVideoCodecType_H264:
            return "H.264"
        case kCMVideoCodecType_HEVC:
            return "HEVC"
        case kCMVideoCodecType_AppleProRes422,
             kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT,
             kCMVideoCodecType_AppleProRes422Proxy:
            return "ProRes"
        default:
            return fourCCString(subtype)
        }
    }

    private func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar((code >> 24) & 0xff),
            CChar((code >> 16) & 0xff),
            CChar((code >> 8) & 0xff),
            CChar(code & 0xff),
            0
        ]
        return String(cString: bytes)
    }

    private func nonEmptyOrDash(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.unknownDash : trimmed
    }
}

private extension AVPlayer {
    @MainActor
    func playAsync() async throws {
        try Task.checkCancellation()
        play()
        try await Task.sleep(nanoseconds: 200_000_000)
        if let error { throw error }
    }
}

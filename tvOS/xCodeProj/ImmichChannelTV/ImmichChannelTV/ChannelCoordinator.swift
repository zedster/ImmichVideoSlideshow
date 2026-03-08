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
    @Published var fallbackMessage: String = ""
    @Published var statusText: String = ""
    @Published var currentInfoFields: [VideoInfoField] = []
    @Published var currentIsFavorite: Bool = false
    @Published var isPlaybackPaused: Bool = false
    @Published var favoriteUpdateInProgress: Bool = false
    @Published var isSyncing: Bool = false
    @Published var syncPagesFetched: Int = 0
    @Published var syncRowsUpserted: Int = 0
    @Published var syncLastSyncAt: String = "-"
    @Published var syncLastError: String = ""
    @Published var shouldOpenSetup: Bool = false
    @Published var setupErrorMessage: String = ""

    private let client: ImmichAPIClient
    private let configStore: ConfigStore
    private let store: SQLiteVideoStore
    private lazy var syncService = VideoSyncService(client: client, store: store)

    private var queue: [VideoCandidate] = []
    private var currentItem: VideoCandidate?
    private var transitionInProgress = false
    private var preparingNext = false
    private var nextPreparedId = ""
    private var inflightQueueFetches = 0
    private var started = false
    private var consecutivePlaybackFailures = 0
    private let maxConsecutivePlaybackFailures = 5

    private var timeObserver: Any?
    private var timeObserverPlayer: AVPlayer?
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
            return
        }
        guard !started else { return }
        started = true

        setupEndObserver()
        applyMuteState(readMutedPreference())
        updateStatus()

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
        stop()
        queue = []
        currentItem = nil
        nextPreparedId = ""
        consecutivePlaybackFailures = 0
        shouldOpenSetup = false
        setupErrorMessage = ""
        fallbackMessage = ""
        title = "Loading..."
        captionText = ""
        currentInfoFields = []
        currentIsFavorite = false
        isPlaybackPaused = false
        favoriteUpdateInProgress = false
        opacityA = 1
        opacityB = 0
        activeIndex = 0
        start()
    }

    func acknowledgeSetupOpenRequest() {
        shouldOpenSetup = false
    }

    func skip() {
        Task {
            await transitionToNext(reason: "manual_skip")
        }
    }

    func toggleMute() {
        let next = !activePlayer().isMuted
        applyMuteState(next)
        saveMutedPreference(next)
    }

    func muteButtonLabel() -> String {
        activePlayer().isMuted ? "Unmute" : "Mute"
    }

    func forceSyncNow() {
        Task {
            await runForceSync()
        }
    }

    func favoriteButtonLabel() -> String {
        currentIsFavorite ? "Unfavorite" : "Favorite"
    }

    func favoriteButtonSystemImage() -> String {
        currentIsFavorite ? "heart.fill" : "heart"
    }

    func playPauseButtonSystemImage() -> String {
        isPlaybackPaused ? "play.fill" : "pause.fill"
    }

    func togglePlayPause() {
        let player = activePlayer()
        if isPlaybackPaused {
            player.play()
            isPlaybackPaused = false
        } else {
            player.pause()
            isPlaybackPaused = true
        }
    }

    func toggleFavorite() {
        guard let currentItem else { return }
        let nextValue = !currentItem.isFavorite
        Task {
            await setFavorite(for: currentItem, to: nextValue)
        }
    }

    private func bootstrapPlayback() async {
        do {
            if configStore.config.useSQLiteCache {
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
        } catch {
            registerPlaybackFailure("Could not load initial video. Retrying...", error: error)
            if configStore.config.debug {
                print("[ChannelCoordinator] bootstrap failed: \(error)")
            }
        }
    }

    private func runForceSync(silent: Bool = false) async {
        guard configStore.config.useSQLiteCache else { return }
        guard !isSyncing else { return }

        isSyncing = true
        syncPagesFetched = 0
        syncRowsUpserted = 0
        syncLastError = ""
        updateStatus()
        if !silent {
            fallbackMessage = "Syncing metadata..."
        }

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
        } catch {
            syncLastError = error.localizedDescription
            fallbackMessage = "Sync failed: \(error.localizedDescription)"
            if configStore.config.debug {
                print("[ChannelCoordinator] sync failed: \(error)")
            }
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
        if configStore.config.useSQLiteCache {
            if let fromDB = try await store.selectRandom(minDuration: configStore.config.minDuration, onlyFavorites: configStore.config.onlyFavorites) {
                return fromDB
            }
            await runForceSync(silent: true)
            if let fromDB = try await store.selectRandom(minDuration: configStore.config.minDuration, onlyFavorites: configStore.config.onlyFavorites) {
                return fromDB
            }
        }

        return try await client.fetchRandomEligibleVideo(config: configStore.config)
    }

    private func fillQueueIfNeeded() async {
        let target = max(1, min(configStore.config.queueTargetSize, 5))
        while (queue.count + inflightQueueFetches) < target {
            inflightQueueFetches += 1
            defer { inflightQueueFetches -= 1 }

            do {
                let item = try await fetchNextCandidate()
                if currentItem?.id == item.id { continue }
                if queue.contains(where: { $0.id == item.id }) { continue }
                queue.append(item)
                updateStatus()
                await maybePrepareNext()
                if fallbackMessage == "Could not fetch next video. Retrying..." {
                    fallbackMessage = ""
                }
            } catch {
                if configStore.config.debug {
                    print("[ChannelCoordinator] queue fetch failed: \(error)")
                }
                registerPlaybackFailure("Could not fetch next video. Retrying...", error: error)
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

        do {
            try await prepareHiddenPlayer(with: next)
            nextPreparedId = next.id
        } catch {
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
        currentIsFavorite = candidate.isFavorite
        isPlaybackPaused = false
        currentInfoFields = buildInfoFields(for: candidate)
        title = candidate.title
        captionText = formatCaption(for: candidate)
        clearPlaybackFailureState()
        installTimeObserver()
        updateStatus()
    }

    private func playWithAutoplayFallback(player: AVPlayer) async throws {
        do {
            try await player.playAsync()
        } catch {
            player.isMuted = true
            applyMuteState(true)
            try await player.playAsync()
        }
    }

    private func transitionToNext(reason: String) async {
        guard !transitionInProgress else { return }
        transitionInProgress = true
        defer { transitionInProgress = false }

        if queue.isEmpty {
            await fillQueueIfNeeded()
        }

        guard !queue.isEmpty else {
            registerPlaybackFailure("No eligible videos right now. Retrying...")
            return
        }

        let next = queue.removeFirst()
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
            currentItem = next
            currentIsFavorite = next.isFavorite
            isPlaybackPaused = false
            currentInfoFields = buildInfoFields(for: next)
            title = next.title
            captionText = formatCaption(for: next)
            nextPreparedId = ""
            clearPlaybackFailureState()

            installTimeObserver()
            await fillQueueIfNeeded()
            await maybePrepareNext()

            if configStore.config.debug {
                print("[ChannelCoordinator] transitioned: \(reason) -> \(next.id)")
            }
        } catch {
            registerPlaybackFailure("Transition failed. Skipping...", error: error)
            nextPreparedId = ""
            if configStore.config.debug {
                print("[ChannelCoordinator] transition failed: \(reason) error=\(error)")
            }
        }
    }

    private func activePlayer() -> AVPlayer {
        activeIndex == 0 ? playerA : playerB
    }

    private func hiddenPlayer() -> AVPlayer {
        activeIndex == 0 ? playerB : playerA
    }

    private func updateStatus() {
        let mode = configStore.config.crossfadeEnabled ? "fade \(configStore.config.crossfadeDurationMs)ms" : "cut"
        let syncText = isSyncing ? " · syncing p\(syncPagesFetched) r\(syncRowsUpserted)" : ""
        statusText = "Queue \(queue.count)/\(configStore.config.queueTargetSize) · \(mode)\(syncText)"
    }

    private func applyMuteState(_ muted: Bool) {
        playerA.isMuted = muted
        playerB.isMuted = muted
        objectWillChange.send()
    }

    private func readMutedPreference() -> Bool {
        let key = "ImmichChannelTV.Muted"
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func saveMutedPreference(_ muted: Bool) {
        UserDefaults.standard.set(muted, forKey: "ImmichChannelTV.Muted")
    }

    private func setFavorite(for candidate: VideoCandidate, to isFavorite: Bool) async {
        guard !favoriteUpdateInProgress else { return }

        favoriteUpdateInProgress = true
        let previous = candidate.isFavorite
        applyFavoriteStateLocally(assetId: candidate.id, isFavorite: isFavorite)

        do {
            try await client.updateFavorite(assetId: candidate.id, isFavorite: isFavorite, config: configStore.config)
            try await store.initializeSchema()
            try await store.setFavorite(assetId: candidate.id, isFavorite: isFavorite)
        } catch {
            applyFavoriteStateLocally(assetId: candidate.id, isFavorite: previous)
            fallbackMessage = "Favorite update failed: \(error.localizedDescription)"
            if configStore.config.debug {
                print("[ChannelCoordinator] favorite update failed: \(error)")
            }
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
    }

    private func clearPlaybackFailureState() {
        consecutivePlaybackFailures = 0
        fallbackMessage = ""
    }

    private func registerPlaybackFailure(_ message: String, error: Error? = nil) {
        consecutivePlaybackFailures += 1
        fallbackMessage = message

        if consecutivePlaybackFailures < maxConsecutivePlaybackFailures || shouldOpenSetup {
            return
        }

        let details = error?.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let composedMessage = details.isEmpty ? message : "\(message) (\(details))"
        setupErrorMessage = composedMessage
        syncLastError = composedMessage
        shouldOpenSetup = true
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

    private func formatLocation(city: String, country: String) -> String {
        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = country.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty && !k.isEmpty { return "\(c), \(k)" }
        if !c.isEmpty { return c }
        if !k.isEmpty { return k }
        return ""
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
        var fields: [VideoInfoField] = []

        fields.append(VideoInfoField(id: "title", label: "Title", value: candidate.title))
        fields.append(VideoInfoField(id: "id", label: "Asset ID", value: candidate.id))
        fields.append(VideoInfoField(id: "duration", label: "Duration", value: formatDuration(candidate.duration)))
        fields.append(VideoInfoField(id: "favorite", label: "Favorite", value: candidate.isFavorite ? "Yes" : "No"))

        let dateTime = formatCaptureDateTime(candidate.captureDate)
        if !dateTime.isEmpty {
            fields.append(VideoInfoField(id: "datetime", label: "Date/Time", value: dateTime))
        }

        let location = formatLocation(city: candidate.city, country: candidate.country)
        if !location.isEmpty {
            fields.append(VideoInfoField(id: "location", label: "Location", value: location))
        }

        let camera = [candidate.cameraMake, candidate.cameraModel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !camera.isEmpty {
            fields.append(VideoInfoField(id: "camera", label: "Camera", value: camera))
        }

        if !candidate.lensModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(VideoInfoField(id: "lens", label: "Lens", value: candidate.lensModel))
        }
        if !candidate.fNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(VideoInfoField(id: "fnumber", label: "Aperture", value: candidate.fNumber))
        }
        if !candidate.focalLength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(VideoInfoField(id: "focal", label: "Focal Length", value: candidate.focalLength))
        }
        if !candidate.iso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(VideoInfoField(id: "iso", label: "ISO", value: candidate.iso))
        }
        if !candidate.exposureTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(VideoInfoField(id: "shutter", label: "Exposure", value: candidate.exposureTime))
        }

        let gps = [candidate.latitude, candidate.longitude]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if !gps.isEmpty {
            fields.append(VideoInfoField(id: "gps", label: "GPS", value: gps))
        }

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

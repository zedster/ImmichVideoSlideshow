import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct SetupView: View {
    private enum SettingFocus: Hashable {
        case immichURL
        case apiKey
        case testConnection
        case minDuration
        case randomBatchSize
        case playbackOrder
        case playbackQuality
        case showDateLocationOverlay
        case onlyFavorites
        case resetPlayback
        case crossfadeEnabled
        case crossfadeDuration
        case preloadSeconds
        case queueTarget
        case useSQLiteCache
        case syncOnStartup
        case syncPageSize
        case syncMaxPages
        case forceSync
        case openLibraryStats
        case debugLogging
        case saveAndStart
    }

    @EnvironmentObject private var configStore: ConfigStore
    @Environment(\.dismiss) private var dismiss
    var onForceSync: (() -> Void)? = nil
    var onResetPlaybackProgress: (() -> Void)? = nil
    var onRefreshStats: (() -> Void)? = nil
    var syncIsSyncing: Binding<Bool>? = nil
    var syncPagesFetched: Binding<Int>? = nil
    var syncRowsUpserted: Binding<Int>? = nil
    var syncLastSyncAt: Binding<String>? = nil
    var syncLastError: Binding<String>? = nil
    var statsTotalVideos: Binding<Int>? = nil
    var statsTotalVideoDuration: Binding<Double>? = nil
    var statsTotalWatchedPlays: Binding<Int>? = nil
    var statsTotalWatchedDuration: Binding<Double>? = nil
    var statsWatchedPlays7Days: Binding<Int>? = nil
    var statsWatchedPlays30Days: Binding<Int>? = nil
    var statsVideosWatchedAtLeastOnce: Binding<Int>? = nil
    var statsFavoritesCount: Binding<Int>? = nil
    var statsHiddenCount: Binding<Int>? = nil
    var sessionVideosWatchedCount: Binding<Int>? = nil
    var statsMostPopularCamera: Binding<String>? = nil
    var statsMostPopularCodec: Binding<String>? = nil
    var statsMostPopularFileType: Binding<String>? = nil
    var statsMostPopularPlace: Binding<String>? = nil
    var statsMostPopularYear: Binding<String>? = nil
    var statsTopCamerasSummary: Binding<String>? = nil
    var statsTopCodecsSummary: Binding<String>? = nil
    var statsTopFileTypesSummary: Binding<String>? = nil
    var statsTopPlacesSummary: Binding<String>? = nil
    var statsTopYearsSummary: Binding<String>? = nil
    var statsLastError: Binding<String>? = nil
    var playbackError: Binding<String>? = nil

    @State private var immichURL = ""
    @State private var apiKey = ""
    @State private var minDuration = "10"
    @State private var randomBatchSize = "20"
    @State private var playbackOrder = "random"
    @State private var playbackQuality = "auto"
    @State private var showDateLocationOverlay = true
    @State private var preloadSeconds = "4"
    @State private var crossfadeDuration = "450"
    @State private var queueTarget = "2"
    @State private var syncPageSize = "200"
    @State private var syncMaxPages = "200"

    @State private var onlyFavorites = false
    @State private var debugEnabled = false
    @State private var crossfadeEnabled = true
    @State private var useSQLiteCache = true
    @State private var syncOnStartup = true

    @State private var validationError = ""
    @State private var testMessage = ""
    @State private var testFailed = false
    @State private var testInProgress = false
    @State private var hasLoadedConfig = false
    @FocusState private var focusedSetting: SettingFocus?

    private let bananaSystemsGuideURL = "https://bananasystems.co.uk/home-video-channel/setupqr/"

    private var isOnboarding: Bool {
        configStore.config.immichURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.08, blue: 0.14),
                        Color(red: 0.10, green: 0.18, blue: 0.22),
                        Color(red: 0.20, green: 0.12, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if isOnboarding {
                    onboardingLayout
                } else {
                    settingsLayout
                }
            }
            .navigationTitle(isOnboarding ? "Welcome" : "Settings")
            .onAppear {
                loadFromConfig()
                onRefreshStats?()
                hasLoadedConfig = true
            }
            .onDisappear {
                persistSettingsIfValid()
            }
            .onChange(of: immichURL) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: apiKey) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: minDuration) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: randomBatchSize) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: playbackOrder) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: playbackQuality) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: showDateLocationOverlay) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: preloadSeconds) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: crossfadeDuration) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: queueTarget) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: syncPageSize) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: syncMaxPages) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: onlyFavorites) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: debugEnabled) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: crossfadeEnabled) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: useSQLiteCache) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: syncOnStartup) { _ in autoSaveSettingsIfNeeded() }
        }
    }

    private var onboardingLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Set up your channel")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                    Text("Add your Immich server URL and API key once, then press Go.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.82))
                }

                HStack(alignment: .top, spacing: 24) {
                    card {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Connect")
                                .font(.title2.weight(.semibold))

                            labeledField(
                                "Immich URL",
                                placeholder: "https://immich.example.com",
                                text: $immichURL,
                                disableAutocorrect: true,
                                focus: .immichURL
                            )

                            labeledField(
                                "Immich API key",
                                placeholder: "Paste your API key",
                                text: $apiKey,
                                disableAutocorrect: true,
                                focus: .apiKey
                            )
                            Text("Required permissions: asset.read, asset.view, asset.update, album.read.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))

                            Text("Use the full server address, including https://.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))

                            primaryActionButton("Go", focus: .saveAndStart) {
                                save()
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("How to find your API key")
                                .font(.title2.weight(.semibold))

                            VStack(alignment: .leading, spacing: 10) {
                                guideStep(number: "1", text: "Open Immich in your browser or phone app.")
                                guideStep(number: "2", text: "Go to Account Settings, then API Keys.")
                                guideStep(number: "3", text: "Create a new key and paste it here.")
                            }

                            Divider()
                                .overlay(Color.white.opacity(0.12))

                            HStack(alignment: .top, spacing: 18) {
                                if let image = qrImage(from: bananaSystemsGuideURL) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(uiImage: image)
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 180, height: 180)
                                            .padding(10)
                                            .background(Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 18))
                                        Text("Scan for the Banana Systems guide")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.68))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Need help?")
                                        .font(.headline)
                                    Text("Scan the QR code for the Banana Systems site and follow the setup guide.")
                                        .foregroundStyle(.white.opacity(0.82))
                                    Text(bananaSystemsGuideURL)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                            }
                        }
                    }
                }

                errorSection
            }
            .padding(.horizontal, 58)
            .padding(.vertical, 40)
        }
    }

    private var settingsLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Channel settings")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                        Text("Keep playback simple up front. Advanced controls are grouped below.")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Spacer()

                    if let image = qrImage(from: bananaSystemsGuideURL) {
                        VStack(alignment: .center, spacing: 8) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 132, height: 132)
                                .padding(8)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            Text("Setup help")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeading("Connection")
                        labeledField(
                            "Immich URL",
                            placeholder: "https://immich.example.com",
                            text: $immichURL,
                            disableAutocorrect: true,
                            focus: .immichURL
                        )
                        labeledField(
                            "Immich API key",
                            placeholder: "API key",
                            text: $apiKey,
                            disableAutocorrect: true,
                            focus: .apiKey
                        )
                        Text("Required permissions: asset.read, asset.view, asset.update, album.read.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                        HStack(spacing: 14) {
                            actionButton(
                                testInProgress ? "Testing..." : "Test Connection",
                                focus: .testConnection,
                                disabled: testInProgress
                            ) {
                                testImmichConnection()
                            }
                        }
                        Text("Changes save automatically when values are valid.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                        if !testMessage.isEmpty {
                            Text(testMessage)
                                .foregroundStyle(testFailed ? .red : Color(red: 0.64, green: 0.95, blue: 0.73))
                        }
                    }
                }

                HStack(alignment: .top, spacing: 24) {
                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeading("Playback")
                            labeledField("Minimum Duration (seconds)", placeholder: "10", text: $minDuration, focus: .minDuration)
                            labeledField("Random Batch Size", placeholder: "20", text: $randomBatchSize, focus: .randomBatchSize)
                            choiceRow("Order", value: playbackOrderDisplayValue, focus: .playbackOrder) {
                                cyclePlaybackOrder()
                            }
                            choiceRow("Picture Quality", value: playbackQualityDisplayValue, focus: .playbackQuality) {
                                cyclePlaybackQuality()
                            }
                            booleanPicker("Show Month/Year + Location", isOn: $showDateLocationOverlay, focus: .showDateLocationOverlay)
                            booleanPicker("Only Favorites", isOn: $onlyFavorites, focus: .onlyFavorites)
                            if onResetPlaybackProgress != nil {
                                actionButton("Reset Playback Progress", focus: .resetPlayback) {
                                    onResetPlaybackProgress?()
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeading("Smooth Channel")
                            booleanPicker("Crossfade Enabled", isOn: $crossfadeEnabled, focus: .crossfadeEnabled)
                            labeledField("Crossfade Duration (ms)", placeholder: "450", text: $crossfadeDuration, focus: .crossfadeDuration)
                            labeledField("Preload Seconds Before End", placeholder: "4", text: $preloadSeconds, focus: .preloadSeconds)
                            labeledField("Queue Target Size", placeholder: "2", text: $queueTarget, focus: .queueTarget)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 24) {
                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeading("Local Cache")
                            booleanPicker("Use SQLite Cache", isOn: $useSQLiteCache, focus: .useSQLiteCache)
                            booleanPicker("Sync On Startup", isOn: $syncOnStartup, focus: .syncOnStartup)
                            labeledField("Sync Page Size", placeholder: "200", text: $syncPageSize, focus: .syncPageSize)
                            labeledField("Sync Max Pages", placeholder: "200", text: $syncMaxPages, focus: .syncMaxPages)

                            if syncIsSyncing != nil || syncLastSyncAt != nil {
                                infoPillGroup(values: [
                                    "Syncing: \(syncIsSyncing?.wrappedValue == true ? "yes" : "no")",
                                    "Pages: \(syncPagesFetched?.wrappedValue ?? 0)",
                                    "Rows: \(syncRowsUpserted?.wrappedValue ?? 0)",
                                    "Last Sync: \(syncLastSyncAt?.wrappedValue ?? "-")"
                                ])
                                if let err = syncLastError?.wrappedValue, !err.isEmpty {
                                    Text(err)
                                        .foregroundStyle(.red)
                                }
                            }

                            if onForceSync != nil {
                                actionButton("Force Sync Now", focus: .forceSync, disabled: syncIsSyncing?.wrappedValue == true) {
                                    onForceSync?()
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeading("Tools")
                            NavigationLink {
                                LibraryStatsView(
                                    onRefreshStats: onRefreshStats,
                                    statsTotalVideos: statsTotalVideos,
                                    statsTotalVideoDuration: statsTotalVideoDuration,
                                    statsTotalWatchedPlays: statsTotalWatchedPlays,
                                    statsTotalWatchedDuration: statsTotalWatchedDuration,
                                    statsWatchedPlays7Days: statsWatchedPlays7Days,
                                    statsWatchedPlays30Days: statsWatchedPlays30Days,
                                    statsVideosWatchedAtLeastOnce: statsVideosWatchedAtLeastOnce,
                                    statsFavoritesCount: statsFavoritesCount,
                                    statsHiddenCount: statsHiddenCount,
                                    sessionVideosWatchedCount: sessionVideosWatchedCount,
                                    statsMostPopularCamera: statsMostPopularCamera,
                                    statsMostPopularCodec: statsMostPopularCodec,
                                    statsMostPopularFileType: statsMostPopularFileType,
                                    statsMostPopularPlace: statsMostPopularPlace,
                                    statsMostPopularYear: statsMostPopularYear,
                                    statsTopCamerasSummary: statsTopCamerasSummary,
                                    statsTopCodecsSummary: statsTopCodecsSummary,
                                    statsTopFileTypesSummary: statsTopFileTypesSummary,
                                    statsTopPlacesSummary: statsTopPlacesSummary,
                                    statsTopYearsSummary: statsTopYearsSummary,
                                    statsLastError: statsLastError
                                )
                            } label: {
                                settingRowLabel("Open Library Stats", value: "View", isFocused: focusedSetting == .openLibraryStats)
                            }
                            .buttonStyle(.plain)
                            .focused($focusedSetting, equals: .openLibraryStats)

                            booleanPicker("Debug Logging", isOn: $debugEnabled, focus: .debugLogging)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("About")
                                    .font(.headline)
                                aboutRow("Maintained By", value: "bananasystems.co.uk")
                                Link("zedster/ImmichVideoSlideshow", destination: URL(string: "https://github.com/zedster/ImmichVideoSlideshow")!)
                                    .font(.caption)
                                aboutRow("Build", value: buildNumber)
                            }
                            .padding(.top, 8)
                        }
                    }
                }

                errorSection
            }
            .padding(.horizontal, 58)
            .padding(.vertical, 34)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if !validationError.isEmpty || (playbackError?.wrappedValue.isEmpty == false) {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    if !validationError.isEmpty {
                        Text(validationError)
                            .foregroundStyle(.red)
                    }
                    if let playbackError, !playbackError.wrappedValue.isEmpty {
                        Text(playbackError.wrappedValue)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func loadFromConfig() {
        let cfg = configStore.config
        immichURL = cfg.immichURL
        apiKey = cfg.apiKey
        minDuration = String(Int(cfg.minDuration))
        randomBatchSize = String(cfg.randomBatchSize)
        switch cfg.playbackOrder {
        case "sequential_oldest", "sequential":
            playbackOrder = "sequential_oldest"
        case "sequential_newest":
            playbackOrder = "sequential_newest"
        default:
            playbackOrder = "random"
        }
        playbackQuality = cfg.playbackQuality
        showDateLocationOverlay = cfg.showDateLocationOverlay
        preloadSeconds = String(cfg.preloadSecondsBeforeEnd)
        crossfadeDuration = String(cfg.crossfadeDurationMs)
        queueTarget = String(cfg.queueTargetSize)
        syncPageSize = String(cfg.syncPageSize)
        syncMaxPages = String(cfg.syncMaxPages)
        onlyFavorites = cfg.onlyFavorites
        debugEnabled = cfg.debug
        crossfadeEnabled = cfg.crossfadeEnabled
        useSQLiteCache = cfg.useSQLiteCache
        syncOnStartup = cfg.syncOnStartup
        testMessage = ""
        testFailed = false
        validationError = ""
    }

    private func save() {
        guard let next = buildConfig(requireCredentials: true, preserveExistingOnMissingCredentials: false) else {
            return
        }
        validationError = ""
        playbackError?.wrappedValue = ""
        configStore.save(next)
        dismiss()
    }

    private func buildConfig(requireCredentials: Bool, preserveExistingOnMissingCredentials: Bool) -> AppConfig? {
        let trimmedURL = immichURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if requireCredentials && (trimmedURL.isEmpty || trimmedKey.isEmpty) {
            validationError = "Immich URL and API key are required."
            return nil
        }

        guard let minDurationValue = Double(minDuration), minDurationValue >= 0,
              let randomBatchValue = Int(randomBatchSize), randomBatchValue > 0,
              let preloadValue = Double(preloadSeconds), preloadValue > 0,
              let fadeValue = Int(crossfadeDuration), fadeValue >= 0,
              let queueValue = Int(queueTarget), queueValue > 0,
              let syncPageValue = Int(syncPageSize), syncPageValue > 0,
              let syncMaxValue = Int(syncMaxPages), syncMaxValue > 0 else {
            validationError = "Please enter valid numeric values."
            return nil
        }

        var next = configStore.config
        if !trimmedURL.isEmpty {
            next.immichURL = trimmedURL
        } else if !preserveExistingOnMissingCredentials {
            next.immichURL = trimmedURL
        }
        if !trimmedKey.isEmpty {
            next.apiKey = trimmedKey
        } else if !preserveExistingOnMissingCredentials {
            next.apiKey = trimmedKey
        }
        next.minDuration = minDurationValue
        next.randomBatchSize = randomBatchValue
        switch playbackOrder {
        case "sequential_oldest", "sequential_newest", "random":
            next.playbackOrder = playbackOrder
        default:
            next.playbackOrder = "random"
        }
        next.playbackQuality = playbackQuality
        next.showDateLocationOverlay = showDateLocationOverlay
        next.onlyFavorites = onlyFavorites
        if onlyFavorites {
            next.onlyThisMonth = false
            next.onlyThisDay = false
            next.onlyThisWeek = false
            next.referenceCaptureDate = ""
            next.placeFilterCity = ""
            next.placeFilterCountry = ""
        }
        next.debug = debugEnabled
        next.crossfadeEnabled = crossfadeEnabled
        next.crossfadeDurationMs = fadeValue
        next.preloadSecondsBeforeEnd = preloadValue
        next.queueTargetSize = min(queueValue, 5)
        next.useSQLiteCache = useSQLiteCache
        next.syncOnStartup = syncOnStartup
        next.syncPageSize = min(syncPageValue, 1000)
        next.syncMaxPages = syncMaxValue

        return next
    }

    private func persistSettingsIfValid() {
        guard !isOnboarding else { return }
        guard let next = buildConfig(requireCredentials: false, preserveExistingOnMissingCredentials: true) else {
            return
        }
        validationError = ""
        playbackError?.wrappedValue = ""
        configStore.save(next)
    }

    private func autoSaveSettingsIfNeeded() {
        guard hasLoadedConfig, !isOnboarding else { return }
        persistSettingsIfValid()
    }

    private func testImmichConnection() {
        let trimmedURL = immichURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            testFailed = true
            testMessage = "Enter your server URL and API key first."
            return
        }

        testInProgress = true
        testMessage = ""
        testFailed = false

        Task {
            var testConfig = AppConfig()
            testConfig.immichURL = trimmedURL
            testConfig.apiKey = trimmedKey

            let client = ImmichAPIClient()
            do {
                _ = try await client.fetchRandomBatch(config: testConfig, size: 1)
                await MainActor.run {
                    persistImmichCredentialsFromInputs()
                    testFailed = false
                    testMessage = "Connection successful. Server URL and API key saved."
                }
            } catch {
                await MainActor.run {
                    testFailed = true
                    testMessage = "Connection failed: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                testInProgress = false
            }
        }
    }

    private func persistImmichCredentialsFromInputs() {
        let trimmedURL = immichURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else { return }

        var next = configStore.config
        next.immichURL = trimmedURL
        next.apiKey = trimmedKey
        configStore.save(next)
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private func guideStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline.weight(.bold))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.14))
                .clipShape(Circle())
            Text(text)
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    @ViewBuilder
    private func infoPillGroup(values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func labeledField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        disableAutocorrect: Bool = false,
        focus: SettingFocus
    ) -> some View {
        let isFocused = focusedSetting == focus
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.74))
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(disableAutocorrect)
                .foregroundStyle(isFocused ? .black : .white)
                .focused($focusedSetting, equals: focus)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.12))
                )
        }
    }

    @ViewBuilder
    private func booleanPicker(_ label: String, isOn: Binding<Bool>, focus: SettingFocus) -> some View {
        let isFocused = focusedSetting == focus
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            settingRowLabel(label, value: isOn.wrappedValue ? "On" : "Off", isFocused: isFocused)
        }
        .buttonStyle(.plain)
        .focused($focusedSetting, equals: focus)
    }

    @ViewBuilder
    private func choiceRow(_ label: String, value: String, focus: SettingFocus, action: @escaping () -> Void) -> some View {
        let isFocused = focusedSetting == focus
        Button(action: action) {
            settingRowLabel(label, value: value, isFocused: isFocused)
        }
        .buttonStyle(.plain)
        .focused($focusedSetting, equals: focus)
    }

    @ViewBuilder
    private func primaryActionButton(_ title: String, focus: SettingFocus, action: @escaping () -> Void) -> some View {
        let isFocused = focusedSetting == focus
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isFocused ? Color(red: 0.64, green: 0.18, blue: 0.14) : .white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFocused ? Color.white : Color(red: 0.84, green: 0.28, blue: 0.20))
            )
        }
        .buttonStyle(.plain)
        .focused($focusedSetting, equals: focus)
    }

    @ViewBuilder
    private func actionButton(_ title: String, focus: SettingFocus, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        let isFocused = focusedSetting == focus
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(isFocused ? .black : .white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.10))
            )
            .opacity(disabled ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .focused($focusedSetting, equals: focus)
    }

    @ViewBuilder
    private func settingRowLabel(_ label: String, value: String, isFocused: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(isFocused ? .black : .white)
            Spacer()
            Text(value)
                .foregroundStyle(isFocused ? .black : .white.opacity(0.78))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFocused ? Color.white : Color.white.opacity(0.10))
        )
    }

    @ViewBuilder
    private func aboutRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
        }
    }

    private var buildNumber: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private var playbackOrderDisplayValue: String {
        switch playbackOrder {
        case "sequential_oldest":
            return "Sequential Oldest -> Newest"
        case "sequential_newest":
            return "Sequential Newest -> Oldest"
        default:
            return "Random"
        }
    }

    private var playbackQualityDisplayValue: String {
        switch playbackQuality {
        case "high":
            return "High"
        case "medium":
            return "Medium"
        case "low":
            return "Low"
        default:
            return "Auto"
        }
    }

    private func cyclePlaybackOrder() {
        switch playbackOrder {
        case "random":
            playbackOrder = "sequential_oldest"
        case "sequential_oldest":
            playbackOrder = "sequential_newest"
        default:
            playbackOrder = "random"
        }
    }

    private func cyclePlaybackQuality() {
        switch playbackQuality {
        case "auto":
            playbackQuality = "high"
        case "high":
            playbackQuality = "medium"
        case "medium":
            playbackQuality = "low"
        default:
            playbackQuality = "auto"
        }
    }

    private func qrImage(from value: String) -> UIImage? {
        guard !value.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct LibraryStatsView: View {
    private enum SectionID: Hashable {
        case totals
        case activity
        case libraryState
        case popular
        case topCameras
        case topCodecs
        case topFileTypes
        case topPlaces
        case topYears
        case error
    }

    var onRefreshStats: (() -> Void)? = nil
    var statsTotalVideos: Binding<Int>? = nil
    var statsTotalVideoDuration: Binding<Double>? = nil
    var statsTotalWatchedPlays: Binding<Int>? = nil
    var statsTotalWatchedDuration: Binding<Double>? = nil
    var statsWatchedPlays7Days: Binding<Int>? = nil
    var statsWatchedPlays30Days: Binding<Int>? = nil
    var statsVideosWatchedAtLeastOnce: Binding<Int>? = nil
    var statsFavoritesCount: Binding<Int>? = nil
    var statsHiddenCount: Binding<Int>? = nil
    var sessionVideosWatchedCount: Binding<Int>? = nil
    var statsMostPopularCamera: Binding<String>? = nil
    var statsMostPopularCodec: Binding<String>? = nil
    var statsMostPopularFileType: Binding<String>? = nil
    var statsMostPopularPlace: Binding<String>? = nil
    var statsMostPopularYear: Binding<String>? = nil
    var statsTopCamerasSummary: Binding<String>? = nil
    var statsTopCodecsSummary: Binding<String>? = nil
    var statsTopFileTypesSummary: Binding<String>? = nil
    var statsTopPlacesSummary: Binding<String>? = nil
    var statsTopYearsSummary: Binding<String>? = nil
    var statsLastError: Binding<String>? = nil
    @FocusState private var focusedSection: SectionID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Library Stats")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text("Stats are calculated from the local SQLite cache.")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(.top, 10)

                    focusSection(.totals, title: "Totals") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            summaryTile(
                                "Total Videos",
                                value: "\(statsTotalVideos?.wrappedValue ?? 0)",
                                detail: formattedDuration(statsTotalVideoDuration?.wrappedValue ?? 0)
                            )
                            summaryTile(
                                "Total Watched Plays",
                                value: "\(statsTotalWatchedPlays?.wrappedValue ?? 0)",
                                detail: formattedDuration(statsTotalWatchedDuration?.wrappedValue ?? 0)
                            )
                        }
                    }

                    focusSection(.activity, title: "Viewing Activity") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            summaryTile("Watched In 7 Days", value: "\(statsWatchedPlays7Days?.wrappedValue ?? 0)")
                            summaryTile("Watched In 30 Days", value: "\(statsWatchedPlays30Days?.wrappedValue ?? 0)")
                            summaryTile("Watched At Least Once", value: "\(statsVideosWatchedAtLeastOnce?.wrappedValue ?? 0)")
                            summaryTile("Current Session", value: "\(sessionVideosWatchedCount?.wrappedValue ?? 0)")
                        }
                    }

                    focusSection(.libraryState, title: "Library State") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            summaryTile("Favorites", value: "\(statsFavoritesCount?.wrappedValue ?? 0)")
                            summaryTile("Hidden", value: "\(statsHiddenCount?.wrappedValue ?? 0)")
                        }
                    }

                    focusSection(.popular, title: "Most Popular") {
                        detailRow("Camera", value: statsMostPopularCamera?.wrappedValue ?? "-")
                        detailRow("Codec", value: statsMostPopularCodec?.wrappedValue ?? "-")
                        detailRow("File Type", value: statsMostPopularFileType?.wrappedValue ?? "-")
                        detailRow("Place", value: statsMostPopularPlace?.wrappedValue ?? "-")
                        detailRow("Year", value: statsMostPopularYear?.wrappedValue ?? "-")
                    }

                    focusSection(.topCameras, title: "Top Cameras") {
                        rankedList(value: statsTopCamerasSummary?.wrappedValue ?? "-")
                    }

                    focusSection(.topCodecs, title: "Top Codecs") {
                        rankedList(value: statsTopCodecsSummary?.wrappedValue ?? "-")
                    }

                    focusSection(.topFileTypes, title: "Top File Types") {
                        rankedList(value: statsTopFileTypesSummary?.wrappedValue ?? "-")
                    }

                    focusSection(.topPlaces, title: "Top Places") {
                        rankedList(value: statsTopPlacesSummary?.wrappedValue ?? "-")
                    }

                    focusSection(.topYears, title: "Top Years") {
                        rankedList(value: statsTopYearsSummary?.wrappedValue ?? "-")
                    }

                    if let err = statsLastError?.wrappedValue, !err.isEmpty {
                        focusSection(.error, title: "Error", tint: Color.red.opacity(0.14)) {
                            Text("Stats Error: \(err)")
                                .font(.title3)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 56)
                .padding(.vertical, 36)
            }
            .onAppear {
                onRefreshStats?()
                focusedSection = .totals
            }
            .onChange(of: focusedSection) { target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .navigationTitle("Library Stats")
    }

    @ViewBuilder
    private func summaryTile(_ label: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder
    private func focusSection<Content: View>(_ id: SectionID, title: String, tint: Color = Color.white.opacity(0.08), @ViewBuilder content: () -> Content) -> some View {
        let isFocused = focusedSection == id

        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            content()
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(isFocused ? Color.white.opacity(0.16) : tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.08), lineWidth: isFocused ? 4 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isFocused ? 0.28 : 0.12), radius: isFocused ? 18 : 8, y: 10)
        .animation(.easeInOut(duration: 0.18), value: isFocused)
        .focusable(true)
        .focused($focusedSection, equals: id)
        .id(id)
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 20)
            Text(value)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func rankedList(value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let rows = expandedRows(from: value)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(index + 1).")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                    Text(row)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func expandedRows(from value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-" else { return ["No data"] }

        let pattern = #".+? \(\d+\)(?:,|$)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
            let matches = regex.matches(in: trimmed, range: nsRange)
            let rows = matches.compactMap { match -> String? in
                guard let range = Range(match.range, in: trimmed) else { return nil }
                return trimmed[range]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            }
            if !rows.isEmpty {
                return rows
            }
        }

        return trimmed
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func formattedDuration(_ totalSeconds: Double) -> String {
        let seconds = max(0, Int(totalSeconds.rounded()))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

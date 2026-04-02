import SwiftUI

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
        case showPeopleOverlay
        case includeDiagnosticsInFeedback
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
        case sendFeedback
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
    @State private var showPeopleOverlay = true
    @State private var includeDiagnosticsInFeedback = true
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
            .navigationTitle(isOnboarding
                ? L10n.tr("settings.onboarding.title", "Welcome", comment: "Onboarding navigation title")
                : L10n.tr("settings.title", "Settings", comment: "Settings navigation title")
            )
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
            .onChange(of: showPeopleOverlay) { _ in autoSaveSettingsIfNeeded() }
            .onChange(of: includeDiagnosticsInFeedback) { _ in autoSaveSettingsIfNeeded() }
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
                    Text(L10n.tr("settings.onboarding.heading", "Set up your channel", comment: "Onboarding heading"))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                    Text(L10n.tr(
                        "settings.onboarding.subtitle",
                        "Add your Immich server URL and API key once, then press Go.",
                        comment: "Onboarding subtitle"
                    ))
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.82))
                }

                HStack(alignment: .top, spacing: 24) {
                    card {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(L10n.tr("settings.onboarding.connect.section", "Connect", comment: "Onboarding connection card title"))
                                .font(.title2.weight(.semibold))

                            labeledField(
                                L10n.tr("settings.connection.immich_url", "Immich URL", comment: "Immich URL field label"),
                                placeholder: L10n.tr(
                                    "settings.connection.immich_url.placeholder",
                                    "https://immich.example.com",
                                    comment: "Immich URL field placeholder"
                                ),
                                text: $immichURL,
                                disableAutocorrect: true,
                                focus: .immichURL
                            )

                            labeledField(
                                L10n.tr("settings.connection.api_key", "Immich API key", comment: "Immich API key field label"),
                                placeholder: L10n.tr("settings.connection.api_key.placeholder", "Paste your API key", comment: "Immich API key field placeholder"),
                                text: $apiKey,
                                disableAutocorrect: true,
                                focus: .apiKey
                            )
                            Text(L10n.tr(
                                "settings.connection.permissions",
                                "Required permissions: asset.read, asset.view, asset.update, album.read.",
                                comment: "Required API key permissions for Immich"
                            ))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))

                            Text(L10n.tr(
                                "settings.connection.url_hint",
                                "Use the full server address, including https://.",
                                comment: "Immich URL hint"
                            ))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))

                            primaryActionButton(L10n.tr("settings.onboarding.go", "Go", comment: "Onboarding primary action"), focus: .saveAndStart) {
                                save()
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(L10n.tr("settings.onboarding.api_key_help.title", "How to find your API key", comment: "API key help section title"))
                                .font(.title2.weight(.semibold))

                            VStack(alignment: .leading, spacing: 10) {
                                guideStep(number: "1", text: L10n.tr("settings.onboarding.api_key_help.step1", "Open Immich in your browser or phone app.", comment: "API key help step 1"))
                                guideStep(number: "2", text: L10n.tr("settings.onboarding.api_key_help.step2", "Go to Account Settings, then API Keys.", comment: "API key help step 2"))
                                guideStep(number: "3", text: L10n.tr("settings.onboarding.api_key_help.step3", "Create a new key and paste it here.", comment: "API key help step 3"))
                            }

                            Divider()
                                .overlay(Color.white.opacity(0.12))

                            HStack(alignment: .top, spacing: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    QRCodeView(value: bananaSystemsGuideURL, size: 180)
                                    Text(L10n.tr("settings.onboarding.scan_guide", "Scan for the Banana Systems guide", comment: "Caption below setup QR code"))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.68))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.tr("settings.onboarding.need_help", "Need help?", comment: "Onboarding helper heading"))
                                        .font(.headline)
                                    Text(L10n.tr(
                                        "settings.onboarding.need_help.description",
                                        "Scan the QR code for the Banana Systems site and follow the setup guide.",
                                        comment: "Onboarding help description"
                                    ))
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
                        Text(L10n.tr("settings.channel.heading", "Channel settings", comment: "Settings hero heading"))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                        Text(L10n.tr(
                            "settings.channel.subtitle",
                            "Keep playback simple up front. Advanced controls are grouped below.",
                            comment: "Settings hero subtitle"
                        ))
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 8) {
                        QRCodeView(value: bananaSystemsGuideURL, size: 132)
                        Text(L10n.tr("settings.setup_help", "Setup help", comment: "Setup QR helper label"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeading(L10n.tr("settings.connection.section", "Connection", comment: "Connection section title"))
                        labeledField(
                            L10n.tr("settings.connection.immich_url", "Immich URL", comment: "Immich URL field label"),
                            placeholder: L10n.tr("settings.connection.immich_url.placeholder", "https://immich.example.com", comment: "Immich URL field placeholder"),
                            text: $immichURL,
                            disableAutocorrect: true,
                            focus: .immichURL
                        )
                        labeledField(
                            L10n.tr("settings.connection.api_key", "Immich API key", comment: "Immich API key field label"),
                            placeholder: L10n.tr("settings.connection.api_key.short_placeholder", "API key", comment: "Immich API key field placeholder"),
                            text: $apiKey,
                            disableAutocorrect: true,
                            focus: .apiKey
                        )
                        Text(L10n.tr("settings.connection.permissions", "Required permissions: asset.read, asset.view, asset.update, album.read.", comment: "Required API key permissions for Immich"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                        HStack(spacing: 14) {
                            actionButton(
                                testInProgress
                                    ? L10n.tr("settings.connection.testing", "Testing...", comment: "Connection test button while loading")
                                    : L10n.tr("settings.connection.test", "Test Connection", comment: "Connection test button"),
                                focus: .testConnection,
                                disabled: testInProgress
                            ) {
                                testImmichConnection()
                            }
                        }
                        Text(L10n.tr("settings.autosave_hint", "Changes save automatically when values are valid.", comment: "Settings auto-save helper text"))
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
                            sectionHeading(L10n.tr("playback.section", "Playback", comment: "Playback settings section title"))
                            labeledField(L10n.tr("playback.minimum_duration", "Minimum Duration (seconds)", comment: "Playback setting label"), placeholder: "10", text: $minDuration, focus: .minDuration)
                            labeledField(L10n.tr("playback.random_batch_size", "Random Batch Size", comment: "Playback setting label"), placeholder: "20", text: $randomBatchSize, focus: .randomBatchSize)
                            choiceRow(L10n.tr("playback.order", "Order", comment: "Playback setting label"), value: playbackOrderDisplayValue, focus: .playbackOrder) {
                                cyclePlaybackOrder()
                            }
                            choiceRow(L10n.tr("playback.picture_quality", "Picture Quality", comment: "Playback setting label"), value: playbackQualityDisplayValue, focus: .playbackQuality) {
                                cyclePlaybackQuality()
                            }
                            booleanPicker(L10n.tr("playback.overlay_date_location", "Show Month/Year + Location", comment: "Playback setting label"), isOn: $showDateLocationOverlay, focus: .showDateLocationOverlay)
                            booleanPicker(L10n.tr("playback.overlay_people", "Show People In Overlay", comment: "Playback setting label"), isOn: $showPeopleOverlay, focus: .showPeopleOverlay)
                            booleanPicker(L10n.tr("playback.only_favorites", "Only Favorites", comment: "Playback setting label"), isOn: $onlyFavorites, focus: .onlyFavorites)
                            if onResetPlaybackProgress != nil {
                                actionButton(L10n.tr("playback.reset_progress", "Reset Playback Progress", comment: "Reset playback progress action"), focus: .resetPlayback) {
                                    onResetPlaybackProgress?()
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeading(L10n.tr("playback.smooth_channel.section", "Smooth Channel", comment: "Smooth playback section title"))
                            booleanPicker(L10n.tr("playback.crossfade_enabled", "Crossfade Enabled", comment: "Playback setting label"), isOn: $crossfadeEnabled, focus: .crossfadeEnabled)
                            labeledField(L10n.tr("playback.crossfade_duration_ms", "Crossfade Duration (ms)", comment: "Playback setting label"), placeholder: "450", text: $crossfadeDuration, focus: .crossfadeDuration)
                            labeledField(L10n.tr("playback.preload_seconds", "Preload Seconds Before End", comment: "Playback setting label"), placeholder: "4", text: $preloadSeconds, focus: .preloadSeconds)
                            labeledField(L10n.tr("playback.queue_target", "Queue Target Size", comment: "Playback setting label"), placeholder: "2", text: $queueTarget, focus: .queueTarget)
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeading(L10n.tr("feedback.section", "Feedback", comment: "Feedback section title"))

                        Text(L10n.tr(
                            "feedback.section.description",
                            "We love making this app better for our users. If you have suggestions, bug reports, or feature ideas, we want to hear them.",
                            comment: "Feedback section description"
                        ))
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)

                        NavigationLink {
                            FeedbackView(config: configStore.config)
                        } label: {
                            detailedSettingRowLabel(
                                L10n.tr("feedback.title", "Send Feedback", comment: "Feedback screen title"),
                                subtitle: L10n.tr("feedback.open.subtitle", "Scan a QR code to report a bug or request a feature", comment: "Feedback row subtitle"),
                                value: L10n.tr("common.open", "Open", comment: "Generic open action"),
                                isFocused: focusedSetting == .sendFeedback
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedSetting, equals: .sendFeedback)

                        booleanPicker(L10n.tr("feedback.include_diagnostics", "Include Diagnostics In Feedback", comment: "Feedback setting toggle"), isOn: $includeDiagnosticsInFeedback, focus: .includeDiagnosticsInFeedback)
                    }
                }

                HStack(alignment: .top, spacing: 24) {
                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeading(L10n.tr("library.cache.section", "Local Cache", comment: "Local cache section title"))
                            booleanPicker(L10n.tr("library.cache.use_sqlite", "Use SQLite Cache", comment: "Cache setting label"), isOn: $useSQLiteCache, focus: .useSQLiteCache)
                            booleanPicker(L10n.tr("library.cache.sync_on_startup", "Sync On Startup", comment: "Cache setting label"), isOn: $syncOnStartup, focus: .syncOnStartup)
                            labeledField(L10n.tr("library.cache.sync_page_size", "Sync Page Size", comment: "Cache setting label"), placeholder: "200", text: $syncPageSize, focus: .syncPageSize)
                            labeledField(L10n.tr("library.cache.sync_max_pages", "Sync Max Pages", comment: "Cache setting label"), placeholder: "200", text: $syncMaxPages, focus: .syncMaxPages)

                            if syncIsSyncing != nil || syncLastSyncAt != nil {
                                infoPillGroup(values: [
                                    String(format: L10n.tr("library.cache.syncing.value", "Syncing: %@", comment: "Current sync active state"), syncIsSyncing?.wrappedValue == true ? L10n.tr("common.yes", "yes", comment: "Yes value") : L10n.tr("common.no", "no", comment: "No value")),
                                    String(format: L10n.tr("library.cache.pages.value", "Pages: %@", comment: "Sync pages value"), (syncPagesFetched?.wrappedValue ?? 0).formatted()),
                                    String(format: L10n.tr("library.cache.rows.value", "Rows: %@", comment: "Sync rows value"), (syncRowsUpserted?.wrappedValue ?? 0).formatted()),
                                    String(format: L10n.tr("library.cache.last_sync.value", "Last Sync: %@", comment: "Last sync timestamp value"), syncLastSyncAt?.wrappedValue ?? L10n.unknownDash)
                                ])
                                if let err = syncLastError?.wrappedValue, !err.isEmpty {
                                    Text(err)
                                        .foregroundStyle(.red)
                                }
                            }

                            if onForceSync != nil {
                                actionButton(L10n.tr("library.cache.force_sync_now", "Force Sync Now", comment: "Force sync action"), focus: .forceSync, disabled: syncIsSyncing?.wrappedValue == true) {
                                    onForceSync?()
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeading(L10n.tr("settings.tools.section", "Tools", comment: "Tools section title"))
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
                                settingRowLabel(
                                    L10n.tr("library.stats.open", "Open Library Stats", comment: "Open library stats action"),
                                    value: L10n.tr("common.view", "View", comment: "Generic view action"),
                                    isFocused: focusedSetting == .openLibraryStats
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedSetting, equals: .openLibraryStats)

                            booleanPicker(L10n.tr("settings.debug_logging", "Debug Logging", comment: "Debug logging toggle"), isOn: $debugEnabled, focus: .debugLogging)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.tr("about.section", "About", comment: "About section title"))
                                    .font(.headline)
                                aboutRow(L10n.tr("about.maintained_by", "Maintained By", comment: "About row label"), value: "bananasystems.co.uk")
                                Link("zedster/ImmichVideoSlideshow", destination: URL(string: "https://github.com/zedster/ImmichVideoSlideshow")!)
                                    .font(.caption)
                                aboutRow(L10n.tr("about.build", "Build", comment: "Build label in about section"), value: buildNumber)
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
        showPeopleOverlay = cfg.showPeopleOverlay
        includeDiagnosticsInFeedback = cfg.includeDiagnosticsInFeedback
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
            validationError = L10n.tr(
                "errors.settings.missing_url_or_key",
                "Immich URL and API key are required.",
                comment: "Validation error when connection details are missing"
            )
            return nil
        }

        guard let minDurationValue = Double(minDuration), minDurationValue >= 0,
              let randomBatchValue = Int(randomBatchSize), randomBatchValue > 0,
              let preloadValue = Double(preloadSeconds), preloadValue > 0,
              let fadeValue = Int(crossfadeDuration), fadeValue >= 0,
              let queueValue = Int(queueTarget), queueValue > 0,
              let syncPageValue = Int(syncPageSize), syncPageValue > 0,
              let syncMaxValue = Int(syncMaxPages), syncMaxValue > 0 else {
            validationError = L10n.tr(
                "errors.settings.invalid_numeric_values",
                "Please enter valid numeric values.",
                comment: "Validation error when numeric settings are invalid"
            )
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
        next.showPeopleOverlay = showPeopleOverlay
        next.includeDiagnosticsInFeedback = includeDiagnosticsInFeedback
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
            testMessage = L10n.tr(
                "errors.connection.enter_url_and_key_first",
                "Enter your server URL and API key first.",
                comment: "Message shown before testing connection without required fields"
            )
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
                    testMessage = L10n.tr(
                        "settings.connection.test.success",
                        "Connection successful. Server URL and API key saved.",
                        comment: "Message shown when test connection succeeds"
                    )
                }
            } catch {
                await MainActor.run {
                    testFailed = true
                    testMessage = String(format: L10n.tr(
                        "errors.connection.test_failed_with_reason",
                        "Connection failed: %@",
                        comment: "Connection test failure message with reason"
                    ), error.localizedDescription)
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
            settingRowLabel(label, value: L10n.onOff(isOn.wrappedValue), isFocused: isFocused)
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
    private func detailedSettingRowLabel(_ label: String, subtitle: String, value: String, isFocused: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .foregroundStyle(isFocused ? .black : .white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isFocused ? Color.black.opacity(0.68) : Color.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Text(value)
                .foregroundStyle(isFocused ? .black : .white.opacity(0.78))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        return trimmed.isEmpty ? L10n.unknownDash : trimmed
    }

    private var playbackOrderDisplayValue: String {
        switch playbackOrder {
        case "sequential_oldest":
            return L10n.tr("playback.order.sequential_oldest", "Sequential Oldest -> Newest", comment: "Playback order value")
        case "sequential_newest":
            return L10n.tr("playback.order.sequential_newest", "Sequential Newest -> Oldest", comment: "Playback order value")
        default:
            return L10n.tr("playback.order.random", "Random", comment: "Playback order value")
        }
    }

    private var playbackQualityDisplayValue: String {
        switch playbackQuality {
        case "high":
            return L10n.tr("playback.quality.high", "High", comment: "Playback quality value")
        case "medium":
            return L10n.tr("playback.quality.medium", "Medium", comment: "Playback quality value")
        case "low":
            return L10n.tr("playback.quality.low", "Low", comment: "Playback quality value")
        default:
            return L10n.tr("playback.quality.auto", "Auto", comment: "Playback quality value")
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
                        Text(L10n.tr("library.stats.title", "Library Stats", comment: "Library stats screen title"))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text(L10n.tr(
                            "library.stats.subtitle",
                            "Stats are calculated from the local SQLite cache.",
                            comment: "Library stats subtitle"
                        ))
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(.top, 10)

                    focusSection(.totals, title: L10n.tr("library.stats.section.totals", "Totals", comment: "Library stats section title")) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            summaryTile(
                                L10n.tr("library.stats.total_videos", "Total Videos", comment: "Library stats metric label"),
                                value: "\(statsTotalVideos?.wrappedValue ?? 0)",
                                detail: formattedDuration(statsTotalVideoDuration?.wrappedValue ?? 0)
                            )
                            summaryTile(
                                L10n.tr("library.stats.total_watched_plays", "Total Watched Plays", comment: "Library stats metric label"),
                                value: "\(statsTotalWatchedPlays?.wrappedValue ?? 0)",
                                detail: formattedDuration(statsTotalWatchedDuration?.wrappedValue ?? 0)
                            )
                        }
                    }

                    focusSection(.activity, title: L10n.tr("library.stats.section.activity", "Viewing Activity", comment: "Library stats section title")) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            summaryTile(L10n.tr("library.stats.watched_7_days", "Watched In 7 Days", comment: "Library stats metric label"), value: "\(statsWatchedPlays7Days?.wrappedValue ?? 0)")
                            summaryTile(L10n.tr("library.stats.watched_30_days", "Watched In 30 Days", comment: "Library stats metric label"), value: "\(statsWatchedPlays30Days?.wrappedValue ?? 0)")
                            summaryTile(L10n.tr("library.stats.watched_at_least_once", "Watched At Least Once", comment: "Library stats metric label"), value: "\(statsVideosWatchedAtLeastOnce?.wrappedValue ?? 0)")
                            summaryTile(L10n.tr("library.stats.current_session", "Current Session", comment: "Library stats metric label"), value: "\(sessionVideosWatchedCount?.wrappedValue ?? 0)")
                        }
                    }

                    focusSection(.libraryState, title: L10n.tr("library.stats.section.library_state", "Library State", comment: "Library stats section title")) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            summaryTile(L10n.tr("library.stats.favorites", "Favorites", comment: "Library stats metric label"), value: "\(statsFavoritesCount?.wrappedValue ?? 0)")
                            summaryTile(L10n.tr("library.stats.hidden", "Hidden", comment: "Library stats metric label"), value: "\(statsHiddenCount?.wrappedValue ?? 0)")
                        }
                    }

                    focusSection(.popular, title: L10n.tr("library.stats.section.most_popular", "Most Popular", comment: "Library stats section title")) {
                        detailRow(L10n.tr("library.stats.camera", "Camera", comment: "Library stats field label"), value: statsMostPopularCamera?.wrappedValue ?? L10n.unknownDash)
                        detailRow(L10n.tr("library.stats.codec", "Codec", comment: "Library stats field label"), value: statsMostPopularCodec?.wrappedValue ?? L10n.unknownDash)
                        detailRow(L10n.tr("library.stats.file_type", "File Type", comment: "Library stats field label"), value: statsMostPopularFileType?.wrappedValue ?? L10n.unknownDash)
                        detailRow(L10n.tr("library.stats.place", "Place", comment: "Library stats field label"), value: statsMostPopularPlace?.wrappedValue ?? L10n.unknownDash)
                        detailRow(L10n.tr("library.stats.year", "Year", comment: "Library stats field label"), value: statsMostPopularYear?.wrappedValue ?? L10n.unknownDash)
                    }

                    focusSection(.topCameras, title: L10n.tr("library.stats.section.top_cameras", "Top Cameras", comment: "Library stats section title")) {
                        rankedList(value: statsTopCamerasSummary?.wrappedValue ?? L10n.unknownDash)
                    }

                    focusSection(.topCodecs, title: L10n.tr("library.stats.section.top_codecs", "Top Codecs", comment: "Library stats section title")) {
                        rankedList(value: statsTopCodecsSummary?.wrappedValue ?? L10n.unknownDash)
                    }

                    focusSection(.topFileTypes, title: L10n.tr("library.stats.section.top_file_types", "Top File Types", comment: "Library stats section title")) {
                        rankedList(value: statsTopFileTypesSummary?.wrappedValue ?? L10n.unknownDash)
                    }

                    focusSection(.topPlaces, title: L10n.tr("library.stats.section.top_places", "Top Places", comment: "Library stats section title")) {
                        rankedList(value: statsTopPlacesSummary?.wrappedValue ?? L10n.unknownDash)
                    }

                    focusSection(.topYears, title: L10n.tr("library.stats.section.top_years", "Top Years", comment: "Library stats section title")) {
                        rankedList(value: statsTopYearsSummary?.wrappedValue ?? L10n.unknownDash)
                    }

                    if let err = statsLastError?.wrappedValue, !err.isEmpty {
                        focusSection(.error, title: L10n.tr("errors.title", "Error", comment: "Error section title"), tint: Color.red.opacity(0.14)) {
                            Text(String(format: L10n.tr(
                                "errors.library.stats",
                                "Stats Error: %@",
                                comment: "Library stats error message with reason"
                            ), err))
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
        .navigationTitle(L10n.tr("library.stats.title", "Library Stats", comment: "Library stats navigation title"))
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
        guard !trimmed.isEmpty, trimmed != L10n.unknownDash else {
            return [L10n.tr("library.stats.no_data", "No data", comment: "Fallback row when no ranked data exists")]
        }

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
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 3
        formatter.zeroFormattingBehavior = [.dropLeading, .dropMiddle]
        return formatter.string(from: max(0, totalSeconds)) ?? "0m"
    }
}

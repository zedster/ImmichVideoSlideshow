import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var configStore: ConfigStore
    @Environment(\.dismiss) private var dismiss
    var onForceSync: (() -> Void)? = nil
    var onResetPlaybackProgress: (() -> Void)? = nil
    var syncIsSyncing: Binding<Bool>? = nil
    var syncPagesFetched: Binding<Int>? = nil
    var syncRowsUpserted: Binding<Int>? = nil
    var syncLastSyncAt: Binding<String>? = nil
    var syncLastError: Binding<String>? = nil
    var playbackError: Binding<String>? = nil

    @State private var immichURL = ""
    @State private var apiKey = ""
    @State private var minDuration = "10"
    @State private var randomBatchSize = "20"
    @State private var playbackOrder = "random"
    @State private var playbackQuality = "auto"
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Immich") {
                    Text("Use your full Immich server URL, including `http://` or `https://`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    labeledField(
                        "Immich URL",
                        placeholder: "https://immich.example.com",
                        text: $immichURL,
                        disableAutocorrect: true
                    )
                    labeledField(
                        "Immich API Key",
                        placeholder: "API key",
                        text: $apiKey,
                        disableAutocorrect: true
                    )
                    Text("API key is used to fetch and play your videos directly from Immich.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(testInProgress ? "Testing..." : "Test Immich Connection") {
                        testImmichConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(testInProgress)

                    if !testMessage.isEmpty {
                        Text(testMessage)
                            .foregroundStyle(testFailed ? .red : .green)
                    }
                }

                Section("Playback") {
                    Text("Controls which videos are eligible and how many are fetched at a time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    labeledField("Minimum Duration (seconds)", placeholder: "10", text: $minDuration)
                    labeledField("Random Batch Size", placeholder: "20", text: $randomBatchSize)
                    Picker("Order", selection: $playbackOrder) {
                        Text("Random").tag("random")
                        Text("Sequential").tag("sequential")
                    }
                    Picker("Picture Quality", selection: $playbackQuality) {
                        Text("Auto").tag("auto")
                        Text("High").tag("high")
                        Text("Medium").tag("medium")
                        Text("Low").tag("low")
                    }
                    Toggle("Only Favorites", isOn: $onlyFavorites)

                    if onResetPlaybackProgress != nil {
                        Button("Reset Playback Progress") {
                            onResetPlaybackProgress?()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Smooth Channel") {
                    Text("Crossfade and preload settings control how smooth transitions feel between videos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Crossfade Enabled", isOn: $crossfadeEnabled)
                    labeledField("Crossfade Duration (ms)", placeholder: "450", text: $crossfadeDuration)
                    labeledField("Preload Seconds Before End", placeholder: "4", text: $preloadSeconds)
                    labeledField("Queue Target Size", placeholder: "2", text: $queueTarget)
                }

                Section("Local Cache") {
                    Text("Keeps metadata in local SQLite for faster random selection and better reliability.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Use SQLite Cache", isOn: $useSQLiteCache)
                    Toggle("Sync On Startup", isOn: $syncOnStartup)
                    labeledField("Sync Page Size", placeholder: "200", text: $syncPageSize)
                    labeledField("Sync Max Pages", placeholder: "200", text: $syncMaxPages)

                    if syncIsSyncing != nil || syncLastSyncAt != nil {
                        Divider()
                        Text("Sync Status")
                            .font(.headline)
                        Text("In Progress: \(syncIsSyncing?.wrappedValue == true ? "yes" : "no")")
                        Text("Pages Fetched: \(syncPagesFetched?.wrappedValue ?? 0)")
                        Text("Rows Upserted: \(syncRowsUpserted?.wrappedValue ?? 0)")
                        Text("Last Sync At: \(syncLastSyncAt?.wrappedValue ?? "-")")
                        if let err = syncLastError?.wrappedValue, !err.isEmpty {
                            Text("Last Error: \(err)")
                                .foregroundStyle(.red)
                        }
                    }

                    if onForceSync != nil {
                        Button("Force Sync Now") {
                            onForceSync?()
                        }
                        .buttonStyle(.bordered)
                        .disabled(syncIsSyncing?.wrappedValue == true)
                    }
                }

                Section("Advanced") {
                    Text("Debug logging adds technical status info on screen and in console output.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Debug Logging", isOn: $debugEnabled)
                }

                if !validationError.isEmpty {
                    Section {
                        Text(validationError)
                            .foregroundStyle(.red)
                    }
                }

                if let playbackError, !playbackError.wrappedValue.isEmpty {
                    Section("Playback Error") {
                        Text(playbackError.wrappedValue)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Save And Start") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Created and maintained by bananasystems.co.uk.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("GitHub: zedster/ImmichVideoSlideshow", destination: URL(string: "https://github.com/zedster/ImmichVideoSlideshow")!)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Immich Channel Setup")
            .onAppear {
                loadFromConfig()
            }
        }
    }

    private func loadFromConfig() {
        let cfg = configStore.config
        immichURL = cfg.immichURL
        apiKey = cfg.apiKey
        minDuration = String(Int(cfg.minDuration))
        randomBatchSize = String(cfg.randomBatchSize)
        playbackOrder = cfg.playbackOrder
        playbackQuality = cfg.playbackQuality
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
    }

    private func save() {
        let trimmedURL = immichURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            validationError = "Immich URL and API key are required."
            return
        }

        guard let minDurationValue = Double(minDuration), minDurationValue >= 0,
              let randomBatchValue = Int(randomBatchSize), randomBatchValue > 0,
              let preloadValue = Double(preloadSeconds), preloadValue > 0,
              let fadeValue = Int(crossfadeDuration), fadeValue >= 0,
              let queueValue = Int(queueTarget), queueValue > 0,
              let syncPageValue = Int(syncPageSize), syncPageValue > 0,
              let syncMaxValue = Int(syncMaxPages), syncMaxValue > 0 else {
            validationError = "Please enter valid numeric values."
            return
        }

        var next = AppConfig()
        next.immichURL = trimmedURL
        next.apiKey = trimmedKey
        next.minDuration = minDurationValue
        next.randomBatchSize = randomBatchValue
        next.playbackOrder = playbackOrder
        next.playbackQuality = playbackQuality
        next.onlyFavorites = onlyFavorites
        next.debug = debugEnabled
        next.crossfadeEnabled = crossfadeEnabled
        next.crossfadeDurationMs = fadeValue
        next.preloadSecondsBeforeEnd = preloadValue
        next.queueTargetSize = min(queueValue, 5)
        next.useSQLiteCache = useSQLiteCache
        next.syncOnStartup = syncOnStartup
        next.syncPageSize = min(syncPageValue, 1000)
        next.syncMaxPages = syncMaxValue

        validationError = ""
        playbackError?.wrappedValue = ""
        configStore.save(next)
        dismiss()
    }

    private func testImmichConnection() {
        let trimmedURL = immichURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            testFailed = true
            testMessage = "Enter Immich URL and API key first."
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
                    testMessage = "Connection successful. URL/API key saved."
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
    private func labeledField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        disableAutocorrect: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(disableAutocorrect)
        }
    }
}

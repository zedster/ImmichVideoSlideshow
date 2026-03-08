import Foundation

struct AppConfig: Codable, Equatable {
    var immichURL: String = ""
    var apiKey: String = ""
    var minDuration: Double = 10
    var randomBatchSize: Int = 20
    var onlyFavorites: Bool = false
    var debug: Bool = false
    var crossfadeEnabled: Bool = true
    var crossfadeDurationMs: Int = 450
    var preloadSecondsBeforeEnd: Double = 4
    var queueTargetSize: Int = 2
    var playbackQuality: String = "auto"
    var useSQLiteCache: Bool = true
    var syncOnStartup: Bool = true
    var syncPageSize: Int = 200
    var syncMaxPages: Int = 200

    var isConfigured: Bool {
        !immichURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalizedImmichBaseURL: String {
        immichURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var playbackPeakBitRate: Double {
        switch playbackQuality {
        case "low":
            return 2_000_000
        case "medium":
            return 5_000_000
        case "high":
            return 10_000_000
        default:
            return 0
        }
    }

    var playbackQualityLabel: String {
        switch playbackQuality {
        case "low":
            return "low"
        case "medium":
            return "med"
        case "high":
            return "high"
        default:
            return "auto"
        }
    }
}

@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig

    private let defaultsKey = "ImmichChannelTV.Config.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = AppConfig()
        }
    }

    func save(_ newConfig: AppConfig) {
        config = newConfig
        persist()
    }

    func reset() {
        config = AppConfig()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

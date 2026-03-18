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
    var playbackOrder: String = "random"
    var playbackQuality: String = "auto"
    var showDateLocationOverlay: Bool = true
    var useSQLiteCache: Bool = true
    var syncOnStartup: Bool = true
    var syncPageSize: Int = 200
    var syncMaxPages: Int = 200

    enum CodingKeys: String, CodingKey {
        case immichURL
        case apiKey
        case minDuration
        case randomBatchSize
        case onlyFavorites
        case debug
        case crossfadeEnabled
        case crossfadeDurationMs
        case preloadSecondsBeforeEnd
        case queueTargetSize
        case playbackOrder
        case playbackQuality
        case showDateLocationOverlay
        case useSQLiteCache
        case syncOnStartup
        case syncPageSize
        case syncMaxPages
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        immichURL = try c.decodeIfPresent(String.self, forKey: .immichURL) ?? ""
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        minDuration = try c.decodeIfPresent(Double.self, forKey: .minDuration) ?? 10
        randomBatchSize = try c.decodeIfPresent(Int.self, forKey: .randomBatchSize) ?? 20
        onlyFavorites = try c.decodeIfPresent(Bool.self, forKey: .onlyFavorites) ?? false
        debug = try c.decodeIfPresent(Bool.self, forKey: .debug) ?? false
        crossfadeEnabled = try c.decodeIfPresent(Bool.self, forKey: .crossfadeEnabled) ?? true
        crossfadeDurationMs = try c.decodeIfPresent(Int.self, forKey: .crossfadeDurationMs) ?? 450
        preloadSecondsBeforeEnd = try c.decodeIfPresent(Double.self, forKey: .preloadSecondsBeforeEnd) ?? 4
        queueTargetSize = try c.decodeIfPresent(Int.self, forKey: .queueTargetSize) ?? 2
        let decodedOrder = try c.decodeIfPresent(String.self, forKey: .playbackOrder) ?? "random"
        switch decodedOrder {
        case "random", "sequential_oldest", "sequential_newest":
            playbackOrder = decodedOrder
        case "sequential":
            playbackOrder = "sequential_oldest"
        default:
            playbackOrder = "random"
        }
        playbackQuality = try c.decodeIfPresent(String.self, forKey: .playbackQuality) ?? "auto"
        showDateLocationOverlay = try c.decodeIfPresent(Bool.self, forKey: .showDateLocationOverlay) ?? true
        useSQLiteCache = try c.decodeIfPresent(Bool.self, forKey: .useSQLiteCache) ?? true
        syncOnStartup = try c.decodeIfPresent(Bool.self, forKey: .syncOnStartup) ?? true
        syncPageSize = try c.decodeIfPresent(Int.self, forKey: .syncPageSize) ?? 200
        syncMaxPages = try c.decodeIfPresent(Int.self, forKey: .syncMaxPages) ?? 200
    }

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

    private let defaultsKey = "HomeVideoChannel.Config.v1"

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

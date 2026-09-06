import Foundation

struct AppConfig: Codable, Equatable {
    var immichURL: String = ""
    var apiKey: String = ""
    var minDuration: Double = 10
    var randomBatchSize: Int = 20
    var onlyFavorites: Bool = false
    var seasonHemisphere: SeasonHemisphere = .northern
    var timeChannel: TimeChannel? = nil
    var onlyThisMonth: Bool = false
    var onlyThisDay: Bool = false
    var onlyThisWeek: Bool = false
    var referenceCaptureDate: String = ""
    var placeFilterCity: String = ""
    var placeFilterCountry: String = ""
    var albumFilterID: String = ""
    var albumFilterName: String = ""
    var personFilterID: String = ""
    var personFilterName: String = ""
    var searchQuery: String = ""
    var debug: Bool = false
    var crossfadeEnabled: Bool = true
    var crossfadeDurationMs: Int = 450
    var preloadSecondsBeforeEnd: Double = 4
    var queueTargetSize: Int = 2
    var playbackOrder: String = "random"
    var playbackQuality: String = "auto"
    var showDateLocationOverlay: Bool = true
    var showPeopleOverlay: Bool = true
    var includeDiagnosticsInFeedback: Bool = true
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
        case seasonHemisphere
        case timeChannel
        case onlyThisMonth
        case onlyThisDay
        case onlyThisWeek
        case referenceCaptureDate
        case placeFilterCity
        case placeFilterCountry
        case albumFilterID
        case albumFilterName
        case personFilterID
        case personFilterName
        case searchQuery
        case debug
        case crossfadeEnabled
        case crossfadeDurationMs
        case preloadSecondsBeforeEnd
        case queueTargetSize
        case playbackOrder
        case playbackQuality
        case showDateLocationOverlay
        case showPeopleOverlay
        case includeDiagnosticsInFeedback
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
        seasonHemisphere = try c.decodeIfPresent(SeasonHemisphere.self, forKey: .seasonHemisphere) ?? .northern
        timeChannel = try c.decodeIfPresent(TimeChannel.self, forKey: .timeChannel)
        onlyThisMonth = try c.decodeIfPresent(Bool.self, forKey: .onlyThisMonth) ?? false
        onlyThisDay = try c.decodeIfPresent(Bool.self, forKey: .onlyThisDay) ?? false
        onlyThisWeek = try c.decodeIfPresent(Bool.self, forKey: .onlyThisWeek) ?? false
        referenceCaptureDate = try c.decodeIfPresent(String.self, forKey: .referenceCaptureDate) ?? ""
        placeFilterCity = try c.decodeIfPresent(String.self, forKey: .placeFilterCity) ?? ""
        placeFilterCountry = try c.decodeIfPresent(String.self, forKey: .placeFilterCountry) ?? ""
        albumFilterID = try c.decodeIfPresent(String.self, forKey: .albumFilterID) ?? ""
        albumFilterName = try c.decodeIfPresent(String.self, forKey: .albumFilterName) ?? ""
        personFilterID = try c.decodeIfPresent(String.self, forKey: .personFilterID) ?? ""
        personFilterName = try c.decodeIfPresent(String.self, forKey: .personFilterName) ?? ""
        searchQuery = try c.decodeIfPresent(String.self, forKey: .searchQuery) ?? ""
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
        showPeopleOverlay = try c.decodeIfPresent(Bool.self, forKey: .showPeopleOverlay) ?? true
        includeDiagnosticsInFeedback = try c.decodeIfPresent(Bool.self, forKey: .includeDiagnosticsInFeedback) ?? true
        useSQLiteCache = try c.decodeIfPresent(Bool.self, forKey: .useSQLiteCache) ?? true
        syncOnStartup = try c.decodeIfPresent(Bool.self, forKey: .syncOnStartup) ?? true
        syncPageSize = try c.decodeIfPresent(Int.self, forKey: .syncPageSize) ?? 200
        syncMaxPages = try c.decodeIfPresent(Int.self, forKey: .syncMaxPages) ?? 200
    }

    var isConfigured: Bool {
        !immichURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCollectionFilter: Bool {
        !albumFilterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !personFilterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSearchFilter: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func includesDuration(_ duration: Double) -> Bool {
        duration.isFinite && duration >= minDuration
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

enum SeasonHemisphere: String, Codable, CaseIterable {
    case northern, southern

    var title: String {
        switch self {
        case .northern: return L10n.tr("settings.hemisphere.northern", "Northern", comment: "Hemisphere setting option")
        case .southern: return L10n.tr("settings.hemisphere.southern", "Southern", comment: "Hemisphere setting option")
        }
    }
}

// Rolling calendar periods and meteorological seasons.
enum TimeChannel: String, Codable, CaseIterable {
    case lastMonth = "last_month"
    case lastThreeMonths = "last_3_months"
    case lastYear = "last_year"
    case lastFiveYears = "last_5_years"
    case winter, summer, spring, autumn

    var title: String {
        switch self {
        case .lastMonth: return L10n.tr("library.channels.last_month.title", "Last month", comment: "Channel title")
        case .lastThreeMonths: return L10n.tr("library.channels.last_3_months.title", "Last 3 months", comment: "Channel title")
        case .lastYear: return L10n.tr("library.channels.last_year.title", "Last Year", comment: "Channel title")
        case .lastFiveYears: return L10n.tr("library.channels.last_5_years.title", "Last 5 years", comment: "Channel title")
        case .winter: return L10n.tr("library.channels.winter.title", "Winter", comment: "Channel title")
        case .summer: return L10n.tr("library.channels.summer.title", "Summer", comment: "Channel title")
        case .spring: return L10n.tr("library.channels.spring.title", "Spring", comment: "Channel title")
        case .autumn: return L10n.tr("library.channels.autumn.title", "Autumn", comment: "Channel title")
        }
    }

    var months: [Int] {
        switch self {
        case .winter: return [12, 1, 2]
        case .spring: return [3, 4, 5]
        case .summer: return [6, 7, 8]
        case .autumn: return [9, 10, 11]
        default: return []
        }
    }

    func months(in hemisphere: SeasonHemisphere) -> [Int] {
        hemisphere == .northern ? months : months.map { (($0 + 5) % 12) + 1 }
    }

    var symbol: String {
        switch self {
        case .winter: return "snowflake"
        case .spring: return "leaf.fill"
        case .summer: return "sun.max.fill"
        case .autumn: return "leaf"
        default: return "calendar"
        }
    }

    func dateBounds(now: Date = Date(), calendar: Calendar = .current) -> (start: String, end: String)? {
        let component: Calendar.Component
        let offset: Int
        switch self {
        case .lastMonth: (component, offset) = (.month, -1)
        case .lastThreeMonths: (component, offset) = (.month, -3)
        case .lastYear: (component, offset) = (.year, -1)
        case .lastFiveYears: (component, offset) = (.year, -5)
        default: return nil
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let today = gregorian.startOfDay(for: now)
        guard let start = gregorian.date(byAdding: component, value: offset, to: today),
              let end = gregorian.date(byAdding: .day, value: 1, to: today) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = gregorian.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }

    func includes(_ captureDate: String, hemisphere: SeasonHemisphere = .northern, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = String(captureDate.prefix(10))
        guard day.count == 10, let month = Int(day.dropFirst(5).prefix(2)), (1...12).contains(month) else { return false }
        if let bounds = dateBounds(now: now, calendar: calendar) {
            return day >= bounds.start && day < bounds.end
        }
        return months(in: hemisphere).contains(month)
    }
}

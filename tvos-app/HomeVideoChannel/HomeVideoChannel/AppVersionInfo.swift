import Foundation

struct AppVersionInfo: Equatable {
    let marketingVersion: String
    let buildNumber: String

    var displayVersion: String {
        let trimmedVersion = marketingVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedVersion.isEmpty {
            return trimmedVersion
        }
        let trimmedBuild = buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBuild.isEmpty
            ? L10n.tr("common.unknown", "Unknown", comment: "Fallback text for unknown version")
            : trimmedBuild
    }

    static var current: AppVersionInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let marketingVersion = (info["CFBundleShortVersionString"] as? String) ?? ""
        let buildNumber = (info["CFBundleVersion"] as? String) ?? ""
        return AppVersionInfo(marketingVersion: marketingVersion, buildNumber: buildNumber)
    }
}

struct DottedVersion: Comparable, Equatable {
    let rawValue: String
    private let components: [Int]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ".")
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        parsed.reserveCapacity(parts.count)

        for part in parts {
            guard let value = Int(part) else { return nil }
            parsed.append(value)
        }

        self.rawValue = trimmed
        self.components = parsed
    }

    static func < (lhs: DottedVersion, rhs: DottedVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<maxCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

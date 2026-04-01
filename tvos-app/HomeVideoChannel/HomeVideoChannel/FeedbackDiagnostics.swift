import Foundation
import UIKit

struct FeedbackDiagnostics {
    struct Item: Identifiable, Equatable {
        let label: String
        let value: String

        var id: String { label }
    }

    static let feedbackBaseURL = URL(string: "https://bananasystems.co.uk/home-video-channel/fb")!
    static let fallbackDisplayURL = "bananasystems.co.uk/home-video-channel/fb"

    // Replace this when a support mailbox is ready.
    static let supportEmail: String = "support@bananasystems.co.uk"

    let config: AppConfig
    let supportCode: String

    var feedbackURL: URL {
        var components = URLComponents(url: Self.feedbackBaseURL, resolvingAgainstBaseURL: false)
        let items = queryItems
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url ?? Self.feedbackBaseURL
    }

    var summaryItems: [Item] {
        var items: [Item] = [
            Item(label: "Support Code", value: supportCode),
            Item(label: "Diagnostics Sharing", value: config.includeDiagnosticsInFeedback ? "On" : "Off")
        ]

        if config.includeDiagnosticsInFeedback {
            items.append(Item(label: "App Version", value: appVersionSummary))
            items.append(Item(label: "Platform", value: "tvOS \(device.systemVersion)"))
            if let deviceModel, !deviceModel.isEmpty {
                items.append(Item(label: "Device", value: deviceModel))
            }
            items.append(Item(label: "Playback Mode", value: playbackModeLabel))
            items.append(Item(label: "Minimum Clip", value: formattedMinDuration))
            items.append(Item(label: "Crossfade", value: config.crossfadeEnabled ? "Enabled" : "Disabled"))
        } else {
            items.append(Item(label: "Shared In URL", value: "Support code only"))
        }

        return items
    }

    private var queryItems: [URLQueryItem] {
        if !config.includeDiagnosticsInFeedback {
            return [URLQueryItem(name: "supportCode", value: supportCode)]
        }

        var items: [URLQueryItem] = []
        appendQueryItem(named: "sc", value: supportCode, to: &items)
        appendQueryItem(named: "av", value: appVersion, to: &items)
        appendQueryItem(named: "bn", value: buildNumber, to: &items)
        appendQueryItem(named: "p", value: "tvOS", to: &items)
        appendQueryItem(named: "osv", value: device.systemVersion, to: &items)
        appendQueryItem(named: "d", value: deviceModel, to: &items)
        appendQueryItem(named: "lm", value: nonEmpty(device.localizedModel), to: &items)
        appendQueryItem(named: "bi", value: bundleIdentifier, to: &items)
        appendQueryItem(named: "pm", value: playbackModeParameter, to: &items)
        appendQueryItem(named: "md", value: formattedMinDurationParameter, to: &items)
        appendQueryItem(named: "ce", value: String(config.crossfadeEnabled), to: &items)
        appendQueryItem(named: "doag", value: "true", to: &items)
        return items
    }

    private var device: UIDevice {
        UIDevice.current
    }

    private var appVersion: String? {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    private var buildNumber: String? {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    private var bundleIdentifier: String? {
        nonEmpty(Bundle.main.bundleIdentifier)
    }

    private var deviceModel: String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let machine = machineMirror.children.reduce(into: "") { partialResult, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partialResult.append(Character(UnicodeScalar(UInt8(value))))
        }
        return nonEmpty(machine)
    }

    private var playbackModeParameter: String {
        switch config.playbackOrder {
        case "sequential_oldest":
            return "chronological_oldest"
        case "sequential_newest":
            return "chronological_newest"
        default:
            return "random"
        }
    }

    private var playbackModeLabel: String {
        switch config.playbackOrder {
        case "sequential_oldest":
            return "Chronological (Oldest First)"
        case "sequential_newest":
            return "Chronological (Newest First)"
        default:
            return "Random"
        }
    }

    private var formattedMinDuration: String {
        if config.minDuration.rounded() == config.minDuration {
            return "\(Int(config.minDuration)) sec"
        }
        return String(format: "%.1f sec", config.minDuration)
    }

    private var formattedMinDurationParameter: String {
        if config.minDuration.rounded() == config.minDuration {
            return "\(Int(config.minDuration))"
        }
        return String(format: "%.1f", config.minDuration)
    }

    private var appVersionSummary: String {
        switch (appVersion, buildNumber) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), nil):
            return version
        case let (nil, .some(build)):
            return "Build \(build)"
        default:
            return "-"
        }
    }

    private func appendQueryItem(named name: String, value: String?, to items: inout [URLQueryItem]) {
        guard let value = nonEmpty(value) else { return }
        items.append(URLQueryItem(name: name, value: value))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func makeSupportCode(length: Int = 6) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).map { _ in alphabet.randomElement() ?? "X" })
    }
}

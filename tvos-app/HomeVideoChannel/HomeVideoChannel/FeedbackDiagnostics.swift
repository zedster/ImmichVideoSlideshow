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
            Item(
                label: L10n.tr("feedback.diagnostics.support_code", "Support Code", comment: "Diagnostics field label"),
                value: supportCode
            ),
            Item(
                label: L10n.tr("feedback.diagnostics.sharing", "Diagnostics Sharing", comment: "Diagnostics field label"),
                value: L10n.onOff(config.includeDiagnosticsInFeedback)
            )
        ]

        if config.includeDiagnosticsInFeedback {
            items.append(Item(
                label: L10n.tr("feedback.diagnostics.app_version", "App Version", comment: "Diagnostics field label"),
                value: appVersionSummary
            ))
            items.append(Item(
                label: L10n.tr("feedback.diagnostics.platform", "Platform", comment: "Diagnostics field label"),
                value: String(format: L10n.tr(
                    "feedback.diagnostics.platform.value",
                    "tvOS %@",
                    comment: "Platform value with OS version"
                ), device.systemVersion)
            ))
            if let deviceModel, !deviceModel.isEmpty {
                items.append(Item(
                    label: L10n.tr("feedback.diagnostics.device", "Device", comment: "Diagnostics field label"),
                    value: deviceModel
                ))
            }
            items.append(Item(
                label: L10n.tr("feedback.diagnostics.playback_mode", "Playback Mode", comment: "Diagnostics field label"),
                value: playbackModeLabel
            ))
            items.append(Item(
                label: L10n.tr("feedback.diagnostics.minimum_clip", "Minimum Clip", comment: "Diagnostics field label"),
                value: formattedMinDuration
            ))
            items.append(Item(
                label: L10n.tr("feedback.diagnostics.crossfade", "Crossfade", comment: "Diagnostics field label"),
                value: config.crossfadeEnabled
                    ? L10n.tr("common.enabled", "Enabled", comment: "Generic enabled label")
                    : L10n.tr("common.disabled", "Disabled", comment: "Generic disabled label")
            ))
        } else {
            items.append(Item(
                label: L10n.tr("feedback.diagnostics.shared_in_url", "Shared In URL", comment: "Diagnostics field label"),
                value: L10n.tr(
                    "feedback.diagnostics.shared_in_url.value",
                    "Support code only",
                    comment: "Diagnostic summary text when sharing is disabled"
                )
            ))
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
            return L10n.tr(
                "playback.mode.chronological_oldest",
                "Chronological (Oldest First)",
                comment: "Playback order option"
            )
        case "sequential_newest":
            return L10n.tr(
                "playback.mode.chronological_newest",
                "Chronological (Newest First)",
                comment: "Playback order option"
            )
        default:
            return L10n.tr("playback.mode.random", "Random", comment: "Playback order option")
        }
    }

    private var formattedMinDuration: String {
        let measurement = Measurement(value: config.minDuration, unit: UnitDuration.seconds)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(config.minDuration.rounded() == config.minDuration ? 0 : 1))
            )
        )
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
            return String(format: L10n.tr(
                "about.build.value",
                "Build %@",
                comment: "Build label with build number"
            ), build)
        default:
            return L10n.unknownDash
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

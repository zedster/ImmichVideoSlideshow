import Foundation

enum L10n {
    static func tr(_ key: String, _ fallback: String, comment: String = "") -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: comment)
    }

    static func onOff(_ isOn: Bool) -> String {
        isOn ? tr("common.on", "On", comment: "Generic enabled state")
             : tr("common.off", "Off", comment: "Generic disabled state")
    }

    static var unknownDash: String {
        tr("common.unknown_dash", "-", comment: "Placeholder for unknown or unavailable values")
    }
}

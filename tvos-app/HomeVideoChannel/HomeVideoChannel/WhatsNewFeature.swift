import Foundation

struct WhatsNewItem: Identifiable, Equatable {
    let icon: String
    let title: String
    let description: String

    var id: String { title }
}

struct WhatsNewEntry: Identifiable, Equatable {
    let version: String
    let title: String
    let subtitle: String
    let items: [WhatsNewItem]

    var id: String { version }
}

enum WhatsNewContentProvider {
    static let entriesByVersion: [String: WhatsNewEntry] = [
        "2": WhatsNewEntry(
            version: "2",
            title: "What's New",
            subtitle: "Home Video Channel got a proper identity refresh and a cleaner setup experience.",
            items: [
                WhatsNewItem(
                    icon: "tv.fill",
                    title: "New app identity",
                    description: "The app name, iconography, and presentation were refreshed around the new Home Video Channel branding."
                ),
                WhatsNewItem(
                    icon: "wand.and.stars",
                    title: "Cleaner overall experience",
                    description: "This release focused on making the Apple TV app feel more polished and easier to navigate."
                ),
                WhatsNewItem(
                    icon: "play.rectangle.fill",
                    title: "More living-room friendly",
                    description: "Playback and navigation were shaped more around a simple lean-back TV experience."
                )
            ]
        ),
        "2.1": WhatsNewEntry(
            version: "2.1",
            title: "What's New",
            subtitle: "Setup and diagnostics got much easier from the sofa.",
            items: [
                WhatsNewItem(
                    icon: "qrcode",
                    title: "QR-guided setup",
                    description: "The app added a friendlier setup flow with QR help so it is easier to get connected without typing everything on Apple TV."
                ),
                WhatsNewItem(
                    icon: "gearshape.2.fill",
                    title: "Nicer settings",
                    description: "Settings were reorganized into a cleaner TV-first layout that is easier to scan and adjust."
                ),
                WhatsNewItem(
                    icon: "chart.bar.xaxis",
                    title: "Better debugging and stats",
                    description: "Extra playback diagnostics landed to help track down high bitrate and library issues."
                )
            ]
        ),
        "2.2": WhatsNewEntry(
            version: "2.2",
            title: "What's New",
            subtitle: "Playback and library tools became more reliable and easier to use.",
            items: [
                WhatsNewItem(
                    icon: "list.bullet.rectangle.portrait",
                    title: "Improved library stats",
                    description: "The library stats screen was cleaned up and fixed so it scrolls properly and surfaces more useful viewing info."
                ),
                WhatsNewItem(
                    icon: "slider.horizontal.3",
                    title: "Playback control fixes",
                    description: "The video seeker and related focus behavior were refined so playback controls feel more predictable on the Siri Remote."
                ),
                WhatsNewItem(
                    icon: "hammer.fill",
                    title: "Stability improvements",
                    description: "This release focused on reliability work across settings, stats, and everyday playback."
                )
            ]
        ),
        "2.3": WhatsNewEntry(
            version: "2.3",
            title: "What's New",
            subtitle: "A bigger upgrade for channels, feedback, and metadata-rich playback.",
            items: [
                WhatsNewItem(
                    icon: "square.grid.2x2.fill",
                    title: "Smarter channel tabs",
                    description: "Browse channels by time and place, then switch across albums and people right from the selector."
                ),
                WhatsNewItem(
                    icon: "person.2.crop.square.stack.fill",
                    title: "Richer synced metadata",
                    description: "Album and people data now sync from Immich, with better artwork, people labels, and more useful browsing context."
                ),
                WhatsNewItem(
                    icon: "qrcode",
                    title: "QR feedback and polish",
                    description: "Send feedback from your phone with the new QR screen, plus a round of playback, focus, and stability fixes."
                )
            ]
        )
    ]

    static func entry(for version: String) -> WhatsNewEntry? {
        entriesByVersion[version.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}

@MainActor
final class WhatsNewController: ObservableObject {
    @Published private(set) var presentedEntry: WhatsNewEntry?

    private let defaults: UserDefaults
    private let versionInfo: AppVersionInfo

    private static let acknowledgedVersionKey = "lastAcknowledgedWhatsNewVersion"
    private static let showOnFirstInstall = true

    init(
        defaults: UserDefaults = .standard,
        versionInfo: AppVersionInfo = .current
    ) {
        self.defaults = defaults
        self.versionInfo = versionInfo
        evaluatePresentation()
    }

    func evaluatePresentation() {
        let currentVersion = versionInfo.displayVersion
        guard let entry = WhatsNewContentProvider.entry(for: currentVersion) else {
            presentedEntry = nil
            return
        }

        let acknowledgedVersion = (defaults.string(forKey: Self.acknowledgedVersionKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if acknowledgedVersion.isEmpty {
            presentedEntry = Self.showOnFirstInstall ? entry : nil
            return
        }

        if acknowledgedVersion == currentVersion {
            presentedEntry = nil
            return
        }

        guard let current = DottedVersion(currentVersion),
              let acknowledged = DottedVersion(acknowledgedVersion) else {
            presentedEntry = currentVersion == acknowledgedVersion ? nil : entry
            return
        }

        presentedEntry = current > acknowledged ? entry : nil
    }

    func acknowledgeCurrentEntry() {
        guard let presentedEntry else { return }
        defaults.set(presentedEntry.version, forKey: Self.acknowledgedVersionKey)
        self.presentedEntry = nil
    }
}

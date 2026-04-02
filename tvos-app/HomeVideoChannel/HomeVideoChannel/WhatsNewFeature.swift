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
            title: L10n.tr("whatsnew.common.title", "What's New", comment: "Title of the release notes screen"),
            subtitle: L10n.tr(
                "whatsnew.2.subtitle",
                "Home Video Channel got a proper identity refresh and a cleaner setup experience.",
                comment: "Subtitle for version 2 What's New entry"
            ),
            items: [
                WhatsNewItem(
                    icon: "tv.fill",
                    title: L10n.tr("whatsnew.2.item1.title", "New app identity", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2.item1.description",
                        "The app name, iconography, and presentation were refreshed around the new Home Video Channel branding.",
                        comment: "What's New item description"
                    )
                ),
                WhatsNewItem(
                    icon: "wand.and.stars",
                    title: L10n.tr("whatsnew.2.item2.title", "Cleaner overall experience", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2.item2.description",
                        "This release focused on making the Apple TV app feel more polished and easier to navigate.",
                        comment: "What's New item description"
                    )
                ),
                WhatsNewItem(
                    icon: "play.rectangle.fill",
                    title: L10n.tr("whatsnew.2.item3.title", "More living-room friendly", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2.item3.description",
                        "Playback and navigation were shaped more around a simple lean-back TV experience.",
                        comment: "What's New item description"
                    )
                )
            ]
        ),
        "2.1": WhatsNewEntry(
            version: "2.1",
            title: L10n.tr("whatsnew.common.title", "What's New", comment: "Title of the release notes screen"),
            subtitle: L10n.tr(
                "whatsnew.2_1.subtitle",
                "Setup and diagnostics got much easier from the sofa.",
                comment: "Subtitle for version 2.1 What's New entry"
            ),
            items: [
                WhatsNewItem(
                    icon: "qrcode",
                    title: L10n.tr("whatsnew.2_1.item1.title", "QR-guided setup", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_1.item1.description",
                        "The app added a friendlier setup flow with QR help so it is easier to get connected without typing everything on Apple TV.",
                        comment: "What's New item description"
                    )
                ),
                WhatsNewItem(
                    icon: "gearshape.2.fill",
                    title: L10n.tr("whatsnew.2_1.item2.title", "Nicer settings", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_1.item2.description",
                        "Settings were reorganized into a cleaner TV-first layout that is easier to scan and adjust.",
                        comment: "What's New item description"
                    )
                ),
                WhatsNewItem(
                    icon: "chart.bar.xaxis",
                    title: L10n.tr("whatsnew.2_1.item3.title", "Better debugging and stats", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_1.item3.description",
                        "Extra playback diagnostics landed to help track down high bitrate and library issues.",
                        comment: "What's New item description"
                    )
                )
            ]
        ),
        "2.2": WhatsNewEntry(
            version: "2.2",
            title: L10n.tr("whatsnew.common.title", "What's New", comment: "Title of the release notes screen"),
            subtitle: L10n.tr(
                "whatsnew.2_2.subtitle",
                "Playback and library tools became more reliable and easier to use.",
                comment: "Subtitle for version 2.2 What's New entry"
            ),
            items: [
                WhatsNewItem(
                    icon: "list.bullet.rectangle.portrait",
                    title: L10n.tr("whatsnew.2_2.item1.title", "Improved library stats", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_2.item1.description",
                        "The library stats screen was cleaned up and fixed so it scrolls properly and surfaces more useful viewing info.",
                        comment: "What's New item description"
                    )
                ),
                WhatsNewItem(
                    icon: "slider.horizontal.3",
                    title: L10n.tr("whatsnew.2_2.item2.title", "Playback control fixes", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_2.item2.description",
                        "The video seeker and related focus behavior were refined so playback controls feel more predictable on the Siri Remote.",
                        comment: "What's New item description"
                    )
                ),
                WhatsNewItem(
                    icon: "hammer.fill",
                    title: L10n.tr("whatsnew.2_2.item3.title", "Stability improvements", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_2.item3.description",
                        "This release focused on reliability work across settings, stats, and everyday playback.",
                        comment: "What's New item description"
                    )
                )
            ]
        ),
        "2.5": WhatsNewEntry(
            version: "2.5",
            title: L10n.tr("whatsnew.common.title", "What's New", comment: "Title of the release notes screen"),
            subtitle: L10n.tr(
                "whatsnew.2_5.subtitle",
                "A bigger upgrade for channels, feedback, and metadata-rich playback.",
                comment: "Subtitle for version 2.5 What's New entry"
            ),
            items: [
                WhatsNewItem(
                    icon: "square.grid.2x2.fill",
                    title: L10n.tr("whatsnew.2_5.item1.title", "Smarter channel tabs", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_5.item1.description",
                        "Browse channels by time and place, then switch across albums and people right from the selector.",
                        comment: "What's New item description"
                    )
                ),
                WhatsNewItem(
                    icon: "person.2.crop.square.stack.fill",
                    title: L10n.tr("whatsnew.2_5.item2.title", "Richer synced metadata", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_5.item2.description",
                        "Album and people data now sync from Immich, with better artwork, people labels, and more useful browsing context.",
                        comment: "What's New item description"
                    )
                ),
                WhatsNewItem(
                    icon: "qrcode",
                    title: L10n.tr("whatsnew.2_5.item3.title", "QR feedback and polish", comment: "What's New item title"),
                    description: L10n.tr(
                        "whatsnew.2_5.item3.description",
                        "Send feedback from your phone with the new QR screen, plus a round of playback, focus, and stability fixes.",
                        comment: "What's New item description"
                    )
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

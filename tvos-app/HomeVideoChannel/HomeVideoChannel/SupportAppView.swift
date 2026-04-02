import SwiftUI

struct SupportAppView: View {
    private let supportBaseURL = URL(string: "https://bananasystems.co.uk/home-video-channel/support")!
    private let supportDisplayURL = "bananasystems.co.uk/home-video-channel/support"

    // Keep this easy to disable if you only want a plain URL QR.
    private let includeTrackingParameters = true

    private var supportURL: URL {
        guard includeTrackingParameters else { return supportBaseURL }

        var components = URLComponents(url: supportBaseURL, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "source", value: "tvos"),
            URLQueryItem(name: "app", value: "home-video-channel")
        ]

        if let version = nonEmpty(appVersion) {
            queryItems.append(URLQueryItem(name: "av", value: version))
        }
        if let build = nonEmpty(buildNumber) {
            queryItems.append(URLQueryItem(name: "bn", value: build))
        }

        components?.queryItems = queryItems
        return components?.url ?? supportBaseURL
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    private var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
    }

    private var versionSummary: String {
        let version = nonEmpty(appVersion)
        let build = nonEmpty(buildNumber)

        switch (version, build) {
        case let (.some(v), .some(b)):
            return String(format: L10n.tr(
                "support.version_build",
                "Version %@ (%@)",
                comment: "Version and build text shown on support screen"
            ), v, b)
        case let (.some(v), nil):
            return String(format: L10n.tr(
                "support.version_only",
                "Version %@",
                comment: "Version-only text shown on support screen"
            ), v)
        case let (nil, .some(b)):
            return String(format: L10n.tr(
                "support.build_only",
                "Build %@",
                comment: "Build-only text shown on support screen"
            ), b)
        default:
            return L10n.unknownDash
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 12) {
                    Text(L10n.tr(
                        "support.title",
                        "Support the App",
                        comment: "Support screen title"
                    ))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                    Text(L10n.tr(
                        "support.description.primary",
                        "If you've enjoyed Home Video Channel, you can support development by scanning this QR code on your phone.",
                        comment: "Primary support screen description"
                    ))
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(maxWidth: 980)

                    Text(L10n.tr(
                        "support.description.secondary",
                        "Your support helps fund updates and future features.",
                        comment: "Secondary support screen description"
                    ))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.76))
                }

                VStack(spacing: 16) {
                    QRCodeView(
                        value: supportURL.absoluteString,
                        size: 420,
                        accessibilityLabelText: L10n.tr(
                            "support.qr.accessibility_label",
                            "Support QR code",
                            comment: "Accessibility label for the support QR code"
                        )
                    )

                    VStack(spacing: 8) {
                        Text(L10n.tr(
                            "support.fallback_url.label",
                            "Support URL",
                            comment: "Label shown above support fallback URL"
                        ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.66))

                        Text(supportDisplayURL)
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.94))

                        Text(L10n.tr(
                            "support.secure_note",
                            "This opens a secure support page on your phone.",
                            comment: "Note below support fallback URL"
                        ))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(28)
                .frame(maxWidth: 760)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.20), radius: 24, y: 10)

                Text(versionSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 56)
            .padding(.vertical, 40)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle(L10n.tr(
            "support.title",
            "Support the App",
            comment: "Support screen navigation title"
        ))
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.08, blue: 0.14),
                Color(red: 0.11, green: 0.17, blue: 0.24),
                Color(red: 0.18, green: 0.11, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SupportAppView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SupportAppView()
        }
        .preferredColorScheme(.dark)
    }
}

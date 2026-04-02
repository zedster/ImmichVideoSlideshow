import SwiftUI

struct FeedbackView: View {
    private enum SectionID: Hashable {
        case feedback
        case diagnostics
    }

    let config: AppConfig
    @State private var supportCode = FeedbackDiagnostics.makeSupportCode()
    @FocusState private var focusedSection: SectionID?

    private var diagnostics: FeedbackDiagnostics {
        FeedbackDiagnostics(config: config, supportCode: supportCode)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .center, spacing: 30) {
                    feedbackSection(.feedback) {
                        HStack(alignment: .center, spacing: 34) {
                            QRCodeView(
                                value: diagnostics.feedbackURL.absoluteString,
                                size: 360,
                                accessibilityLabelText: L10n.tr(
                                    "feedback.qr.accessibility_label",
                                    "Feedback QR code",
                                    comment: "Accessibility label for the feedback QR code"
                                )
                            )

                            VStack(alignment: .leading, spacing: 18) {
                                Text(L10n.tr(
                                    "feedback.title",
                                    "Send Feedback",
                                    comment: "Feedback screen main title"
                                ))
                                    .font(.system(size: 52, weight: .bold, design: .rounded))

                                Text(L10n.tr(
                                    "feedback.description",
                                    "Scan this QR code with your phone to send feedback. We'll include app and device info to help diagnose issues.",
                                    comment: "Feedback screen description explaining QR code usage"
                                ))
                                    .font(.title3.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(.white.opacity(0.82))

                                VStack(alignment: .leading, spacing: 10) {
                                    Text(L10n.tr(
                                        "feedback.fallback_url.label",
                                        "Fallback URL",
                                        comment: "Label above the fallback feedback URL"
                                    ))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.66))
                                    Text(FeedbackDiagnostics.fallbackDisplayURL)
                                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                                        .multilineTextAlignment(.leading)
                                }

                                let supportEmail = FeedbackDiagnostics.supportEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !supportEmail.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(L10n.tr(
                                            "feedback.support_email.label",
                                            "Support Email",
                                            comment: "Label above support email address"
                                        ))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.66))
                                        Text(supportEmail)
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.92))
                                    }
                                }

                                Text(String(format: L10n.tr(
                                    "feedback.support_code.value",
                                    "Support code: %@",
                                    comment: "Support code shown in feedback screen"
                                ), supportCode))
                                    .font(.headline.monospaced())
                                    .foregroundStyle(Color(red: 0.98, green: 0.83, blue: 0.42))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.black.opacity(0.28))
                                    .clipShape(Capsule())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: 1040)

                    feedbackSection(.diagnostics) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(L10n.tr(
                                "feedback.diagnostics.title",
                                "Diagnostics Summary",
                                comment: "Section title listing diagnostics fields included in feedback"
                            ))
                                .font(.title3.weight(.semibold))

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(diagnostics.summaryItems) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.label)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.64))
                                        Text(item.value)
                                            .font(.headline)
                                            .foregroundStyle(.white.opacity(0.92))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 980)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 56)
                .padding(.vertical, 40)
            }
            .onAppear {
                if focusedSection == nil {
                    focusedSection = .feedback
                }
            }
            .onChange(of: focusedSection) { target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle(L10n.tr(
            "feedback.title",
            "Send Feedback",
            comment: "Feedback screen navigation title"
        ))
    }

    @ViewBuilder
    private func feedbackSection<Content: View>(_ id: SectionID, @ViewBuilder content: () -> Content) -> some View {
        let isFocused = focusedSection == id

        feedbackCard {
            content()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(isFocused ? Color.white.opacity(0.92) : Color.white.opacity(0.10), lineWidth: isFocused ? 3 : 1)
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isFocused ? 0.30 : 0.18), radius: isFocused ? 30 : 24, y: 10)
        .animation(.easeInOut(duration: 0.18), value: isFocused)
        .focusable(true)
        .focused($focusedSection, equals: id)
        .id(id)
    }

    @ViewBuilder
    private func feedbackCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 24, y: 10)
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
}

struct FeedbackView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FeedbackView(config: AppConfig())
        }
        .preferredColorScheme(.dark)
    }
}

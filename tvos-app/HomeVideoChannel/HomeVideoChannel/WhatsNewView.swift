import SwiftUI

struct WhatsNewView: View {
    let entry: WhatsNewEntry
    let onContinue: () -> Void

    @FocusState private var continueFocused: Bool

    var body: some View {
        ZStack {
            background

            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Text(entry.title)
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Version \(entry.version)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.78))

                    Text(entry.subtitle)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 860)
                }

                VStack(spacing: 18) {
                    ForEach(entry.items) { item in
                        whatsNewRow(item)
                    }
                }
                .frame(maxWidth: 980)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .frame(minWidth: 280)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(continueFocused ? Color.white : Color(red: 0.98, green: 0.42, blue: 0.36))
                        )
                        .foregroundStyle(continueFocused ? Color.black : Color.white)
                }
                .buttonStyle(.plain)
                .focused($continueFocused)
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 44)
        }
        .ignoresSafeArea()
        .onAppear {
            continueFocused = true
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.11, green: 0.19, blue: 0.27),
                    Color(red: 0.21, green: 0.10, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 540, height: 540)
                .blur(radius: 40)
                .offset(x: -420, y: -250)

            Circle()
                .fill(Color(red: 1.0, green: 0.56, blue: 0.34).opacity(0.14))
                .frame(width: 500, height: 500)
                .blur(radius: 28)
                .offset(x: 460, y: -220)
        }
    }

    @ViewBuilder
    private func whatsNewRow(_ item: WhatsNewItem) -> some View {
        HStack(alignment: .top, spacing: 20) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: 76, height: 76)
                .overlay {
                    Image(systemName: item.icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.83, blue: 0.48))
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text(item.description)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

struct WhatsNewView_Previews: PreviewProvider {
    static var previews: some View {
        WhatsNewView(
            entry: WhatsNewContentProvider.entry(for: "2.3")!,
            onContinue: {}
        )
        .preferredColorScheme(.dark)
    }
}

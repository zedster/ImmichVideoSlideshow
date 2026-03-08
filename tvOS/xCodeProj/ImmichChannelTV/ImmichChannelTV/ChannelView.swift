import AVKit
import SwiftUI

struct ChannelView: View {
    @ObservedObject private var configStore: ConfigStore
    @StateObject private var coordinator: ChannelCoordinator
    @State private var showSetup = false
    @State private var showInfo = false

    init(configStore: ConfigStore) {
        self._configStore = ObservedObject(wrappedValue: configStore)
        _coordinator = StateObject(wrappedValue: ChannelCoordinator(configStore: configStore))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VideoPlayer(player: coordinator.playerA)
                    .ignoresSafeArea()
                    .opacity(coordinator.opacityA)
                    .allowsHitTesting(false)

                VideoPlayer(player: coordinator.playerB)
                    .ignoresSafeArea()
                    .opacity(coordinator.opacityB)
                    .allowsHitTesting(false)

                VStack {
                    if !coordinator.fallbackMessage.isEmpty {
                        Text(coordinator.fallbackMessage)
                            .font(.caption.monospaced())
                            .padding(8)
                            .background(Color.red.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 28)
                    }

                    Spacer()
                }

                if !coordinator.captionText.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            outlinedCaption(coordinator.captionText)
                                .padding(.leading, 20)
                                .padding(.bottom, max(40, geo.size.height * 0.10))
                            Spacer()
                        }
                    }
                }

                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Text(coordinator.title)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Spacer()

                        Text(coordinator.statusText)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            coordinator.togglePlayPause()
                        } label: {
                            Image(systemName: coordinator.playPauseButtonSystemImage())
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Play Pause")

                        Button {
                            coordinator.skip()
                        } label: {
                            Image(systemName: "forward.end.fill")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Skip")

                        Button {
                            coordinator.toggleFavorite()
                        } label: {
                            Image(systemName: coordinator.favoriteButtonSystemImage())
                        }
                        .buttonStyle(.bordered)
                        .disabled(coordinator.favoriteUpdateInProgress)
                        .accessibilityLabel(coordinator.favoriteButtonLabel())

                        Button {
                            showInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Info")

                        Button {
                            showSetup = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Settings")
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            coordinator.start()
        }
        .onDisappear {
            coordinator.stop()
        }
        .onChange(of: configStore.config) { _ in
            coordinator.restart()
        }
        .onChange(of: coordinator.shouldOpenSetup) { shouldOpen in
            guard shouldOpen else { return }
            showSetup = true
            coordinator.acknowledgeSetupOpenRequest()
        }
        .sheet(isPresented: $showSetup) {
            SetupView(onForceSync: {
                coordinator.forceSyncNow()
            },
            syncIsSyncing: Binding(get: { coordinator.isSyncing }, set: { _ in }),
            syncPagesFetched: Binding(get: { coordinator.syncPagesFetched }, set: { _ in }),
            syncRowsUpserted: Binding(get: { coordinator.syncRowsUpserted }, set: { _ in }),
            syncLastSyncAt: Binding(get: { coordinator.syncLastSyncAt }, set: { _ in }),
            syncLastError: Binding(get: { coordinator.syncLastError }, set: { _ in }),
            playbackError: Binding(get: { coordinator.setupErrorMessage }, set: { coordinator.setupErrorMessage = $0 }))
                .environmentObject(configStore)
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                List(coordinator.currentInfoFields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(field.value)
                            .font(.body.monospaced())
                    }
                    .padding(.vertical, 4)
                }
                .navigationTitle("Video Info")
            }
        }
    }

    @ViewBuilder
    private func outlinedCaption(_ text: String) -> some View {
        let base = Text(text)
            .font(.system(size: 34, weight: .heavy))
            .multilineTextAlignment(.leading)
            .lineSpacing(2)

        ZStack {
            base.foregroundColor(.black).offset(x: -1.2, y: -1.2)
            base.foregroundColor(.black).offset(x: 1.2, y: -1.2)
            base.foregroundColor(.black).offset(x: -1.2, y: 1.2)
            base.foregroundColor(.black).offset(x: 1.2, y: 1.2)
            base.foregroundColor(.black).offset(x: 0, y: 1.6)
            base.foregroundColor(.black).offset(x: 0, y: -1.6)
            base.foregroundColor(.white)
        }
    }
}

import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct ChannelView: View {
    @ObservedObject private var configStore: ConfigStore
    @StateObject private var coordinator: ChannelCoordinator
    @State private var showSetup = false
    @State private var showInfo = false
    @State private var shouldResumeAfterSettings = false
    @State private var infoScrollIndex = 0
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showHideForeverConfirmation = false
    @FocusState private var inputAnchorFocused: Bool

    init(configStore: ConfigStore) {
        self._configStore = ObservedObject(wrappedValue: configStore)
        _coordinator = StateObject(wrappedValue: ChannelCoordinator(configStore: configStore))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                PlayerSurfaceView(player: coordinator.playerA)
                    .ignoresSafeArea()
                    .opacity(coordinator.opacityA)
                    .allowsHitTesting(false)

                PlayerSurfaceView(player: coordinator.playerB)
                    .ignoresSafeArea()
                    .opacity(coordinator.opacityB)
                    .allowsHitTesting(false)

                if !controlsVisible && !showInfo && !showSetup {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .focusable(true)
                        .focused($inputAnchorFocused)
                        .opacity(0.001)
                }

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

                if configStore.config.debug && !coordinator.recentDebugMessages.isEmpty {
                    VStack {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(coordinator.recentDebugMessages.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.white.opacity(0.9))
                                        .lineLimit(1)
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.leading, 16)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.top, 56)
                }

                if coordinator.isBuffering {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .padding(18)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }

                if !coordinator.dateLocationText.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            // outlinedCaption((
                            //     coordinator.dateLocationText,
                            //     fontSize: 24,
                            //     weight: .semibold,
                            //     fill: .gray
                            // )
                            //     .lineLimit(2)
                            //     .padding(.horizontal, 10)
                            //     .padding(.vertical, 6)
                            //     .background(Color.black.opacity(0.6))
                            //     .clipShape(RoundedRectangle(cornerRadius: 8))
                            //     .padding(.leading, 16)
                            //     .padding(.bottom, max(120, geo.size.height * 0.18))
                            // Spacer()
                            outlinedCaption(coordinator.dateLocationText)
                                .padding(.leading, 20)
                                .padding(.bottom, max(110, geo.size.height * 0.16))
                            Spacer()
                        }
                    }
                }

                // if configStore.config.debug && !coordinator.title.isEmpty {
                //     VStack {
                //         Spacer()
                //         HStack {
                //             outlinedCaption(coordinator.title)
                //                 .padding(.leading, 20)
                //                 .padding(.bottom, max(110, geo.size.height * 0.16))
                //             Spacer()
                //         }
                //     }
                // }

                if controlsVisible {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(coordinator.secondsLeftText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.trailing, 8)
                        }
                        .padding(.bottom, 6)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                Rectangle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: proxy.size.width * coordinator.playbackProgress)
                            }
                        }
                        .frame(height: 5)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                        //text
                        HStack(spacing: 10) {
                            if !coordinator.captionText.isEmpty {
                                Text(coordinator.captionText)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            Spacer()

                            if configStore.config.debug {
                                Text(coordinator.statusText)
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            if coordinator.canGoBack {
                                Button {
                                    recordInteraction()
                                    coordinator.goBack()
                                } label: {
                                    Image(systemName: "backward.end.fill")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Back")
                            }

                            Button {
                                recordInteraction()
                                coordinator.togglePlayPause()
                            } label: {
                                Image(systemName: coordinator.playPauseButtonSystemImage())
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Play Pause")

                            Button {
                                recordInteraction()
                                coordinator.skip()
                            } label: {
                                Image(systemName: "forward.end.fill")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Skip")

                            Button {
                                recordInteraction()
                                coordinator.toggleFavorite()
                            } label: {
                                Image(systemName: coordinator.favoriteButtonSystemImage())
                            }
                            .buttonStyle(.bordered)
                            .disabled(coordinator.favoriteUpdateInProgress)
                            .accessibilityLabel(coordinator.favoriteButtonLabel())

                            Button(role: .destructive) {
                                recordInteraction()
                                showHideForeverConfirmation = true
                            } label: {
                                Image(systemName: coordinator.hideButtonSystemImage())
                            }
                            .buttonStyle(.bordered)
                            .disabled(!coordinator.canHideToAlbum || coordinator.hideUpdateInProgress)
                            .accessibilityLabel("Hide Forever")

                            Button {
                                recordInteraction()
                                showInfo.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Info")

                            Button {
                                recordInteraction()
                                showSetup = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Settings")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 0)
                    }
                    .transition(.opacity)
                }

                if showInfo {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                Button {
                                    showInfo = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                            }

                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            if let image = qrImage(from: coordinator.currentImmichAssetURL) {
                                                HStack {
                                                    Spacer()
                                                    Image(uiImage: image)
                                                        .interpolation(.none)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(width: 180, height: 180)
                                                    Spacer()
                                                }
                                            }
                                            if !coordinator.currentImmichAssetURL.isEmpty {
                                                Text(coordinator.currentImmichAssetURL)
                                                    .font(.caption2.monospaced())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .id("row-0")

                                        Text("Metadata")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        ForEach(Array(coordinator.currentInfoFields.enumerated()), id: \.element.id) { index, field in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(field.label)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Text(field.value)
                                                    .font(.body.monospaced())
                                            }
                                            .padding(.vertical, 4)
                                            .id("row-\(index + 1)")
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                                }
                                .onChange(of: infoScrollIndex) { next in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        proxy.scrollTo("row-\(next)", anchor: .top)
                                    }
                                }
                            }
                        }
                        .frame(width: geo.size.width * 0.5, height: geo.size.height)
                        .background(Color.black.opacity(0.45))
                    }
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .onAppear {
            coordinator.start()
            recordInteraction()
        }
        .onDisappear {
            coordinator.stop()
            hideControlsTask?.cancel()
        }
        .onChange(of: configStore.config) { _ in
            coordinator.restart()
        }
        .onChange(of: coordinator.shouldOpenSetup) { shouldOpen in
            guard shouldOpen else { return }
            showSetup = true
            coordinator.acknowledgeSetupOpenRequest()
        }
        .onChange(of: showInfo) { isVisible in
            if isVisible {
                infoScrollIndex = 0
            }
            recordInteraction()
            refreshInputAnchorFocus()
        }
        .onChange(of: showSetup) { isPresented in
            if isPresented {
                if !coordinator.isPlaybackPaused {
                    coordinator.togglePlayPause()
                    shouldResumeAfterSettings = true
                } else {
                    shouldResumeAfterSettings = false
                }
            } else if shouldResumeAfterSettings, coordinator.isPlaybackPaused {
                coordinator.togglePlayPause()
                shouldResumeAfterSettings = false
            }
            if !isPresented {
                coordinator.clearDebugMessages()
            }
            recordInteraction()
            refreshInputAnchorFocus()
        }
        .onChange(of: controlsVisible) { _ in
            refreshInputAnchorFocus()
        }
        .onChange(of: configStore.config.debug) { debugEnabled in
            if !debugEnabled {
                coordinator.clearDebugMessages()
            }
        }
        .onExitCommand {
            recordInteraction()
            if showInfo {
                showInfo = false
            }
        }
        .onPlayPauseCommand {
            recordInteraction()
            if !showSetup {
                coordinator.togglePlayPause()
            }
        }
        .onTapGesture {
            recordInteraction()
        }
        .onMoveCommand { direction in
            recordInteraction()
            guard showInfo else { return }
            let maxIndex = coordinator.currentInfoFields.count
            switch direction {
            case .down:
                infoScrollIndex = min(maxIndex, infoScrollIndex + 1)
            case .up:
                infoScrollIndex = max(0, infoScrollIndex - 1)
            default:
                break
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupView(onForceSync: {
                coordinator.forceSyncNow()
            },
            onResetPlaybackProgress: {
                coordinator.resetPlaybackProgress()
            },
            onRefreshStats: {
                coordinator.refreshLibraryStats()
            },
            syncIsSyncing: Binding(get: { coordinator.isSyncing }, set: { _ in }),
            syncPagesFetched: Binding(get: { coordinator.syncPagesFetched }, set: { _ in }),
            syncRowsUpserted: Binding(get: { coordinator.syncRowsUpserted }, set: { _ in }),
            syncLastSyncAt: Binding(get: { coordinator.syncLastSyncAt }, set: { _ in }),
            syncLastError: Binding(get: { coordinator.syncLastError }, set: { _ in }),
            statsTotalVideos: Binding(get: { coordinator.statsTotalVideos }, set: { _ in }),
            statsTotalWatchedPlays: Binding(get: { coordinator.statsTotalWatchedPlays }, set: { _ in }),
            statsWatchedPlays7Days: Binding(get: { coordinator.statsWatchedPlays7Days }, set: { _ in }),
            statsWatchedPlays30Days: Binding(get: { coordinator.statsWatchedPlays30Days }, set: { _ in }),
            statsVideosWatchedAtLeastOnce: Binding(get: { coordinator.statsVideosWatchedAtLeastOnce }, set: { _ in }),
            statsFavoritesCount: Binding(get: { coordinator.statsFavoritesCount }, set: { _ in }),
            statsHiddenCount: Binding(get: { coordinator.statsHiddenCount }, set: { _ in }),
            sessionVideosWatchedCount: Binding(get: { coordinator.sessionVideosWatchedCount }, set: { _ in }),
            statsMostPopularCamera: Binding(get: { coordinator.statsMostPopularCamera }, set: { _ in }),
            statsMostPopularCodec: Binding(get: { coordinator.statsMostPopularCodec }, set: { _ in }),
            statsMostPopularFileType: Binding(get: { coordinator.statsMostPopularFileType }, set: { _ in }),
            statsMostPopularPlace: Binding(get: { coordinator.statsMostPopularPlace }, set: { _ in }),
            statsMostPopularYear: Binding(get: { coordinator.statsMostPopularYear }, set: { _ in }),
            statsTopCamerasSummary: Binding(get: { coordinator.statsTopCamerasSummary }, set: { _ in }),
            statsTopCodecsSummary: Binding(get: { coordinator.statsTopCodecsSummary }, set: { _ in }),
            statsTopFileTypesSummary: Binding(get: { coordinator.statsTopFileTypesSummary }, set: { _ in }),
            statsTopPlacesSummary: Binding(get: { coordinator.statsTopPlacesSummary }, set: { _ in }),
            statsTopYearsSummary: Binding(get: { coordinator.statsTopYearsSummary }, set: { _ in }),
            statsLastError: Binding(get: { coordinator.statsLastError }, set: { _ in }),
            playbackError: Binding(get: { coordinator.setupErrorMessage }, set: { coordinator.setupErrorMessage = $0 }))
                .environmentObject(configStore)
        }
        .alert("Hide Forever?", isPresented: $showHideForeverConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Hide Forever", role: .destructive) {
                recordInteraction()
                coordinator.hideCurrentVideo()
            }
        } message: {
            Text("Are you sure? This hides the video in Immich too. The only way to unhide it is via the web interface.")
        }
    }

    @ViewBuilder
    private func outlinedCaption(_ text: String) -> some View {
        outlinedText(text, fontSize: 34, weight: .heavy, fill: .white)
    }

    @ViewBuilder
    private func outlinedText(
        _ text: String,
        fontSize: CGFloat,
        weight: Font.Weight,
        fill: Color
    ) -> some View {
        let base = Text(text)
            .font(.system(size: fontSize, weight: weight))
            .multilineTextAlignment(.leading)
            .lineSpacing(2)

        ZStack {
            base.foregroundColor(.black).offset(x: -1.2, y: -1.2)
            base.foregroundColor(.black).offset(x: 1.2, y: -1.2)
            base.foregroundColor(.black).offset(x: -1.2, y: 1.2)
            base.foregroundColor(.black).offset(x: 1.2, y: 1.2)
            base.foregroundColor(.black).offset(x: 0, y: 1.6)
            base.foregroundColor(.black).offset(x: 0, y: -1.6)
            base.foregroundColor(fill)
        }
    }

    private func recordInteraction() {
        showControls()
        hideControlsTask?.cancel()
        guard !showInfo, !showSetup else { return }

        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, !showInfo, !showSetup else { return }
            hideControls()
        }
    }

    private func showControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
    }

    private func hideControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = false
        }
    }

    private func refreshInputAnchorFocus() {
        inputAnchorFocused = !controlsVisible && !showInfo && !showSetup
    }

    private func qrImage(from value: String) -> UIImage? {
        guard !value.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct PlayerSurfaceView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceUIView {
        let view = PlayerSurfaceUIView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerSurfaceUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

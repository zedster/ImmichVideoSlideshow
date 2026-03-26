import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

fileprivate struct ChannelOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}

struct ChannelView: View {
    private enum ControlsFocusTarget: Hashable {
        case back
        case playPause
        case skip
        case favorite
        case hideForever
        case info
        case settings
    }

    @ObservedObject private var configStore: ConfigStore
    @StateObject private var coordinator: ChannelCoordinator
    @State private var showSetup = false
    @State private var showInfo = false
    @State private var showChannelList = false
    @State private var shouldResumeAfterSettings = false
    @State private var infoScrollIndex = 0
    @State private var controlsVisible = true
    @State private var scrubBarFocused = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showHideForeverConfirmation = false
    @FocusState private var inputAnchorFocused: Bool
    @FocusState private var focusedControl: ControlsFocusTarget?
    @FocusState private var focusedChannelID: String?
    @State private var lastFocusedControl: ControlsFocusTarget = .playPause

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
                        .padding(.bottom, 0)

                        if scrubBarFocused && !showChannelList {
                            Text("Press Up for Channels")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.84))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .padding(.bottom, 8)
                        }

                        ScrubProgressBar(progress: coordinator.playbackProgress) { deltaSeconds in
                            recordInteraction()
                            coordinator.seek(bySeconds: deltaSeconds)
                        } onOpenChannels: {
                            recordInteraction()
                            openChannelList()
                        } onFocusChange: { isFocused in
                            scrubBarFocused = isFocused
                        }
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
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(coordinator.statusText)
                                        .font(.caption2.monospaced())

                                    if !coordinator.debugTelemetryText.isEmpty {
                                        Text(coordinator.debugTelemetryText)
                                            .font(.caption2.monospaced())
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
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
                                .focused($focusedControl, equals: .back)
                                .accessibilityLabel("Back")
                            }

                            Button {
                                recordInteraction()
                                coordinator.togglePlayPause()
                            } label: {
                                Image(systemName: coordinator.playPauseButtonSystemImage())
                            }
                            .buttonStyle(.bordered)
                            .focused($focusedControl, equals: .playPause)
                            .accessibilityLabel("Play Pause")

                            Button {
                                recordInteraction()
                                coordinator.skip()
                            } label: {
                                Image(systemName: "forward.end.fill")
                            }
                            .buttonStyle(.bordered)
                            .focused($focusedControl, equals: .skip)
                            .accessibilityLabel("Skip")

                            Button {
                                recordInteraction()
                                coordinator.toggleFavorite()
                            } label: {
                                Image(systemName: coordinator.favoriteButtonSystemImage())
                            }
                            .buttonStyle(.bordered)
                            .disabled(coordinator.favoriteUpdateInProgress)
                            .focused($focusedControl, equals: .favorite)
                            .accessibilityLabel(coordinator.favoriteButtonLabel())

                            Button(role: .destructive) {
                                recordInteraction()
                                showHideForeverConfirmation = true
                            } label: {
                                Image(systemName: coordinator.hideButtonSystemImage())
                            }
                            .buttonStyle(.bordered)
                            .disabled(!coordinator.canHideToAlbum || coordinator.hideUpdateInProgress)
                            .focused($focusedControl, equals: .hideForever)
                            .accessibilityLabel("Hide Forever")

                            Button {
                                recordInteraction()
                                showInfo.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.bordered)
                            .focused($focusedControl, equals: .info)
                            .accessibilityLabel("Info")

                            Button {
                                recordInteraction()
                                showSetup = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(.borderedProminent)
                            .focused($focusedControl, equals: .settings)
                            .accessibilityLabel("Settings")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 0)
                    }
                    .transition(.opacity)
                }

                if showChannelList {
                    HStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.72),
                                Color.black.opacity(0.38),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .ignoresSafeArea()

                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Channels")
                                    .font(.system(size: 38, weight: .bold, design: .rounded))
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(channelOptions) { option in
                                    Button {
                                        selectChannel(option.id)
                                    } label: {
                                        ChannelOptionRow(
                                            option: option,
                                            isSelected: option.id == selectedChannelID
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .focused($focusedChannelID, equals: option.id)
                                }
                            }

                            Text("Press Back to close")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.58))

                            Spacer()
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 28)
                        .frame(width: min(520, geo.size.width * 0.42), height: geo.size.height, alignment: .topLeading)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.09, green: 0.10, blue: 0.13).opacity(0.96),
                                    Color(red: 0.13, green: 0.12, blue: 0.17).opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1)
                        }

                        Spacer()
                    }
                    .ignoresSafeArea()
                    .transition(.move(edge: .leading).combined(with: .opacity))
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
                showChannelList = false
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
            if isPresented {
                showChannelList = false
            }
            recordInteraction()
            refreshInputAnchorFocus()
        }
        .onChange(of: showChannelList) { isVisible in
            if isVisible {
                controlsVisible = true
                focusedChannelID = selectedChannelID
            } else {
                focusedChannelID = nil
            }
            recordInteraction()
            refreshInputAnchorFocus()
        }
        .onChange(of: controlsVisible) { _ in
            refreshInputAnchorFocus()
            if controlsVisible && !showChannelList {
                restoreLastFocusedControl()
            }
        }
        .onChange(of: focusedControl) { target in
            guard let target else { return }
            lastFocusedControl = target
        }
        .onChange(of: configStore.config.debug) { debugEnabled in
            if !debugEnabled {
                coordinator.clearDebugMessages()
            }
        }
        .onExitCommand {
            recordInteraction()
            if showChannelList {
                showChannelList = false
            } else if showInfo {
                showInfo = false
            }
        }
        .onPlayPauseCommand {
            recordInteraction()
            if !showSetup && !showChannelList {
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
            statsTotalVideoDuration: Binding(get: { coordinator.statsTotalVideoDuration }, set: { _ in }),
            statsTotalWatchedPlays: Binding(get: { coordinator.statsTotalWatchedPlays }, set: { _ in }),
            statsTotalWatchedDuration: Binding(get: { coordinator.statsTotalWatchedDuration }, set: { _ in }),
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
        guard !showInfo, !showSetup, !showChannelList else { return }

        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, !showInfo, !showSetup, !showChannelList else { return }
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
        inputAnchorFocused = !controlsVisible && !showInfo && !showSetup && !showChannelList
    }

    private func restoreLastFocusedControl() {
        guard controlsVisible, !showInfo, !showSetup, !showChannelList else { return }
        let target = resolvedFocusTarget(from: lastFocusedControl)
        DispatchQueue.main.async {
            focusedControl = target
        }
    }

    private var channelOptions: [ChannelOption] {
        [
            ChannelOption(
                id: "all",
                title: "All Videos",
                subtitle: "Play everything that matches your normal playback settings."
            ),
            ChannelOption(
                id: "favorites",
                title: "Favorites",
                subtitle: "Only play videos marked as favorite in Immich."
            ),
            ChannelOption(
                id: "this_month",
                title: "In This Month (\(currentMonthShortName))",
                subtitle: "Play videos filmed in this calendar month across all years."
            )
        ]
    }

    private var selectedChannelID: String {
        if configStore.config.onlyThisMonth {
            return "this_month"
        }
        if configStore.config.onlyFavorites {
            return "favorites"
        }
        return "all"
    }

    private var currentMonthShortName: String {
        DateFormatter.channelMonthDisplayFormatter.string(from: Date())
    }

    private func openChannelList() {
        showInfo = false
        showChannelList = true
    }

    private func selectChannel(_ channelID: String) {
        guard channelID != selectedChannelID else {
            showChannelList = false
            return
        }

        var nextConfig = configStore.config
        nextConfig.onlyFavorites = (channelID == "favorites")
        nextConfig.onlyThisMonth = (channelID == "this_month")
        configStore.save(nextConfig)
        showChannelList = false
    }

    private func resolvedFocusTarget(from target: ControlsFocusTarget) -> ControlsFocusTarget {
        switch target {
        case .back:
            return coordinator.canGoBack ? .back : .playPause
        case .favorite:
            return coordinator.favoriteUpdateInProgress ? .playPause : .favorite
        case .hideForever:
            return (coordinator.canHideToAlbum && !coordinator.hideUpdateInProgress) ? .hideForever : .favorite
        case .playPause, .skip, .info, .settings:
            return target
        }
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

private extension DateFormatter {
    static let channelMonthDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

private struct ChannelOptionRow: View {
    let option: ChannelOption
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(iconBackground)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: isSelected ? "play.fill" : "tv.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(iconForeground)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(option.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                Text(option.subtitle)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.72) : Color.white.opacity(0.68))
                    .lineLimit(3)
            }

            Spacer(minLength: 12)

            if isSelected {
                Text("Live")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isFocused ? Color.white : Color.white.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .scaleEffect(isFocused ? 1.035 : 1.0)
        .shadow(color: Color.black.opacity(isFocused ? 0.45 : 0.18), radius: isFocused ? 24 : 10, y: isFocused ? 10 : 4)
        .animation(.easeInOut(duration: 0.16), value: isFocused)
    }

    private var cardBackground: some ShapeStyle {
        if isFocused {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.94),
                        Color.white.opacity(0.86)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.09)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color.white.opacity(0.07))
    }

    private var borderColor: Color {
        if isFocused {
            return Color.white.opacity(0.95)
        }
        if isSelected {
            return Color.white.opacity(0.22)
        }
        return Color.white.opacity(0.08)
    }

    private var titleColor: Color {
        isFocused ? .black : .white
    }

    private var iconBackground: Color {
        if isFocused {
            return Color.black.opacity(0.10)
        }
        return isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.10)
    }

    private var iconForeground: Color {
        isFocused ? .black : .white
    }
}

private struct ScrubProgressBar: View {
    private let focusedTint = Color(red: 0.78, green: 0.12, blue: 0.34)

    let progress: Double
    let onStep: (Double) -> Void
    let onOpenChannels: () -> Void
    let onFocusChange: (Bool) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let clamped = max(0, min(1, progress))
                let knobX = proxy.size.width * clamped
                let knobSize: CGFloat = isFocused ? 22 : 14

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 8)
                        Capsule()
                            .fill(isFocused ? focusedTint : Color.white)
                            .frame(width: knobX, height: 8)

                        Circle()
                            .fill(Color.white)
                            .frame(width: knobSize, height: knobSize)
                            .shadow(color: Color.white.opacity(isFocused ? 0.85 : 0), radius: 8)
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(isFocused ? 1.0 : 0), lineWidth: 2)
                            }
                            .offset(x: max(0, min(proxy.size.width - knobSize, knobX - (knobSize / 2))))
                    }
                    .offset(y: 24)
                }
            }
            .frame(height: 52)
            .padding(.vertical, 2)
        }
        .focusable(true)
        .focused($isFocused)
        .onMoveCommand { direction in
            if isFocused {
                switch direction {
                case .left:
                    onStep(-10)
                case .right:
                    onStep(10)
                case .up:
                    onOpenChannels()
                default:
                    break
                }
            }
        }
        .onChange(of: isFocused) { focused in
            onFocusChange(focused)
        }
        .accessibilityLabel("Scrub Position")
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

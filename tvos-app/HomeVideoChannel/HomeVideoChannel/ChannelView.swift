import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

fileprivate struct ChannelOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let count: Int
    let artworkURL: URL?
    let fallbackSymbol: String
}

fileprivate enum ChannelSelectorTab: String, CaseIterable, Hashable, Identifiable {
    case timePlace
    case albums
    case people

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timePlace:
            return "Time & Place"
        case .albums:
            return "Albums"
        case .people:
            return "People"
        }
    }
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
    @State private var channelCounts: [String: Int] = [:]
    @State private var albumChannelOptions: [ChannelOption] = []
    @State private var peopleChannelOptions: [ChannelOption] = []
    @State private var selectedChannelTab: ChannelSelectorTab = .timePlace
    @State private var channelDataTask: Task<Void, Never>?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showHideForeverConfirmation = false
    @FocusState private var inputAnchorFocused: Bool
    @FocusState private var focusedControl: ControlsFocusTarget?
    @FocusState private var focusedChannelID: String?
    @FocusState private var focusedChannelTab: ChannelSelectorTab?
    @State private var lastFocusedControl: ControlsFocusTarget = .playPause
    private let channelStore = SQLiteVideoStore()

    init(configStore: ConfigStore) {
        self._configStore = ObservedObject(wrappedValue: configStore)
        _coordinator = StateObject(wrappedValue: ChannelCoordinator(configStore: configStore))
    }

    var body: some View {
        GeometryReader { geo in
            mainContent(in: geo)
        }
    }

    @ViewBuilder
    private func mainContent(in geo: GeometryProxy) -> some View {
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

                controlsOverlay
                channelListOverlay(in: geo)
                infoOverlay(in: geo)
        }
        .onAppear {
            coordinator.start()
            recordInteraction()
        }
        .onDisappear {
            coordinator.stop()
            hideControlsTask?.cancel()
            channelDataTask?.cancel()
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
                focusedControl = nil
                scrubBarFocused = false
                selectedChannelTab = resolvedSelectedChannelTab
                focusedChannelTab = resolvedSelectedChannelTab
                focusSelectedChannel()
                refreshChannelData()
            } else {
                focusedChannelID = nil
                focusedChannelTab = nil
                channelDataTask?.cancel()
            }
            recordInteraction()
            refreshInputAnchorFocus()
        }
        .onChange(of: coordinator.currentCaptureDateRaw) { _ in
            guard showChannelList else { return }
            refreshChannelData()
        }
        .onChange(of: coordinator.currentPlaceCity) { _ in
            guard showChannelList else { return }
            refreshChannelData()
        }
        .onChange(of: coordinator.currentPlaceCountry) { _ in
            guard showChannelList else { return }
            refreshChannelData()
        }
        .onChange(of: selectedChannelTab) { _ in
            guard showChannelList else { return }
            focusFirstOptionInSelectedTab()
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
    private var controlsOverlay: some View {
        if controlsVisible && !showChannelList {
            controlsOverlayContent()
                .transition(AnyTransition.opacity)
        }
    }

    private func controlsOverlayContent() -> some View {
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

            controlsToolbarRow
        }
    }

    private var controlsToolbarRow: some View {
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

    @ViewBuilder
    private func channelListOverlay(in geo: GeometryProxy) -> some View {
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
                        Text("Swipe left and right to switch tabs, then up and down to pick a channel.")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                    }

                    HStack(spacing: 12) {
                        ForEach(ChannelSelectorTab.allCases) { tab in
                            Button {
                                selectedChannelTab = tab
                                focusedChannelTab = tab
                            } label: {
                                ChannelTabButton(
                                    title: tab.title,
                                    isSelected: tab == selectedChannelTab
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedChannelTab, equals: tab)
                        }
                    }

                    ScrollView {
                        if channelOptionsForSelectedTab.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(emptyStateTitle)
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                Text(emptyStateSubtitle)
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                            .padding(.top, 14)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(channelOptionsForSelectedTab) { option in
                                    Button {
                                        selectChannel(option.id)
                                    } label: {
                                        ChannelOptionRow(
                                            option: option,
                                            isSelected: option.id == selectedChannelID,
                                            apiKey: configStore.config.apiKey
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .focused($focusedChannelID, equals: option.id)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 10)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onMoveCommand { direction in
                        switch direction {
                        case .left:
                            moveSelectedChannelTab(-1)
                        case .right:
                            moveSelectedChannelTab(1)
                        default:
                            break
                        }
                    }

                    Text("Press Back to close")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))

                    Spacer()
                }
                .focusSection()
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(width: min(720, geo.size.width * 0.42), height: geo.size.height, alignment: .topLeading)
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
    }

    @ViewBuilder
    private func infoOverlay(in geo: GeometryProxy) -> some View {
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

    private var timePlaceChannelOptions: [ChannelOption] {
        var options: [ChannelOption] = [
            ChannelOption(
                id: "all",
                title: "All Videos",
                subtitle: "Play everything that matches your normal playback settings.",
                count: channelCount(for: "all"),
                artworkURL: nil,
                fallbackSymbol: "tv.fill"
            ),
            ChannelOption(
                id: "favorites",
                title: "Favorites",
                subtitle: "Only play videos marked as favorite in Immich.",
                count: channelCount(for: "favorites"),
                artworkURL: nil,
                fallbackSymbol: "heart.fill"
            ),
            ChannelOption(
                id: "this_month",
                title: "In This Month (\(currentMonthShortName))",
                subtitle: "Play videos filmed in this calendar month across all years.",
                count: channelCount(for: "this_month"),
                artworkURL: nil,
                fallbackSymbol: "calendar"
            )
        ]

        if hasCurrentCaptureDate {
            options.append(
                ChannelOption(
                    id: "this_day",
                    title: "More On This Day",
                    subtitle: "Play videos filmed on this calendar day across all years.",
                    count: channelCount(for: "this_day"),
                    artworkURL: nil,
                    fallbackSymbol: "calendar.badge.clock"
                )
            )
            options.append(
                ChannelOption(
                    id: "this_week",
                    title: "More On This Week",
                    subtitle: "Play videos filmed in this week of the year across all years.",
                    count: channelCount(for: "this_week"),
                    artworkURL: nil,
                    fallbackSymbol: "calendar.badge.exclamationmark"
                )
            )
        }

        if !coordinator.currentPlaceCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options.append(
                ChannelOption(
                    id: "place_city",
                    title: "Place (\(shortBracketLabel(coordinator.currentPlaceCity)))",
                    subtitle: "Play more videos from this place.",
                    count: channelCount(for: "place_city"),
                    artworkURL: nil,
                    fallbackSymbol: "mappin.and.ellipse"
                )
            )
        }

        if !coordinator.currentPlaceCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options.append(
                ChannelOption(
                    id: "place_country",
                    title: "Country (\(shortBracketLabel(coordinator.currentPlaceCountry)))",
                    subtitle: "Play more videos from this country.",
                    count: channelCount(for: "place_country"),
                    artworkURL: nil,
                    fallbackSymbol: "globe.europe.africa"
                )
            )
        }

        return options
    }

    private var channelOptionsForSelectedTab: [ChannelOption] {
        switch selectedChannelTab {
        case .timePlace:
            return timePlaceChannelOptions
        case .albums:
            return albumChannelOptions
        case .people:
            return peopleChannelOptions
        }
    }

    private var selectedChannelID: String {
        if !configStore.config.albumFilterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "album:\(configStore.config.albumFilterID)"
        }
        if !configStore.config.personFilterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "person:\(configStore.config.personFilterID)"
        }
        if !configStore.config.placeFilterCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "place_city"
        }
        if !configStore.config.placeFilterCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "place_country"
        }
        if configStore.config.onlyThisWeek {
            return "this_week"
        }
        if configStore.config.onlyThisDay {
            return "this_day"
        }
        if configStore.config.onlyThisMonth {
            return "this_month"
        }
        if configStore.config.onlyFavorites {
            return "favorites"
        }
        return "all"
    }

    private var resolvedSelectedChannelTab: ChannelSelectorTab {
        if !configStore.config.albumFilterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .albums
        }
        if !configStore.config.personFilterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .people
        }
        return .timePlace
    }

    private var currentMonthShortName: String {
        DateFormatter.channelMonthDisplayFormatter.string(from: Date())
    }

    private var hasCurrentCaptureDate: Bool {
        !coordinator.currentCaptureDateRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        nextConfig.onlyFavorites = false
        nextConfig.onlyThisMonth = false
        nextConfig.onlyThisDay = false
        nextConfig.onlyThisWeek = false
        nextConfig.referenceCaptureDate = ""
        nextConfig.placeFilterCity = ""
        nextConfig.placeFilterCountry = ""
        nextConfig.albumFilterID = ""
        nextConfig.albumFilterName = ""
        nextConfig.personFilterID = ""
        nextConfig.personFilterName = ""

        switch channelID {
        case "favorites":
            nextConfig.onlyFavorites = true
        case "this_month":
            nextConfig.onlyThisMonth = true
        case "this_day":
            nextConfig.onlyThisDay = true
            nextConfig.referenceCaptureDate = coordinator.currentCaptureDateRaw
        case "this_week":
            nextConfig.onlyThisWeek = true
            nextConfig.referenceCaptureDate = coordinator.currentCaptureDateRaw
        case "place_city":
            nextConfig.placeFilterCity = coordinator.currentPlaceCity.trimmingCharacters(in: .whitespacesAndNewlines)
        case "place_country":
            nextConfig.placeFilterCountry = coordinator.currentPlaceCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value where value.hasPrefix("album:"):
            let albumID = String(value.dropFirst("album:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let option = albumChannelOptions.first(where: { $0.id == channelID }), !albumID.isEmpty {
                nextConfig.albumFilterID = albumID
                nextConfig.albumFilterName = option.title
            }
        case let value where value.hasPrefix("person:"):
            let personID = String(value.dropFirst("person:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let option = peopleChannelOptions.first(where: { $0.id == channelID }), !personID.isEmpty {
                nextConfig.personFilterID = personID
                nextConfig.personFilterName = option.title
            }
        default:
            break
        }
        configStore.save(nextConfig)
        showChannelList = false
    }

    private func channelCount(for id: String) -> Int {
        channelCounts[id] ?? 0
    }

    private func shortBracketLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstPart = trimmed.split(separator: ",").first.map(String.init) ?? trimmed
        return String(firstPart.prefix(14))
    }

    private func albumArtworkURL(for assetID: String) -> URL? {
        let trimmed = assetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return URL(string: "\(configStore.config.normalizedImmichBaseURL)/api/assets/\(encoded)/thumbnail")
    }

    private func personArtworkURL(for personID: String) -> URL? {
        let trimmed = personID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return URL(string: "\(configStore.config.normalizedImmichBaseURL)/api/people/\(encoded)/thumbnail")
    }

    private func focusSelectedChannel() {
        DispatchQueue.main.async {
            focusedChannelID = selectedChannelID
        }
    }

    private func focusFirstOptionInSelectedTab() {
        let options = channelOptionsForSelectedTab
        let targetID = options.first(where: { $0.id == selectedChannelID })?.id ?? options.first?.id
        DispatchQueue.main.async {
            focusedChannelID = targetID
        }
    }

    private var emptyStateTitle: String {
        switch selectedChannelTab {
        case .timePlace:
            return "No channel options"
        case .albums:
            return "No album channels yet"
        case .people:
            return "No people channels yet"
        }
    }

    private var emptyStateSubtitle: String {
        switch selectedChannelTab {
        case .timePlace:
            return "Play a video first to unlock time and place shortcuts."
        case .albums:
            return "Run a sync to load Immich albums that contain videos."
        case .people:
            return "Run a sync to load named people from your synced videos."
        }
    }

    private func moveSelectedChannelTab(_ offset: Int) {
        let tabs = ChannelSelectorTab.allCases
        guard let currentIndex = tabs.firstIndex(of: selectedChannelTab) else { return }
        let nextIndex = max(0, min(tabs.count - 1, currentIndex + offset))
        guard nextIndex != currentIndex else { return }
        let nextTab = tabs[nextIndex]
        selectedChannelTab = nextTab
        focusedChannelTab = nextTab
    }

    private func refreshChannelData() {
        channelDataTask?.cancel()
        channelDataTask = Task { @MainActor in
            var nextCounts: [String: Int] = [:]
            try? await channelStore.initializeSchema()

            nextCounts["all"] = (try? await channelStore.countQualifying(
                minDuration: configStore.config.minDuration,
                onlyFavorites: false,
                onlyThisMonth: false,
                onlyThisDay: false,
                onlyThisWeek: false,
                referenceCaptureDate: "",
                placeCity: "",
                placeCountry: "",
                albumID: "",
                personID: ""
            )) ?? 0

            nextCounts["favorites"] = (try? await channelStore.countQualifying(
                minDuration: configStore.config.minDuration,
                onlyFavorites: true,
                onlyThisMonth: false,
                onlyThisDay: false,
                onlyThisWeek: false,
                referenceCaptureDate: "",
                placeCity: "",
                placeCountry: "",
                albumID: "",
                personID: ""
            )) ?? 0

            nextCounts["this_month"] = (try? await channelStore.countQualifying(
                minDuration: configStore.config.minDuration,
                onlyFavorites: false,
                onlyThisMonth: true,
                onlyThisDay: false,
                onlyThisWeek: false,
                referenceCaptureDate: "",
                placeCity: "",
                placeCountry: "",
                albumID: "",
                personID: ""
            )) ?? 0

            if hasCurrentCaptureDate {
                nextCounts["this_day"] = (try? await channelStore.countQualifying(
                    minDuration: configStore.config.minDuration,
                    onlyFavorites: false,
                    onlyThisMonth: false,
                    onlyThisDay: true,
                    onlyThisWeek: false,
                    referenceCaptureDate: coordinator.currentCaptureDateRaw,
                    placeCity: "",
                    placeCountry: "",
                    albumID: "",
                    personID: ""
                )) ?? 0

                nextCounts["this_week"] = (try? await channelStore.countQualifying(
                    minDuration: configStore.config.minDuration,
                    onlyFavorites: false,
                    onlyThisMonth: false,
                    onlyThisDay: false,
                    onlyThisWeek: true,
                    referenceCaptureDate: coordinator.currentCaptureDateRaw,
                    placeCity: "",
                    placeCountry: "",
                    albumID: "",
                    personID: ""
                )) ?? 0
            }

            if !coordinator.currentPlaceCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nextCounts["place_city"] = (try? await channelStore.countQualifying(
                    minDuration: configStore.config.minDuration,
                    onlyFavorites: false,
                    onlyThisMonth: false,
                    onlyThisDay: false,
                    onlyThisWeek: false,
                    referenceCaptureDate: "",
                    placeCity: coordinator.currentPlaceCity,
                    placeCountry: "",
                    albumID: "",
                    personID: ""
                )) ?? 0
            }

            if !coordinator.currentPlaceCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nextCounts["place_country"] = (try? await channelStore.countQualifying(
                    minDuration: configStore.config.minDuration,
                    onlyFavorites: false,
                    onlyThisMonth: false,
                    onlyThisDay: false,
                    onlyThisWeek: false,
                    referenceCaptureDate: "",
                    placeCity: "",
                    placeCountry: coordinator.currentPlaceCountry,
                    albumID: "",
                    personID: ""
                )) ?? 0
            }

            let nextAlbumOptions = ((try? await channelStore.listAlbumChannels(minDuration: configStore.config.minDuration)) ?? []).map {
                ChannelOption(
                    id: "album:\($0.id)",
                    title: $0.title,
                    subtitle: "Play videos from this album.",
                    count: $0.count,
                    artworkURL: albumArtworkURL(for: $0.artworkID),
                    fallbackSymbol: "photo.on.rectangle.angled"
                )
            }

            let nextPeopleOptions = ((try? await channelStore.listPeopleChannels(minDuration: configStore.config.minDuration)) ?? []).map {
                ChannelOption(
                    id: "person:\($0.id)",
                    title: $0.title,
                    subtitle: "Play videos featuring this person.",
                    count: $0.count,
                    artworkURL: personArtworkURL(for: $0.artworkID),
                    fallbackSymbol: "person.crop.circle.fill"
                )
            }

            guard !Task.isCancelled else { return }
            channelCounts = nextCounts
            albumChannelOptions = nextAlbumOptions
            peopleChannelOptions = nextPeopleOptions
            focusFirstOptionInSelectedTab()
        }
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

private struct ChannelTabButton: View {
    let title: String
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(background)
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
            }
            .clipShape(Capsule())
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 0.16), value: isFocused)
    }

    private var background: some ShapeStyle {
        if isFocused {
            return AnyShapeStyle(Color.white)
        }
        if isSelected {
            return AnyShapeStyle(Color.white.opacity(0.14))
        }
        return AnyShapeStyle(Color.white.opacity(0.07))
    }

    private var borderColor: Color {
        if isFocused {
            return Color.white.opacity(0.95)
        }
        if isSelected {
            return Color.white.opacity(0.28)
        }
        return Color.white.opacity(0.08)
    }
}

@MainActor
private final class AuthenticatedRemoteImageLoader: ObservableObject {
    @Published var image: UIImage?

    private var task: Task<Void, Never>?
    private var loadedSignature: String = ""

    func load(url: URL?, apiKey: String) {
        let signature = "\(url?.absoluteString ?? "")|\(apiKey)"
        guard signature != loadedSignature else { return }
        loadedSignature = signature
        task?.cancel()
        image = nil

        guard let url, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        task = Task {
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, let image = UIImage(data: data) else { return }
                self.image = image
            } catch {
                if Task.isCancelled { return }
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

private struct ChannelOptionArtwork: View {
    let imageURL: URL?
    let apiKey: String
    let fallbackSymbol: String
    let backgroundColor: Color
    let foregroundColor: Color

    @StateObject private var loader = AuthenticatedRemoteImageLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
                .frame(width: 52, height: 52)

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(foregroundColor)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .onAppear {
            loader.load(url: imageURL, apiKey: apiKey)
        }
        .onChange(of: imageURL) { next in
            loader.load(url: next, apiKey: apiKey)
        }
        .onChange(of: apiKey) { next in
            loader.load(url: imageURL, apiKey: next)
        }
    }
}

private struct ChannelOptionRow: View {
    let option: ChannelOption
    let isSelected: Bool
    let apiKey: String

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ChannelOptionArtwork(
                imageURL: option.artworkURL,
                apiKey: apiKey,
                fallbackSymbol: isSelected ? "play.fill" : option.fallbackSymbol,
                backgroundColor: iconBackground,
                foregroundColor: iconForeground
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(option.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(2)

                    Text("\(option.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(countTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(countBackground)
                        .clipShape(Capsule())
                }

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
                        Color.white.opacity(0.96),
                        Color.white.opacity(0.88)
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
                        Color(red: 0.96, green: 0.34, blue: 0.48).opacity(0.78),
                        Color(red: 0.74, green: 0.12, blue: 0.28).opacity(0.68)
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
            return Color(red: 1.0, green: 0.72, blue: 0.78).opacity(0.95)
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
        return isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.10)
    }

    private var iconForeground: Color {
        isFocused ? .black : .white
    }

    private var countBackground: Color {
        if isFocused {
            return Color.black.opacity(0.12)
        }
        return isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.10)
    }

    private var countTextColor: Color {
        isFocused ? Color.black.opacity(0.78) : Color.white.opacity(0.92)
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

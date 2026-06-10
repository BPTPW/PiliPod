//
//  LivePlaybackPage.swift
//  PiliPod
//
//  Created by Codex on 2026/6/8.
//

import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LivePlaybackPage: View {
    let room: LiveCardModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LivePlaybackViewModel
    @State private var player = MPVKitPlayer()
    @State private var playerUISnapshot = PlayerUIPlaybackSnapshot()
    @State private var shouldResumeAfterBackgroundPause = false
    @State private var mediaControlSyncTask: Task<Void, Never>?
#if canImport(UIKit)
    @StateObject private var audioSessionManager = VideoPlaybackAudioSessionManager()
#endif

    init(room: LiveCardModel) {
        self.room = room
        _viewModel = State(initialValue: LivePlaybackViewModel(room: room))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                liveBackground

                VStack(spacing: 0) {
                    headerBar(topInset: geo.safeAreaInsets.top)

                    LivePlayerView(
                        roomId: room.roomId,
                        streamURL: viewModel.streamURL,
                        aspectRatio: viewModel.aspectRatio,
                        statusText: viewModel.playerStatusText,
                        player: player
                    )
                    .frame(width: geo.size.width)
                    .onAppear {
                        playerUISnapshot = player.uiSnapshot
                    }
                    .onChange(of: player.uiSnapshot) { oldSnapshot, snapshot in
                        playerUISnapshot = snapshot
#if canImport(UIKit)
                        if oldSnapshot.isPlaying != snapshot.isPlaying {
                            syncSystemMediaControl()
                        }
#endif
                    }

                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(viewModel.displayTitle)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)

                                HStack(spacing: 8) {
                                    if !viewModel.displayOnlineCount.isEmpty {
                                        Label(viewModel.displayOnlineCount, systemImage: "eye.fill")
                                    }

                                    Text("房间号 \(room.roomId)")
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.78))
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 16)

                            LiveDanmakuListView(messages: viewModel.messages)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(.bottom, 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        Color.clear
                            .frame(width: 24)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 12)
                                    .onEnded { value in
                                        let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                                        guard isHorizontal, value.translation.width > 80 else { return }
                                        dismiss()
                                    }
                            )
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Color.black)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
#if canImport(UIKit)
            configureAudioSessionHandlers()
            startMediaControlSyncLoopIfNeeded()
#endif
            await viewModel.loadPlaybackIfNeeded()
#if canImport(UIKit)
            audioSessionManager.activate()
            syncSystemMediaControl()
            if viewModel.streamURL != nil {
                Task { await syncSystemMediaControlWhenPlaybackStarts() }
            }
#endif
        }
        .onDisappear {
            mediaControlSyncTask?.cancel()
            mediaControlSyncTask = nil
            player.pause()
#if canImport(UIKit)
            audioSessionManager.deactivate()
#endif
            viewModel.teardown()
        }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification
        )) { _ in
            handleDidEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            handleDidBecomeActive()
        }
#endif
        .onChange(of: viewModel.streamURL) { _, newValue in
#if canImport(UIKit)
            guard newValue != nil else { return }
            Task { await syncSystemMediaControlWhenPlaybackStarts() }
#endif
        }
        .onChange(of: viewModel.displayTitle) { _, _ in
#if canImport(UIKit)
            syncSystemMediaControl()
#endif
        }
        .onChange(of: viewModel.anchorName) { _, _ in
#if canImport(UIKit)
            syncSystemMediaControl()
#endif
        }
    }

    private var liveBackground: some View {
        Group {
            if let backgroundURL = viewModel.backgroundURL {
                CachedAsyncImage(url: backgroundURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image("defaultLiveBg")
                            .resizable()
                            .scaledToFill()
                    }
                }
            } else {
                Image("defaultLiveBg")
                    .resizable()
                    .scaledToFill()
            }
        }
        .overlay(Color.black.opacity(0.46))
        .ignoresSafeArea()
    }

    private func headerBar(topInset: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
            }
            .tint(.primary)
            .glassEffect(.regular.interactive(), in: .circle)

            CachedAsyncImage(url: viewModel.faceURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.anchorName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)

                if !viewModel.areaName.isEmpty {
                    Text(viewModel.areaName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, max(topInset, 10))
        .padding(.bottom, 10)
    }

#if canImport(UIKit)
    private func configureAudioSessionHandlers() {
        audioSessionManager.configureHandlers(
            onPlay: {
                resumePlayback()
            },
            onPause: {
                pausePlayback()
            },
            onSeek: { _ in }
        )
    }

    private func syncSystemMediaControl() {
        audioSessionManager.updateNowPlaying(
            info: .init(
                title: viewModel.displayTitle,
                artist: viewModel.anchorName,
                artworkURL: viewModel.coverURL,
                duration: 0,
                elapsedTime: 0,
                playbackRate: 1,
                isPlaying: player.isPlaying,
                isLiveStream: true,
                supportsSeeking: false
            )
        )
    }

    private func syncSystemMediaControlWhenPlaybackStarts() async {
        for _ in 0..<20 {
            let snapshot = player.uiSnapshot
            if snapshot.isPlaying {
                playerUISnapshot = snapshot
                syncSystemMediaControl()
                return
            }
            try? await Task.sleep(nanoseconds: 100000000)
        }
    }

    private func startMediaControlSyncLoopIfNeeded() {
        guard mediaControlSyncTask == nil else { return }

        mediaControlSyncTask = Task { @MainActor in
            while !Task.isCancelled {
                syncSystemMediaControl()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func pausePlayback() {
        player.pause()
        playerUISnapshot = player.uiSnapshot
        syncSystemMediaControl()
    }

    private func resumePlayback() {
        player.resume()
        playerUISnapshot = player.uiSnapshot
        syncSystemMediaControl()
    }

    private func handleDidEnterBackground() {
        let playbackSettings = AudioVideoSettingsStore.load()
        guard !playbackSettings.allowsLiveBackgroundPlayback else { return }

        shouldResumeAfterBackgroundPause = player.isPlaying
        guard shouldResumeAfterBackgroundPause else {
            syncSystemMediaControl()
            return
        }

        pausePlayback()
    }

    private func handleDidBecomeActive() {
        guard shouldResumeAfterBackgroundPause else { return }
        shouldResumeAfterBackgroundPause = false
        resumePlayback()
    }
#endif
}

@Observable
@MainActor
private final class LivePlaybackViewModel {
    let room: LiveCardModel

    var roomInfo: LiveRoomInfo?
    var streamURL: URL?
    var aspectRatio: CGFloat = 16.0 / 9.0
    var messages: [LiveDanmakuMessage] = []
    var isLoading = false
    var errorMessage: String?
    private var hasLoaded = false
    private let danmakuService = LiveDanmakuService()

    init(room: LiveCardModel) {
        self.room = room
        danmakuService.onMessage = { [weak self] message in
            self?.messages.append(message)
        }
    }

    var playerStatusText: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if isLoading {
            return "正在获取直播流..."
        }
        return "room id: \(room.roomId)"
    }

    var displayTitle: String {
        let title = roomInfo?.title ?? room.title
        return title.isEmpty ? "直播间" : title
    }

    var displayOnlineCount: String {
        roomInfo?.onlineCount ?? room.onlineCount
    }

    var anchorName: String {
        let name = roomInfo?.anchorName ?? room.anchorName
        return name.isEmpty ? "主播" : name
    }

    var areaName: String {
        roomInfo?.areaName ?? room.areaName
    }

    var faceURL: URL? {
        URL(string: roomInfo?.faceURL ?? room.faceURL)
    }

    var backgroundURL: URL? {
        guard let value = roomInfo?.backgroundURL, !value.isEmpty else { return nil }
        return URL(string: value)
    }

    var coverURL: URL? {
        if let value = roomInfo?.coverURL, !value.isEmpty {
            return URL(string: value)
        }
        return URL(string: room.coverURL)
    }

    func loadPlaybackIfNeeded() async {
        guard !hasLoaded else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRoomInfo() }
            group.addTask { await self.loadPlayback() }
            group.addTask { await self.loadDanmakuIfNeeded() }
        }
        hasLoaded = true
    }

    func teardown() {
        danmakuService.close()
    }

    private func loadPlayback() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let playback = try await BiliAPI.shared.fetchLivePlaybackInfo(roomID: room.roomId)
            streamURL = playback.streamURL
            aspectRatio = playback.aspectRatio
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRoomInfo() async {
        do {
            roomInfo = try await BiliAPI.shared.fetchLiveRoomInfo(roomID: room.roomId)
        } catch {
            print("fetchLiveRoomInfo failed: \(error.localizedDescription)")
        }
    }

    private func loadDanmakuIfNeeded() async {
        guard let roomID = Int(room.roomId) else { return }
        do {
            messages = try await BiliAPI.shared.fetchLiveDanmakuHistory(roomID: roomID)
        } catch {
            print("fetchLiveDanmakuHistory failed: \(error.localizedDescription)")
        }
        await danmakuService.connect(roomID: roomID)
    }
}

private struct LiveDanmakuListView: View {
    let messages: [LiveDanmakuMessage]

    @State private var autoScrollEnabled = true
    @State private var isAtBottom = true
    private let bottomAnchorID = "live-danmaku-bottom"

    var body: some View {
        GeometryReader { container in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { message in
                                LiveDanmakuRow(message: message)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: LiveDanmakuBottomPreferenceKey.self,
                                        value: geo.frame(in: .named("liveDanmakuScroll")).maxY - container.size.height
                                    )
                            }
                            .frame(height: 1)
                            .id(bottomAnchorID)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .coordinateSpace(name: "liveDanmakuScroll")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { _ in
                                if autoScrollEnabled {
                                    autoScrollEnabled = false
                                }
                            }
                    )
                    .onPreferenceChange(LiveDanmakuBottomPreferenceKey.self) { bottomY in
                        let threshold: CGFloat = 24
                        let newIsAtBottom = bottomY <= threshold
                        isAtBottom = newIsAtBottom
                    }
                    .onChange(of: messages.count) { _, _ in
                        guard autoScrollEnabled else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }

                    if !autoScrollEnabled {
                        Button {
                            autoScrollEnabled = true
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                        }
                        .tint(.primary)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveDanmakuRow: View {
    let message: LiveDanmakuMessage

    var body: some View {
        LiveDanmakuWrappedContent(
            username: message.username,
            segments: message.segments
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct LiveDanmakuWrappedContent: View {
    let username: String
    let segments: [LiveDanmakuSegment]

    var body: some View {
        LiveDanmakuFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
            Text("\(username): ")
                .font(.system(size: 15))
                .foregroundStyle(.teal)

            if segments.isEmpty {
                Text("")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            } else {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        Text(text)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    case .emoticon(let emoticon):
                        LiveDanmakuEmoticonView(emoticon: emoticon)
                    }
                }
            }
        }
    }
}

private struct LiveDanmakuEmoticonView: View {
    let emoticon: LiveDanmakuEmoticon

    var body: some View {
        CachedAsyncImage(url: emoticon.url) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                Text(emoticon.placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: emoticon.width, height: emoticon.height)
        .offset(y: 2)
    }
}

private struct LiveDanmakuFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 0, verticalSpacing: CGFloat = 0) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        return arrangement.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        for item in arrangement.items {
            let origin = CGPoint(
                x: bounds.minX + item.frame.minX,
                y: bounds.minY + item.frame.minY
            )
            subviews[item.index].place(
                at: origin,
                proposal: ProposedViewSize(item.frame.size)
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, items: [LiveDanmakuFlowItem]) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var items: [LiveDanmakuFlowItem] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = size.width
            let itemHeight = size.height
            let nextX = currentX == 0 ? itemWidth : currentX + horizontalSpacing + itemWidth

            if currentX > 0, nextX > maxWidth {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }

            let itemOriginX = currentX == 0 ? 0 : currentX + horizontalSpacing
            let frame = CGRect(x: itemOriginX, y: currentY, width: itemWidth, height: itemHeight)
            items.append(LiveDanmakuFlowItem(index: index, frame: frame))

            currentX = frame.maxX
            lineHeight = max(lineHeight, itemHeight)
            usedWidth = max(usedWidth, frame.maxX)
        }

        let totalHeight = items.isEmpty ? 0 : currentY + lineHeight
        return (CGSize(width: usedWidth, height: totalHeight), items)
    }
}

private struct LiveDanmakuFlowItem {
    let index: Int
    let frame: CGRect
}

private struct LiveDanmakuBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    LivePlaybackPage(
        room: LiveCardModel(
            roomId: "226000",
            title: "实时直播间标题示例",
            coverURL: "https://picsum.photos/400/250",
            onlineCount: "1.2万人气",
            anchorName: "主播昵称",
            faceURL: "https://picsum.photos/80",
            areaName: "手游 · 王者荣耀",
            badgeText: "已关注",
            link: nil
        )
    )
}

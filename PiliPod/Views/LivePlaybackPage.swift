//
//  LivePlaybackPage.swift
//  PiliPod
//
//  Created by Codex on 2026/6/8.
//

import SwiftUI
import Observation

struct LivePlaybackPage: View {
    let room: LiveCardModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LivePlaybackViewModel

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
                        statusText: viewModel.playerStatusText
                    )
                    .frame(width: geo.size.width)

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
            await viewModel.loadPlaybackIfNeeded()
        }
        .onDisappear {
            viewModel.teardown()
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

    func loadPlaybackIfNeeded() async {
        guard !hasLoaded else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRoomInfo() }
            group.addTask { await self.loadPlayback() }
            group.addTask { await self.connectDanmakuIfNeeded() }
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

    private func connectDanmakuIfNeeded() async {
        guard let roomID = Int(room.roomId) else { return }
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
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(message.username): ")
                .foregroundStyle(.mint)
            Text(message.content)
                .foregroundStyle(.white)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
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

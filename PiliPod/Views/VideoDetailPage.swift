//
//  VideoDetailPage.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct VideoDetailPage: View {
    @State var viewModel: VideoDetailViewModel
    @State private var showDebugPanel = false
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isVideoDetailExpanded = false
    @State private var isFavoriteSheetPresented = false
    @State private var favoriteFolders: [FavoriteFolderItem] = []
    @State private var favoriteSelectedIds: Set<Int64> = []
    @State private var favoriteInitiallySelectedIds: Set<Int64> = []
    @State private var favoriteIsLoading = false
    @State private var selectedRelatedVideo: VideoItem?
    @State private var selectedUserSpaceRoute: UserSpaceRoute?
    @State private var isSpeedBoostActive = false
    @State private var speedBoostMultiplier: Double = 2.0
    @State private var isSpeedBoostPressing = false
    @State private var speedBoostTriggerTask: Task<Void, Never>?
    @State private var danmakuConfig = DanmakuConfigStore.load()
    @State private var isDanmakuSettingsPresented = false
    @State private var isFullscreen = false
    @State private var isFullscreenDanmakuPanelVisible = false
    @State private var lastDanmakuPrefetchSegment = 0
    @State private var selectedTab: VideoDetailTab = .intro
    @State private var toastMessage: String?

    let video: VideoItem
    let namespace: Namespace.ID
    let onBack: () -> Void

    private var heroID: String { "videoHero.\(video.bvid)" }

    init(video: VideoItem, namespace: Namespace.ID, onBack: @escaping () -> Void) {
        self.video = video
        self.namespace = namespace
        self.onBack = onBack
        _viewModel = State(initialValue: VideoDetailViewModel(
            bvid: video.bvid,
            cid: video.cid ?? 0,
            title: video.title,
            cover: video.cover
        ))
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    // DASH 播放器
                    if let stream = bindableViewModel.dashStream, let player = bindableViewModel.player {
                        ZStack(alignment: .topLeading) {
                            // DASH 播放器容器
                            MPVKitPlayerView(player: player)
                                .id(bindableViewModel.currentPlayerViewID)
                                .aspectRatio(stream.aspectRatio, contentMode: .fit)
                                .frame(width: isFullscreen ? geo.size.width : nil,
                                       height: isFullscreen ? geo.size.height : nil,
                                       alignment: .center)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .clipped()
                                .ignoresSafeArea(isFullscreen ? .all : [])
                                .background(Color.black)
                                .matchedGeometryEffect(id: heroID, in: namespace)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showControlsAndAutoHideIfNeeded(player: player)
                                }
                                .highPriorityGesture(
                                    TapGesture(count: 2)
                                        .onEnded {
                                            if player.isPlaying {
                                                player.pause()
                                            } else {
                                                player.resume()
                                            }
                                            showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                        }
                                )
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { _ in
                                            if !isSpeedBoostPressing {
                                                isSpeedBoostPressing = true
                                                speedBoostTriggerTask?.cancel()
                                                speedBoostTriggerTask = Task { @MainActor in
                                                    do {
                                                        try await Task.sleep(nanoseconds: 200000000)
                                                    } catch {
                                                        return
                                                    }
                                                    if isSpeedBoostPressing {
                                                        beginSpeedBoostIfNeeded(player: player)
                                                    }
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            isSpeedBoostPressing = false
                                            speedBoostTriggerTask?.cancel()
                                            speedBoostTriggerTask = nil
                                            endSpeedBoostIfNeeded(player: player)
                                        }
                                )
                                .overlay {
                                    DanmakuOverlayView(
                                        currentTime: player.currentTime,
                                        isPlaying: player.isPlaying,
                                        elements: bindableViewModel.danmakuElements,
                                        config: fullscreenAwareDanmakuConfig
                                    )
                                }
                                .overlay {
                                    if isFullscreen && controlsVisible {
                                        VStack(spacing: 0) {
                                            LinearGradient(
                                                colors: [Color.black.opacity(0.65), Color.black.opacity(0)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                            .frame(height: 60 + geo.safeAreaInsets.top / 2)
                                            .frame(maxWidth: .infinity, alignment: .top)

                                            Spacer(minLength: 0)

                                            LinearGradient(
                                                colors: [Color.black.opacity(0), Color.black.opacity(0.68)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                            .frame(height: 65 + geo.safeAreaInsets.bottom / 2)
                                            .frame(maxWidth: .infinity, alignment: .bottom)
                                        }
                                        .ignoresSafeArea()
                                        .allowsHitTesting(false)
                                    }
                                }
                                .overlay {
                                    PlayerControlsOverlay(
                                        showDebugPanel: $showDebugPanel,
                                        onShowDanmakuSettings: {
                                            if isFullscreen {
                                                isFullscreenDanmakuPanelVisible.toggle()
                                            } else {
                                                isDanmakuSettingsPresented = true
                                            }
                                        },
                                        isFullscreen: isFullscreen,
                                        isFullscreenDanmakuPanelVisible: isFullscreenDanmakuPanelVisible,
                                        qualityOptions: bindableViewModel.qualityOptions,
                                        selectedQualityCode: bindableViewModel.selectedQualityCode,
                                        selectedPlaybackRate: bindableViewModel.selectedPlaybackRate,
                                        isVisible: controlsVisible,
                                        currentTime: player.currentTime,
                                        duration: player.duration,
                                        bufferedUntil: player.bufferedUntil,
                                        isPlaying: player.isPlaying,
                                        segments: [],
                                        onBack: { handleBackAction() },
                                        onUserInteracted: {
                                            showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                        },
                                        onTogglePlayPause: {
                                            if player.isPlaying {
                                                player.pause()
                                            } else {
                                                player.resume()
                                            }
                                        },
                                        onSeek: { time in
                                            player.seek(to: time)
                                            Task {
                                                await bindableViewModel.preloadDanmakuIfNeeded(currentTime: time)
                                            }
                                            showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                        },
                                        onFullscreen: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                isFullscreen.toggle()
                                                if !isFullscreen {
                                                    isFullscreenDanmakuPanelVisible = false
                                                }
                                            }
                                            updateDeviceOrientationForFullscreen(
                                                isFullscreen: isFullscreen
                                            )
                                            Task { @MainActor in
                                                await bindableViewModel.rebuildPlayerPreservingState()
                                            }
                                        },
                                        onSelectQuality: { code in
                                            Task { @MainActor in
                                                await bindableViewModel.switchQuality(to: code)
                                            }
                                        },
                                        onSelectPlaybackRate: { rate in
                                            bindableViewModel.setPlaybackRate(rate)
                                        }
                                    )
                                }
                                .overlay(alignment: .trailing) {
                                    if controlsVisible && isFullscreen && isFullscreenDanmakuPanelVisible {
                                        DanmakuSettingsPanel(
                                            config: $danmakuConfig,
                                            onClose: {
                                                isFullscreenDanmakuPanelVisible = false
                                            }
                                        )
                                        .padding(.trailing, 12)
                                        .transition(.move(edge: .trailing).combined(with: .opacity))
                                    }
                                }
                                .overlay(alignment: .top) {
                                    if isSpeedBoostActive {
                                        Text(formatSpeedBoostLabel(speedBoostMultiplier))
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .glassEffect(.regular, in: .capsule)
                                            .padding(.top, 12)
                                            .transition(.opacity)
                                    }
                                }
                                .onAppear {
                                    // 初次进入时给用户一个可发现的控制层
                                    showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                }
                                .onChange(of: player.isPlaying) { _, isPlaying in
                                    showControlsAndAutoHideIfNeeded(player: player)
#if canImport(UIKit)
                                    setIdleTimerDisabled(isPlaying)
#endif
                                    if !isPlaying, isPlaybackEnded(player: player) {
                                        player.pause()
                                    }
                                }
                                .onChange(of: player.currentTime) { _, newTime in
                                    let segment = max(1, Int(newTime / 360.0) + 1)
                                    guard segment != lastDanmakuPrefetchSegment else { return }
                                    lastDanmakuPrefetchSegment = segment
                                    Task {
                                        await bindableViewModel.preloadDanmakuIfNeeded(currentTime: newTime)
                                    }
                                }
                                .onChange(of: showDebugPanel) { _, newValue in
                                    if !newValue {
                                        showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                    } else {
                                        controlsVisible = true
                                        hideControlsTask?.cancel()
                                    }
                                }
                        }
                        .frame(
                            width: isFullscreen ? geo.size.width : geo.size.width,
                            height: isFullscreen
                                ? geo.size.height
                                : min(geo.size.width / stream.aspectRatio, geo.size.width * (4.0 / 3.0)),
                            alignment: .center
                        )
                        .clipped()
                        .layoutPriority(1)
                    } else {
                        // 加载状态：先展示封面，保证卡片→详情的 Hero 动画有目标视图
                        ZStack {
                            AsyncImage(url: URL(string: video.cover)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color(.systemGray5))
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .background(Color.black)
                            .matchedGeometryEffect(id: heroID, in: namespace)

                            VStack(spacing: 12) {
                                if bindableViewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else if bindableViewModel.error != nil {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                } else {
                                    ProgressView()
                                        .tint(.white)
                                }
                            }
                        }
                        .frame(
                            width: isFullscreen ? geo.size.width : geo.size.width,
                            height: isFullscreen
                                ? geo.size.height
                                : min(geo.size.width / (16.0 / 9.0), geo.size.width * (4.0 / 3.0)),
                            alignment: .center
                        )
                        .clipped()
                        .layoutPriority(1)
                    }

                    if !isFullscreen {
                        tabBar
                        tabContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .sheet(isPresented: $isFavoriteSheetPresented) {
                    FavoriteFolderSheet(
                        folders: $favoriteFolders,
                        selectedIds: $favoriteSelectedIds,
                        initiallySelectedIds: $favoriteInitiallySelectedIds,
                        isLoading: $favoriteIsLoading,
                        onDismiss: { isFavoriteSheetPresented = false },
                        onConfirm: {
                            let addIds = favoriteSelectedIds.subtracting(favoriteInitiallySelectedIds)
                            let delIds = favoriteInitiallySelectedIds.subtracting(favoriteSelectedIds)

                            Task {
                                await bindableViewModel.applyFavoriteSelection(
                                    addMediaIds: Array(addIds),
                                    delMediaIds: Array(delIds),
                                    finalSelectedIds: favoriteSelectedIds
                                )
                                isFavoriteSheetPresented = false
                            }
                        },
                        onLoad: {
                            guard !favoriteIsLoading else { return }
                            favoriteIsLoading = true
                            Task {
                                do {
                                    let folders = try await bindableViewModel.fetchFavoriteFoldersForCurrentUser()
                                    await MainActor.run {
                                        favoriteFolders = folders
                                        let preselected = Set(
                                            folders.filter { $0.isSelectedInitially }.map(\.id)
                                        )
                                        favoriteInitiallySelectedIds = preselected
                                        favoriteSelectedIds = preselected
                                        favoriteIsLoading = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        favoriteFolders = []
                                        favoriteInitiallySelectedIds = []
                                        favoriteSelectedIds = []
                                        favoriteIsLoading = false
                                    }
                                }
                            }
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $isDanmakuSettingsPresented) {
                    DanmakuSettingsSheet(
                        config: $danmakuConfig,
                        onClose: { isDanmakuSettingsPresented = false }
                    )
                    .presentationDetents([.medium, .large])
                }

                // 调试信息面板
                if showDebugPanel, let stream = bindableViewModel.dashStream {
                    DashStreamDebugPanel(
                        stream: stream,
                        player: bindableViewModel.player,
                        onDismiss: { showDebugPanel = false }
                    )
                }
            }
            .overlay(alignment: .top) {
                if !isFullscreen {
                    Color.black
                        .frame(height: geo.safeAreaInsets.top)
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if isFullscreen {
                    Color.black.ignoresSafeArea()
                } else {
                    Color.clear
                }
            }
        }
        .onAppear {
            danmakuConfig = DanmakuConfigStore.load()
#if canImport(UIKit)
            setIdleTimerDisabled(bindableViewModel.player?.isPlaying == true)
#endif
        }
        .onChange(of: danmakuConfig) { _, newValue in
            danmakuConfig = newValue.clamped()
            DanmakuConfigStore.save(danmakuConfig)
        }
        .task {
            lastDanmakuPrefetchSegment = 0
            await bindableViewModel.loadVideoData()

            // 加载完成后启动历史上报
            if bindableViewModel.dashStream != nil {
                bindableViewModel.startHistoryReporting()
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            if let player = bindableViewModel.player {
                speedBoostTriggerTask?.cancel()
                speedBoostTriggerTask = nil
                if isSpeedBoostActive {
                    endSpeedBoostIfNeeded(player: player)
                }
                player.pause()
                bindableViewModel.stopHistoryReporting(with: player)
            }
#if canImport(UIKit)
            setIdleTimerDisabled(false)
#endif
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toast(message: $toastMessage)
        .statusBarHidden(isFullscreen)
        .navigationDestination(item: $selectedRelatedVideo) { relatedVideo in
            if #available(iOS 18.0, *) {
                VideoDetailPage(
                    video: relatedVideo,
                    namespace: namespace,
                    onBack: { selectedRelatedVideo = nil }
                )
                .navigationTransition(
                    .zoom(sourceID: "videoHero.\(relatedVideo.bvid)", in: namespace)
                )
            } else {
                VideoDetailPage(
                    video: relatedVideo,
                    namespace: namespace,
                    onBack: { selectedRelatedVideo = nil }
                )
            }
        }
        .navigationDestination(item: $selectedUserSpaceRoute) { route in
            UserSpaceView(
                mid: route.mid,
                fromViewAid: route.fromViewAid,
                onBack: { selectedUserSpaceRoute = nil }
            )
            .onDisappear {
                selectedUserSpaceRoute = nil
            }
        }
    }

    private var fullscreenAwareDanmakuConfig: DanmakuEngineConfig {
        var config = danmakuConfig
        if isFullscreen {
            config.fontScale = danmakuConfig.fullscreenFontScale
        }
        return config
    }

    private enum VideoDetailTab: String, CaseIterable {
        case intro = "简介"
        case comments = "评论"
    }

    private var tabBar: some View {
        HStack(spacing: 18) {
            ForEach(VideoDetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .intro:
            introTabContent
        case .comments:
            VideoCommentsTabView(
                aid: viewModel.aid,
                onOpenUserSpace: { mid in
                    guard mid > 0 else { return }
                    selectedUserSpaceRoute = UserSpaceRoute(
                        mid: mid,
                        fromViewAid: viewModel.aid > 0 ? viewModel.aid : nil
                    )
                }
            )
                .background(Color(.systemBackground))
        }
    }

    private var introTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let detail = viewModel.videoDetail {
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: detail.owner.face)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color.gray)
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())

                            // UP主信息
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.owner.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                if let follower = viewModel.ownerFollowerCount,
                                   let archiveCount = viewModel.ownerArchiveCount
                                {
                                    Text("\(formatCount(follower))粉丝  \(archiveCount)视频")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("—粉丝  —视频")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedUserSpaceRoute = UserSpaceRoute(
                                mid: detail.owner.mid,
                                fromViewAid: detail.aid
                            )
                        }

                        HStack{
                            Spacer()
                            // 关注按钮
                            ZStack{
                                Capsule(style: .continuous)
                                    .fill(viewModel.isOwnerFollowing ? .followedBackground : Color("BiliPink"))
                                    .animation(.smooth(duration: 0.1), value: viewModel.isOwnerFollowing)
                                
                                Button(action: {
                                    guard !viewModel.isOwnerFollowRequesting else { return }
                                    Task {
                                        do {
                                            try await viewModel.toggleOwnerFollow()
                                        } catch {
                                            await MainActor.run {
                                                toastMessage = error.localizedDescription
                                            }
                                        }
                                    }
                                }) {
                                    Text(viewModel.isOwnerFollowing ? "已关注" : "关注")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(viewModel.isOwnerFollowing ? .followedText : .white)
                                }
                                .frame(width: 65,height: 25)
                            }
                            .glassEffect(
                                .regular.interactive(),
                                in:.capsule
                            )
                            .frame(width: 65,height: 25)
                        }
                    }

                    // 视频标题
                    Text(video.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isVideoDetailExpanded.toggle()
                            }
                        }

                    // 视频数据
                    HStack(spacing: 10) {
                        Label(formatCount(detail.stat.view), systemImage: "play.fill")
                        Label(formatCount(detail.stat.danmaku), systemImage: "text.bubble.fill")
                        Text(formatTimestamp(TimeInterval(detail.pubdate)))
                        if let online = viewModel.playerInfo?.onlineCount,
                           online > 0,
                           Date().timeIntervalSince1970 >= TimeInterval(detail.pubdate)
                        {
                            Label("\(formatCount(online))人在看", systemImage: "person.2.fill")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isVideoDetailExpanded.toggle()
                        }
                    }

                    // 视频详情（默认折叠；点击标题或视频数据展开/收起）
                    if isVideoDetailExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(detail.bvid)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onLongPressGesture {
#if canImport(UIKit)
                                    UIPasteboard.general.string = detail.bvid
#endif
                                }

                            if !detail.desc.isEmpty {
                                Text(detail.desc)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // 操作栏（点赞/点踩/投币/收藏/转发/稍后再看）
                    VideoActionBar(
                        isLiked: viewModel.isLiked,
                        isDisliked: viewModel.isDisliked,
                        isCoined: viewModel.isCoined,
                        isFavorited: viewModel.isFavorited,
                        isWatchLater: viewModel.isWatchLater,
                        likeCount: viewModel.likeCount,
                        coinCount: viewModel.coinCount,
                        favoriteCount: viewModel.favoriteCount,
                        shareCount: detail.stat.share,
                        isLikeRequesting: viewModel.isLikeRequesting,
                        isDislikeRequesting: viewModel.isDislikeRequesting,
                        isCoinRequesting: viewModel.isCoinRequesting,
                        isFavoriteRequesting: viewModel.isFavoriteRequesting,
                        isWatchLaterRequesting: viewModel.isWatchLaterRequesting,
                        onToggleLike: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.toggleLike()
                            }
                        },
                        onToggleDislike: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.toggleDislike()
                            }
                        },
                        onCoin1: {
                            Task { await viewModel.coin(multiply: 1) }
                        },
                        onCoin2: {
                            Task { await viewModel.coin(multiply: 2) }
                        },
                        onToggleFavorite: {
                            isFavoriteSheetPresented = true
                        },
                        onShare: {
                            // TODO: add share logic later
                        },
                        onLaterWatch: {
                            if(!viewModel.isWatchLater){
                                viewModel.addToWatchLater()
                            }
                        }
                    )
                    .padding(.top, 4)

                    // 推荐视频
                    if viewModel.relatedIsLoading
                        || viewModel.relatedError != nil
                        || !viewModel.relatedVideos.isEmpty
                    {
                        Divider()
                            .padding(.top, 10)

                        HStack(spacing: 10) {
                            Text("推荐视频")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if viewModel.relatedIsLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Spacer()
                        }
                        .padding(.top, 6)

                        if let error = viewModel.relatedError,
                           !viewModel.relatedIsLoading,
                           viewModel.relatedVideos.isEmpty
                        {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.relatedVideos.prefix(40)) { item in
                                    VideoCardSingleView(
                                        video: item,
                                        namespace: namespace,
                                        onTap: { selectedRelatedVideo = item }
                                    )
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 显示控制条并在需要时自动隐藏

    private func showControlsAndAutoHideIfNeeded(player: MPVKitPlayer, forceShow: Bool = false) {
        guard !showDebugPanel else {
            controlsVisible = true
            hideControlsTask?.cancel()
            return
        }

        if forceShow {
            controlsVisible = true
        } else {
            // 点一下显示；若已显示则切换为隐藏
            controlsVisible.toggle()
        }

        hideControlsTask?.cancel()
        guard controlsVisible, player.isPlaying else { return }

        hideControlsTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 3000000000)
            } catch {
                // 重要：若被取消，请勿继续隐藏控制条
                return
            }
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.22)) {
                controlsVisible = false
            }
        }
    }

    // MARK: - 检查播放是否结束

    private func isPlaybackEnded(player: MPVKitPlayer) -> Bool {
        guard player.duration > 0 else { return false }
        return player.currentTime >= player.duration - 0.05
    }

    // MARK: - 开始倍速播放

    private func beginSpeedBoostIfNeeded(player: MPVKitPlayer) {
        guard !isSpeedBoostActive else { return }
        isSpeedBoostActive = true
        player.setPlaybackRate(speedBoostMultiplier)
#if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
#endif
    }

    // MARK: - 结束倍速播放

    private func endSpeedBoostIfNeeded(player: MPVKitPlayer) {
        guard isSpeedBoostActive else { return }
        isSpeedBoostActive = false
        player.setPlaybackRate(1.0)
    }

    // MARK: - 格式化倍速标签

    private func formatSpeedBoostLabel(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return "\(Int(rate))x倍速中"
        }

        return String(format: "%.1fx倍速中", rate)
    }

    // MARK: - 设置空闲计时器

#if canImport(UIKit)
    private func setIdleTimerDisabled(_ isDisabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = isDisabled
    }
#endif

    // MARK: - 格式化时长

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    // MARK: - 格式化计数

    private func formatCount(_ count: Int) -> String {
        if count >= 10000 {
            return String(
                format: "%.1f万",
                Double(count) / 10000
            )
        }

        return "\(count)"
    }

    // MARK: - 格式化时间戳

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current

        return formatter.string(from: date)
    }

#if canImport(UIKit)
    private func updateDeviceOrientationForFullscreen(isFullscreen: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: isFullscreen ? .landscapeRight : .portrait
        )
        scene.requestGeometryUpdate(prefs) { error in
            print("requestGeometryUpdate failed: \(error.localizedDescription)")
        }
    }
#endif

    private func handleBackAction() {
        if isFullscreen {
            withAnimation(.easeInOut(duration: 0.2)) {
                isFullscreen = false
                isFullscreenDanmakuPanelVisible = false
            }
#if canImport(UIKit)
            updateDeviceOrientationForFullscreen(isFullscreen: false)
#endif
            Task { @MainActor in
                await viewModel.rebuildPlayerPreservingState()
            }
        } else {
            onBack()
        }
    }
}

private struct UserSpaceRoute: Identifiable, Hashable {
    let mid: Int
    let fromViewAid: Int?

    var id: String {
        "\(mid)-\(fromViewAid ?? 0)"
    }
}

// MARK: - 视频操作

private struct VideoActionBar: View {
    let isLiked: Bool
    let isDisliked: Bool
    let isCoined: Bool
    let isFavorited: Bool
    let isWatchLater: Bool

    let likeCount: Int
    let coinCount: Int
    let favoriteCount: Int
    let shareCount: Int

    let isLikeRequesting: Bool
    let isDislikeRequesting: Bool
    let isCoinRequesting: Bool
    let isFavoriteRequesting: Bool
    let isWatchLaterRequesting: Bool

    let onToggleLike: () -> Void
    let onToggleDislike: () -> Void
    let onCoin1: () -> Void
    let onCoin2: () -> Void
    let onToggleFavorite: () -> Void
    let onShare: () -> Void
    let onLaterWatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VideoActionButton(
                title: formatCount(likeCount),
                systemImage: "hand.thumbsup.fill",
                isActive: isLiked,
                //isDisabled: isLikeRequesting,
                isDisabled: false,
                onTap: onToggleLike
            )

            VideoActionButton(
                title: "点踩",
                systemImage: "hand.thumbsdown.fill",
                isActive: isDisliked,
                //isDisabled: isDislikeRequesting,
                isDisabled: false,
                onTap: onToggleDislike
            )

            VideoCoinMenuButton(
                title: formatCount(coinCount),
                assetImage: "BiliCoin",
                isActive: isCoined,
                //isDisabled: isCoinRequesting || isCoined,
                isDisabled: isCoined,
                onCoin1: onCoin1,
                onCoin2: onCoin2
            )

            VideoActionButton(
                title: formatCount(favoriteCount),
                systemImage: "star.fill",
                isActive: isFavorited,
                //isDisabled: isFavoriteRequesting,
                isDisabled: false,
                onTap: onToggleFavorite
            )

            VideoActionButton(
                title: formatCount(shareCount),
                systemImage: "square.and.arrow.up.fill",
                isActive: false,
                isDisabled: false,
                onTap: onShare
            )

            VideoActionButton(
                title: "稍后再看",
                systemImage: "clock.badge",
                isActive: isWatchLater,
                isDisabled: isWatchLaterRequesting,
                onTap: onLaterWatch
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 格式化计数（VideoActionBar中的辅助函数）

    private func formatCount(_ count: Int) -> String {
        if count >= 10000 {
            return String(
                format: "%.1f万",
                Double(count) / 10000
            )
        }

        return "\(count)"
    }
}

private struct VideoCoinMenuButton: View {
    let title: String
    let assetImage: String
    let isActive: Bool
    let isDisabled: Bool
    let onCoin1: () -> Void
    let onCoin2: () -> Void

    var body: some View {
        Menu {
            Button("投1个") { onCoin1() }
            Button("投2个") { onCoin2() }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isActive ? Color("BiliPink") : Color.white.opacity(0))
                        .animation(.smooth(duration: 0.1), value: isActive)

                    Image(assetImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(isActive ? .white : .primary)
                }
                .frame(width: 44, height: 44)
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )

                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

private struct VideoActionButton: View {
    let title: String
    let systemImage: String?
    let assetImage: String?
    let isActive: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    init(
        title: String,
        systemImage: String,
        isActive: Bool,
        isDisabled: Bool,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.assetImage = nil
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.onTap = onTap
    }

    init(
        title: String,
        assetImage: String,
        isActive: Bool,
        isDisabled: Bool,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = nil
        self.assetImage = assetImage
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.onTap = onTap
    }

    // 点赞/投币/收藏等按钮
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isActive ? Color("BiliPink") : Color.white.opacity(0))
                        .animation(.smooth(duration: 0.1), value: isActive)
                    Group {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 16, weight: .semibold))
                        } else if let assetImage {
                            Image(assetImage)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        }
                    }
                    .foregroundStyle(isActive ? .white : .primary)
                }
                .frame(width: 44, height: 44)
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )

                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

// MARK: - 收藏夹抽屉

private struct FavoriteFolderSheet: View {
    @Binding var folders: [FavoriteFolderItem]
    @Binding var selectedIds: Set<Int64>
    @Binding var initiallySelectedIds: Set<Int64>
    @Binding var isLoading: Bool

    let onDismiss: () -> Void
    let onConfirm: () -> Void
    let onLoad: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("加载收藏夹中…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if folders.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("暂无收藏夹")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(folders) { folder in
                            FavoriteFolderRow(
                                folder: folder,
                                isSelected: selectedIds.contains(folder.id),
                                onToggle: {
                                    if selectedIds.contains(folder.id) {
                                        selectedIds.remove(folder.id)
                                    } else {
                                        selectedIds.insert(folder.id)
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("选择收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onConfirm) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(selectedIds == initiallySelectedIds)
                }
            }
            .task {
                onLoad()
            }
        }
    }
}

// MARK: - 弹幕设置抽屉

private struct DanmakuSettingsSheet: View {
    @Binding var config: DanmakuEngineConfig
    let onClose: () -> Void

    private let defaultConfig = DanmakuEngineConfig()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sliderSection(
                        title: "屏蔽等级",
                        valueText: "\(config.blockLevel)",
                        onReset: { config.blockLevel = defaultConfig.blockLevel }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { Double(config.blockLevel) },
                                set: { config.blockLevel = Int($0) }
                            ),
                            range: 0 ... 10,
                            step: 1
                        )
                    }

                    blockTypeSection

                    otherSection

                    sliderSection(
                        title: "显示区域",
                        valueText: "\(Int((config.topRegionRatio * 100).rounded()))%",
                        onReset: {
                            config.topRegionRatio = defaultConfig.topRegionRatio
                            config.bottomRegionRatio = defaultConfig.bottomRegionRatio
                        }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { config.topRegionRatio * 100 },
                                set: {
                                    let ratio = $0 / 100
                                    config.topRegionRatio = ratio
                                    config.bottomRegionRatio = ratio
                                }
                            ),
                            range: 10 ... 100,
                            step: 10
                        )
                    }

                    sliderSection(
                        title: "不透明度",
                        valueText: "\(Int((config.opacity * 100).rounded()))%",
                        onReset: { config.opacity = defaultConfig.opacity }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { config.opacity * 100 },
                                set: { config.opacity = $0 / 100 }
                            ),
                            range: 0 ... 100,
                            step: 10
                        )
                    }

                    sliderSection(
                        title: "字体粗细",
                        valueText: "\(config.fontWeightValue)",
                        onReset: { config.fontWeightValue = defaultConfig.fontWeightValue }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { Double(config.fontWeightValue) },
                                set: { config.fontWeightValue = Int($0) }
                            ),
                            range: 1 ... 9,
                            step: 1
                        )
                    }

                    sliderSection(
                        title: "描边粗细",
                        valueText: String(format: "%.1f", config.strokeWidth),
                        onReset: { config.strokeWidth = defaultConfig.strokeWidth }
                    ) {
                        steppedSlider(
                            value: $config.strokeWidth,
                            range: 0 ... 2,
                            step: 0.1
                        )
                    }

                    sliderSection(
                        title: "字体大小",
                        valueText: "\(Int((config.fontScale * 100).rounded()))%",
                        onReset: { config.fontScale = defaultConfig.fontScale }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { config.fontScale * 100 },
                                set: { config.fontScale = $0 / 100 }
                            ),
                            range: 50 ... 250,
                            step: 10
                        )
                    }

                    sliderSection(
                        title: "全屏字体大小",
                        valueText: "\(Int((config.fullscreenFontScale * 100).rounded()))%",
                        onReset: { config.fullscreenFontScale = defaultConfig.fullscreenFontScale }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { config.fullscreenFontScale * 100 },
                                set: { config.fullscreenFontScale = $0 / 100 }
                            ),
                            range: 50 ... 250,
                            step: 10
                        )
                    }

                    sliderSection(
                        title: "滚动弹幕时长",
                        valueText: "\(Int(config.scrollDuration.rounded()))s",
                        onReset: { config.scrollDuration = defaultConfig.scrollDuration }
                    ) {
                        steppedSlider(
                            value: $config.scrollDuration,
                            range: 1 ... 30,
                            step: 1
                        )
                    }

                    sliderSection(
                        title: "静态弹幕时长",
                        valueText: "\(Int(config.staticDuration.rounded()))s",
                        onReset: { config.staticDuration = defaultConfig.staticDuration }
                    ) {
                        steppedSlider(
                            value: $config.staticDuration,
                            range: 1 ... 30,
                            step: 1
                        )
                    }

                    sliderSection(
                        title: "弹幕行高",
                        valueText: String(format: "%.1f", config.lineHeightMultiplier),
                        onReset: { config.lineHeightMultiplier = defaultConfig.lineHeightMultiplier }
                    ) {
                        steppedSlider(
                            value: $config.lineHeightMultiplier,
                            range: 1 ... 3,
                            step: 0.1
                        )
                    }
                }
                .padding(16)
            }
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
        }
    }

    private var blockTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(
                "按类型屏蔽",
                valueText: "",
                onReset: {
                    config.blockScroll = defaultConfig.blockScroll
                    config.blockTop = defaultConfig.blockTop
                    config.blockBottom = defaultConfig.blockBottom
                    config.blockColorful = defaultConfig.blockColorful
                }
            )
            HStack(spacing: 8) {
                toggleChip("滚动", isOn: $config.blockScroll)
                toggleChip("顶部", isOn: $config.blockTop)
                toggleChip("底部", isOn: $config.blockBottom)
                toggleChip("彩色", isOn: $config.blockColorful)
            }
        }
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(
                "其他",
                valueText: "",
                onReset: {
                    config.allowOverlapWhenMassive = defaultConfig.allowOverlapWhenMassive
                    config.forceAllScroll = defaultConfig.forceAllScroll
                }
            )
            HStack(spacing: 8) {
                toggleChip("海量弹幕", isOn: $config.allowOverlapWhenMassive)
                toggleChip("全部滚动", isOn: $config.forceAllScroll)
                Spacer(minLength: 0)
            }
        }
    }

    private func sliderSection(
        title: String,
        valueText: String,
        onReset: @escaping () -> Void,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(title, valueText: valueText, onReset: onReset)
            control()
        }
    }

    private func titleRow(_ title: String, valueText: String, onReset: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private func steppedSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Slider(value: value, in: range, step: step)
            .tint(Color("BiliPink"))
    }

    private func toggleChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isOn.wrappedValue ? Color("BiliPink") : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DanmakuSettingsPanel: View {
    @Binding var config: DanmakuEngineConfig
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("弹幕设置")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
            }

            Toggle("屏蔽滚动", isOn: $config.blockScroll)
                .tint(Color("BiliPink"))
            Toggle("屏蔽顶部", isOn: $config.blockTop)
                .tint(Color("BiliPink"))
            Toggle("屏蔽底部", isOn: $config.blockBottom)
                .tint(Color("BiliPink"))
            Toggle("屏蔽彩色", isOn: $config.blockColorful)
                .tint(Color("BiliPink"))
        }
        .foregroundStyle(.white)
        .font(.system(size: 14, weight: .medium))
        .padding(14)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
    }
}

private struct FavoriteFolderRow: View {
    let folder: FavoriteFolderItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: folder.isPrivate ? "folder.fill.badge.person.crop" : "folder.fill")
                    .foregroundStyle(.primary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Text("\(folder.mediaCount)个内容 \(folder.isPrivate ? "私密" : "公开")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color("BiliPink") : .secondary)
                    .imageScale(.large)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 独立的视频菜单组件，避免跟随视频时间的高频刷新

private struct PlaybackRateMenuView: View, Equatable {
    let selectedRate: Double
    let onUserInteracted: () -> Void
    let onSelect: (Double) -> Void

    static func == (lhs: PlaybackRateMenuView, rhs: PlaybackRateMenuView) -> Bool {
        lhs.selectedRate == rhs.selectedRate
    }

    var body: some View {
        Menu {
            let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
            ForEach(rates, id: \.self) { rate in
                Button(playbackRateText(rate)) {
                    onUserInteracted()
                    onSelect(rate)
                }
            }
        } label: {
            Text(playbackRateMenuLabel)
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .semibold))
                .padding(8)
        }
    }

    private var playbackRateMenuLabel: String {
        selectedRate == 1.0 ? "倍速" : playbackRateText(selectedRate)
    }

    private func playbackRateText(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }
}

private struct QualityMenuView: View, Equatable {
    let options: [VideoQualityOption]
    let selectedCode: Int?
    let onUserInteracted: () -> Void
    let onSelect: (Int) -> Void

    static func == (lhs: QualityMenuView, rhs: QualityMenuView) -> Bool {
        lhs.selectedCode == rhs.selectedCode && lhs.options.count == rhs.options.count
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option.label) {
                    onUserInteracted()
                    onSelect(option.code)
                }
            }
        } label: {
            Text(currentQualityLabel)
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .semibold))
                .padding(8)
        }
    }

    private var currentQualityLabel: String {
        if let selectedCode = selectedCode,
           let selected = options.first(where: { $0.code == selectedCode })
        {
            return selected.label
        }
        return "清晰度"
    }
}

// MARK: - 视频控制器覆盖

private struct PlayerControlsOverlay: View {
    @Binding var showDebugPanel: Bool

    let onShowDanmakuSettings: () -> Void
    let isFullscreen: Bool
    let isFullscreenDanmakuPanelVisible: Bool
    let qualityOptions: [VideoQualityOption]
    let selectedQualityCode: Int?
    let selectedPlaybackRate: Double
    let isVisible: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedUntil: TimeInterval
    let isPlaying: Bool
    let segments: [ProgressSegment]
    let onBack: () -> Void
    let onUserInteracted: () -> Void
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onFullscreen: () -> Void
    let onSelectQuality: (Int) -> Void
    let onSelectPlaybackRate: (Double) -> Void

    var body: some View {
        ZStack {
            if isVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomBar
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: isVisible)
            }
        }
        .allowsHitTesting(isVisible)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            // 左上角返回
            Button(action: {
                onUserInteracted()
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(
                .regular.interactive(),
                in: .circle
            )

            Spacer()

            if !isFullscreen {
                Button(action: {
                    onUserInteracted()
                    onShowDanmakuSettings()
                }) {
                    Image("DanmakuSetting")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                }
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )
            }

            if !isFullscreen {
                // 右上角更多
                Button(action: {
                    onUserInteracted()
                    showDebugPanel.toggle()
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 40)
                }
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )
            }
        }
        .padding(12)
    }

    private var bottomBar: some View {
        Group {
            if isFullscreen {
                fullscreenBottomBar
            } else {
                regularBottomBar
            }
        }
    }

    private var regularBottomBar: some View {
        HStack(spacing: 10) {
            Button(action: {
                onUserInteracted()
                onTogglePlayPause()
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .glassEffect(
                .regular.interactive(),
                in: .circle
            )

            VideoProgressBar(
                currentTime: currentTime,
                duration: duration,
                bufferedUntil: bufferedUntil,
                segments: segments,
                onSeek: { t in onSeek(t) },
                onUserInteracted: onUserInteracted
            )

            Text("\(formatMMSS(currentTime))/\(formatMMSS(duration))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .glassEffect(
                    .regular,
                    in: .capsule
                )

            Button(action: {
                onUserInteracted()
                onFullscreen()
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .glassEffect(
                .regular.interactive(),
                in: .circle
            )
            .accessibilityLabel("全屏")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var fullscreenBottomBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(formatMMSS(currentTime))/\(formatMMSS(duration))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 12)

            VideoProgressBar(
                currentTime: currentTime,
                duration: duration,
                bufferedUntil: bufferedUntil,
                segments: segments,
                onSeek: { t in onSeek(t) },
                onUserInteracted: onUserInteracted
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)

            HStack {
                HStack(spacing: 10) {
                    actionCircleButton(systemName: isPlaying ? "pause.fill" : "play.fill") {
                        onUserInteracted()
                        onTogglePlayPause()
                    }
                    actionCircleButton(imageName: "DanmakuSetting") {
                        onUserInteracted()
                        onShowDanmakuSettings()
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    PlaybackRateMenuView(
                        selectedRate: selectedPlaybackRate,
                        onUserInteracted: onUserInteracted,
                        onSelect: onSelectPlaybackRate
                    )
                    .equatable()

                    QualityMenuView(
                        options: qualityOptions,
                        selectedCode: selectedQualityCode,
                        onUserInteracted: onUserInteracted,
                        onSelect: onSelectQuality
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 10)
    }

    private func actionCircleButton(
        systemName: String? = nil,
        imageName: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                } else if let imageName {
                    Image(imageName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 32, height: 32)
        }
        .glassEffect(
            .regular.interactive(),
            in: .circle
        )
    }

    // MARK: - 格式化时间（分钟:秒）

    private func formatMMSS(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
}

// MARK: - 视频进度条 (Segment-Friendly)

private struct ProgressSegment: Identifiable, Equatable {
    let id = UUID()
    /// 0...1
    let start: Double
    /// 0...1, must be >= start
    let end: Double
    let color: Color
    let opacity: Double

    init(start: Double, end: Double, color: Color, opacity: Double = 0.45) {
        self.start = start
        self.end = end
        self.color = color
        self.opacity = opacity
    }
}

private struct VideoProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedUntil: TimeInterval
    let segments: [ProgressSegment]
    let onSeek: (TimeInterval) -> Void
    let onUserInteracted: () -> Void

    @GestureState private var isDragging = false
    @State private var dragProgress: Double? = nil

    private var clampedProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    private var clampedBufferedProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(bufferedUntil / duration, 0), 1)
    }

    private var effectiveProgress: Double {
        dragProgress ?? clampedProgress
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h: CGFloat = 4
            let knobSize: CGFloat = 10

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: h)

                // 缓冲层：介于已播放/未播放之间的亮度
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.5))
                    .frame(width: w * max(clampedBufferedProgress, 0), height: h)

                // 分段底色层（后续你可以把章节/高光片段塞进 segments）
                ForEach(segments) { seg in
                    let s = min(max(seg.start, 0), 1)
                    let e = min(max(seg.end, 0), 1)
                    if e > s {
                        Capsule(style: .continuous)
                            .fill(seg.color.opacity(seg.opacity))
                            .frame(width: w * (e - s), height: h)
                            .offset(x: w * s)
                    }
                }

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: w * effectiveProgress, height: h)

                // 小圆点，接近 iOS 的轻量样式（显隐跟随 controls）
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                    .offset(x: w * effectiveProgress - knobSize / 2)
                    .opacity(isDragging ? 1 : 0.9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        onUserInteracted()
                        let p = min(max(value.location.x / w, 0), 1)
                        dragProgress = p
                    }
                    .onEnded { value in
                        onUserInteracted()
                        let p = min(max(value.location.x / w, 0), 1)
                        dragProgress = nil
                        guard duration > 0 else { return }
                        onSeek(duration * p)
                    }
            )
        }
        .frame(height: 22)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - DASH 流详情窗口

struct DashStreamDebugPanel: View {
    let stream: DashStream
    let player: MPVKitPlayer?
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("DASH 流详情")
                        .font(.headline)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("视频参数").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow("分辨率", "\(stream.width)×\(stream.height)")
                            InfoRow("宽高比", String(format: "%.2f:1", stream.aspectRatio))
                            InfoRow("帧率", "\(stream.fps) fps")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("编码信息").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow("视频编码", stream.videoCodec)
                            InfoRow("音频编码", stream.audioCodec)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("码率").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow("视频码率", formatBitrate(stream.videoBitrate))
                            InfoRow("音频码率", formatBitrate(stream.audioBitrate))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("流地址").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            URIRow("视频", stream.videoURL.absoluteString)
                            URIRow("音频", stream.audioURL.absoluteString)
                        }

                        if let player = player {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("播放器状态").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                                InfoRow("播放状态", player.isPlaying ? "播放中" : "已暂停")
                                InfoRow("当前时间", formatTime(player.currentTime))
                                InfoRow("总时长", formatTime(player.duration))
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("解码器").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                                InfoRow("硬件解码", player.hwdecCurrent.isEmpty ? "—" : player.hwdecCurrent)
                                InfoRow("视频解码器", player.videoCodec.isEmpty ? "—" : player.videoCodec)
                                InfoRow("音频解码器", player.audioCodec.isEmpty ? "—" : player.audioCodec)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(16)
        }
    }

    // MARK: - 格式化比特率

    private func formatBitrate(_ bitrate: Int) -> String {
        let kbps = Double(bitrate) / 1000
        return String(format: "%.2f Kbps", kbps)
    }

    // MARK: - 格式化时间

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct URIRow: View {
    let label: String
    let url: String

    init(_ label: String, _ url: String) {
        self.label = label
        self.url = url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(url)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var ns

        var body: some View {
            VideoDetailPage(
                video: VideoItem(
                    bvid: "BV1WsD1BhEvt",
                    cid: 37424204720,
                    cover: "https://picsum.photos/800/450",
                    title: "七里香 格温",
                    playCount: "12.9万",
                    danmakuCount: "345",
                    uploader: "还有下次的叭",
                    duration: 325,
                    publishTimeText: "2026-05-25",
                    bottomRcmdReasonText: nil
                ),
                namespace: ns,
                onBack: {}
            )
        }
    }

    return PreviewWrapper()
}

//
//  HomeView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Observation
import SwiftUI

struct HomeView: View {
    private enum HomeTab: String, CaseIterable, Identifiable {
        case live
        case recommended
        case popular
        case section

        var id: Self { self }

        var title: String {
            switch self {
            case .live:
                L10n.string("tab.live")
            case .recommended:
                L10n.string("tab.recommended")
            case .popular:
                L10n.string("tab.popular")
            case .section:
                L10n.string("tab.section")
            }
        }
    }

    @State private var selectedTab: HomeTab = .recommended
    @State private var selectedVideo: VideoItem?
    @State private var isSearchViewPresented = false
    @State private var isMessageViewPresented = false
    @State private var liveHomeViewModel = LiveHomeViewModel()
    @Namespace private var videoHeroNamespace
    @Bindable var viewModel: HomeViewModel
    @ObservedObject private var loginSession = LoginSession.shared
    private let tabs = HomeTab.allCases

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    private let horizontalPadding: CGFloat = 12
    private let columnSpacing: CGFloat = 12

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部区域
                VStack(spacing: 14) {
                    // 第一行
                    HStack(spacing: 12) {
                        // 搜索框
                        Button {
                            isSearchViewPresented = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)

                                Text("搜索视频")
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            .regular.interactive(),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )

                        // 消息按钮
                        Button {
                            isMessageViewPresented = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 18))
                                    .frame(width: 40, height: 40)

                                if viewModel.unreadMessageCount > 0 {
                                    Text(unreadBadgeText)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .frame(minWidth: 17, minHeight: 17)
                                        .background(.red, in: Capsule())
                                        .overlay {
                                            Capsule()
                                                .stroke(.regularMaterial, lineWidth: 1)
                                        }
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .glassEffect(
                            .regular.interactive(),
                            in: .circle
                        )

                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // 分类栏
                    tabBar
                }
                .padding(.bottom, 10)
                .background(.regularMaterial)

                Divider()

                // 视频流
                GeometryReader { proxy in
                    let availableWidth = proxy.size.width - (horizontalPadding * 2)
                    let videoCardWidth = (availableWidth - columnSpacing) / 2

                    TabView(selection: $selectedTab) {
                        ForEach(tabs, id: \.self) { tab in
                            tabPage(for: tab, videoCardWidth: videoCardWidth)
                                .tag(tab)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedVideo) { video in
                if #available(iOS 18.0, *) {
                    VideoDetailPage(
                        video: video,
                        namespace: videoHeroNamespace,
                        onBack: { selectedVideo = nil }
                    )
                    .navigationTransition(
                        .zoom(sourceID: "videoHero.\(video.bvid)", in: videoHeroNamespace)
                    )
                } else {
                    VideoDetailPage(
                        video: video,
                        namespace: videoHeroNamespace,
                        onBack: { selectedVideo = nil }
                    )
                }
            }
            .navigationDestination(isPresented: $isSearchViewPresented) {
                SearchView()
            }
            .navigationDestination(isPresented: $isMessageViewPresented) {
                MessageView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.refreshUnreadMessageCountIfNeeded()
            await viewModel.loadInitialVideos()
        }
        .onReceive(loginSession.$isLogin) { isLogin in
            if isLogin {
                Task {
                    await viewModel.loadUnreadMessageCount(force: true)
                }
            } else {
                viewModel.unreadMessageCount = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .manualPictureInPictureRestoreOnHome)) { notification in
            guard let route = notification.object as? ManualPictureInPictureRoute else { return }
            switch route {
            case let .video(video):
                selectedTab = .recommended
                selectedVideo = nil
                isSearchViewPresented = false
                DispatchQueue.main.async {
                    selectedVideo = video
                }
            case .live:
                selectedTab = .live
            }
        }
    }

    private var unreadBadgeText: String {
        viewModel.unreadMessageCount > 99 ? "99+" : String(viewModel.unreadMessageCount)
    }

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(tabs, id: \.self) { tab in
                        VStack(spacing: 4) {
                            Text(tab.title)
                                .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                            Capsule()
                                .fill(selectedTab == tab ? .biliPink : .clear)
                                .frame(height: 3)
                        }
                        .contentShape(Rectangle())
                        .id(tab)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: selectedTab) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func tabPage(for tab: HomeTab, videoCardWidth: CGFloat) -> some View {
        if tab == .live {
            LiveHomeView(cardWidth: videoCardWidth, viewModel: liveHomeViewModel)
        } else if tab == .popular {
            PopularVideosPage(
                namespace: videoHeroNamespace,
                onSelectVideo: { selectedVideo = $0 }
            )
        } else {
            recommendationContent(videoCardWidth: videoCardWidth)
        }
    }

    // MARK: - Feed 卡片分发

    @ViewBuilder
    private func feedCardView(for card: FeedCardItem, videoCardWidth: CGFloat) -> some View {
        switch card {
        case .video(let videoItem):
            VideoCardView(
                video: videoItem,
                namespace: videoHeroNamespace,
                thumbnailWidth: videoCardWidth,
                onTap: { selectedVideo = videoItem }
            )
        case .live(let liveModel):
            LiveCardView(model: liveModel, cardWidth: videoCardWidth)
        }
    }

    private func recommendationContent(videoCardWidth: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if !viewModel.feedCards.isEmpty {
                    let cards = viewModel.feedCards
                    let marker = viewModel.refreshMarkerIndex

                    if let marker = marker, marker > 0, marker < cards.count {
                        let newCards = Array(cards.prefix(marker))
                        let oldCards = Array(cards.suffix(from: marker))

                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(newCards) { card in
                                feedCardView(for: card, videoCardWidth: videoCardWidth)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)

                        DividerWithText(title: "上次看到这")
                            .padding(.vertical, 6)

                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(oldCards) { card in
                                feedCardView(for: card, videoCardWidth: videoCardWidth)
                                    .onAppear {
                                        if card.id == oldCards.last?.id {
                                            Task { await viewModel.loadMoreVideos() }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(cards) { card in
                                feedCardView(for: card, videoCardWidth: videoCardWidth)
                                    .onAppear {
                                        if card.id == cards.last?.id {
                                            Task { await viewModel.loadMoreVideos() }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    }
                } else {
                    ForEach(viewModel.sections) { section in
                        if let title = section.title {
                            DividerWithText(title: title)
                        }
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(section.videos) { video in
                                VideoCardView(
                                    video: video,
                                    namespace: videoHeroNamespace,
                                    thumbnailWidth: videoCardWidth,
                                    onTap: { selectedVideo = video }
                                )
                                .onAppear {
                                    if video.id == section.videos.last?.id {
                                        Task { await viewModel.loadMoreVideos() }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    }
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .refreshable {
            await viewModel.refreshVideos()
        }
    }
}

#Preview {
    @MainActor in
    HomeView(viewModel: HomeViewModel())
}

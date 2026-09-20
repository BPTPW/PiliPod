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
            GeometryReader { proxy in
                let availableWidth = proxy.size.width - (horizontalPadding * 2)
                let videoCardWidth = (availableWidth - columnSpacing) / 2

                // 删除 TabView 有两个考虑：一个是它会再叠一层 TopBar 还无法单独关闭；一个是翻页时可能会触发中间页面的加载
                ForEach(tabs, id: \.self) { tab in
                    if (selectedTab == tab) {
                        tabPage(for: tab, videoCardWidth: videoCardWidth)
                            .tag(tab)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
            .safeAreaBar(edge: .top) {
                tabBar
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isMessageViewPresented = true
                    } label: {
                        Image(systemName: "bell.fill")
                    }
                    .badge(viewModel.unreadMessageCount > 0 ? Text(unreadBadgeText) : nil)
                }
            }
            .navigationTitle("主页")
            .navigationBarTitleDisplayMode(.inline)
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
                .backgroundStyle(Color.clear)
            }
            .backgroundStyle(Color.clear)
            .onChange(of: selectedTab) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .backgroundStyle(Color.clear)
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

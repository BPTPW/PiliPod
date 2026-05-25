//
//  HomeView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Observation
import SwiftUI

struct HomeView: View {
    @State private var selectedTab: String = "推荐"
    @State private var selectedVideo: VideoItem?
    @State private var serchQuery = ""
    @Namespace private var videoHeroNamespace
    @Bindable var viewModel: HomeViewModel
    @ObservedObject private var loginSession = LoginSession.shared

    let tabs = ["直播", "推荐", "热门", "分区"]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

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
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)

                            TextField("搜索视频", text: $serchQuery)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .glassEffect(
                            .regular.interactive(),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )

                        // 消息按钮
                        Button {} label: {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                        }
                        .foregroundStyle(.primary)
                        .glassEffect(
                            .regular.interactive(),
                            in: .circle
                        )

                        // 用户头像
                        Group {
                            if let face = viewModel.userFace, let url = URL(string: face) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            Image(systemName: "person.fill")
                                        }
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                    }
                                    .frame(width: 40, height: 40)
                            }
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.18),
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color: .black.opacity(0.06),
                            radius: 8,
                            y: 4
                        )
                        .foregroundStyle(.primary)
                        .glassEffect(
                            .clear.interactive(),
                            in: .circle
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // 分类栏
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(tabs, id: \.self) { tab in
                                VStack(spacing: 6) {
                                    Text(tab)
                                        .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                                    Capsule()
                                        .fill(selectedTab == tab ? Color.pink : Color.clear)
                                        .frame(height: 3)
                                }
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedTab = tab
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 10)
                .background(.regularMaterial)

                Divider()

                // 视频流
                ScrollView {
                    VStack(spacing: 0) {
                        // App 版推荐 Feed（优先使用 feedCards）
                        if !viewModel.feedCards.isEmpty {
                            let cards = viewModel.feedCards
                            let marker = viewModel.refreshMarkerIndex

                            if let marker = marker, marker > 0, marker < cards.count {
                                // 下拉刷新：新内容在上，旧内容在下，中间分隔线
                                let newCards = Array(cards.prefix(marker))
                                let oldCards = Array(cards.suffix(from: marker))

                                LazyVGrid(columns: columns, spacing: 18) {
                                    ForEach(newCards) { card in
                                        feedCardView(for: card)
                                    }
                                }
                                .padding(.horizontal, 12)

                                DividerWithText(title: "下拉刷新了")
                                    .padding(.vertical, 6)

                                LazyVGrid(columns: columns, spacing: 18) {
                                    ForEach(oldCards) { card in
                                        feedCardView(for: card)
                                            .onAppear {
                                                if card.id == oldCards.last?.id {
                                                    Task { await viewModel.loadMoreVideos() }
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal, 12)
                            } else {
                                LazyVGrid(columns: columns, spacing: 18) {
                                    ForEach(cards) { card in
                                        feedCardView(for: card)
                                            .onAppear {
                                                if card.id == cards.last?.id {
                                                    Task { await viewModel.loadMoreVideos() }
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        } else {
                            // Web 版推荐（兜底）
                            ForEach(viewModel.sections) { section in
                                if let title = section.title {
                                    DividerWithText(title: title)
                                }
                                LazyVGrid(columns: columns, spacing: 18) {
                                    ForEach(section.videos) { video in
                                        VideoCardView(
                                            video: video,
                                            namespace: videoHeroNamespace,
                                            onTap: { selectedVideo = video }
                                        )
                                        .onAppear {
                                            if video.id == section.videos.last?.id {
                                                Task { await viewModel.loadMoreVideos() }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
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
        }
        .task {
            await viewModel.loadUserIfNeeded()
            await viewModel.loadInitialVideos()
        }
        .onReceive(loginSession.$isLogin) { isLogin in
            if isLogin {
                Task { await viewModel.loadUserIfNeeded() }
            } else {
                viewModel.userFace = nil
            }
        }
    }

    // MARK: - Feed 卡片分发

    @ViewBuilder
    private func feedCardView(for card: FeedCardItem) -> some View {
        switch card {
        case .video(let videoItem):
            VideoCardView(
                video: videoItem,
                namespace: videoHeroNamespace,
                onTap: { selectedVideo = videoItem }
            )
        case .live(let liveModel):
            LiveCardView(model: liveModel)
        }
    }
}

#Preview {
    @MainActor in
    HomeView(viewModel: HomeViewModel())
}

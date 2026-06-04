//
//  SearchView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/4.
//

import SwiftUI

struct SearchView: View {
    private enum SearchTab: String, CaseIterable, Identifiable {
        case comprehensive = "综合"
        case video = "视频"
        case user = "用户"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchText = ""
    @State private var trendingItems: [SearchTrendingItem] = []
    @State private var recommendItems: [SearchRecommendItem] = []
    @State private var isLoadingDiscovery = false
    @State private var discoveryErrorMessage: String?
    @State private var activeSearchKeyword: String?
    @State private var selectedTab: SearchTab = .comprehensive
    @State private var searchModules: [SearchComprehensiveModule] = []
    @State private var isSearching = false
    @State private var searchErrorMessage: String?
    @State private var selectedVideo: VideoItem?
    @State private var selectedUserSpaceRoute: SearchUserSpaceRoute?
    @Namespace private var videoHeroNamespace

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .foregroundStyle(.primary)
                .glassEffect(.regular.interactive(), in: .circle)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("搜索视频", text: $searchText)
                        .focused($isSearchFieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            submitSearch()
                        }

                    if !searchText.isEmpty {
                        Button {
                            clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .glassEffect(
                    .regular.interactive(),
                    in: .capsule
                )
                
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if isShowingSearchResults {
                VStack(spacing: 0) {
                    resultTabs

                    Divider()

                    searchResultsContent
                }
            } else {
                discoveryContent
            }
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
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
        .navigationDestination(item: $selectedUserSpaceRoute) { route in
            UserSpaceView(
                mid: route.mid,
                onBack: { selectedUserSpaceRoute = nil }
            )
        }
        .task {
            await focusSearchField()
        }
        .task {
            await loadDiscovery()
        }
    }

    private var isShowingSearchResults: Bool {
        activeSearchKeyword != nil
    }

    private var filteredModules: [SearchComprehensiveModule] {
        switch selectedTab {
        case .comprehensive:
            return searchModules
        case .video:
            return searchModules.filter { $0.resultType == "video" && !$0.videos.isEmpty }
        case .user:
            return searchModules.filter { $0.resultType == "bili_user" && !$0.users.isEmpty }
        }
    }

    private var resultTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(SearchTab.allCases) { tab in
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                        Capsule()
                            .fill(selectedTab == tab ? .biliPink : .clear)
                            .frame(height: 3)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    private var discoveryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoadingDiscovery && trendingItems.isEmpty && recommendItems.isEmpty {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    if !trendingItems.isEmpty {
                        discoverySection(title: "大家都在搜") {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(trendingItems) { item in
                                    discoveryChip {
                                        submitKeyword(item.keyword)
                                    } content: {
                                        HStack(alignment: .center, spacing: 6) {
                                            Text(item.showName)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)

                                            if let iconString = item.icon,
                                               let iconURL = httpsURL(from: iconString)
                                            {
                                                AsyncImage(url: iconURL) { image in
                                                    image
                                                        .resizable()
                                                        .scaledToFit()
                                                } placeholder: {
                                                    EmptyView()
                                                }
                                                .frame(height: 16)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !recommendItems.isEmpty {
                        discoverySection(title: "搜索发现") {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(recommendItems) { item in
                                    discoveryChip {
                                        submitKeyword(item.keyword)
                                    } content: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.showName)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)

                                            if let recommendReason = item.recommendReason,
                                               !recommendReason.isEmpty
                                            {
                                                Text(recommendReason)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }

                    if let discoveryErrorMessage,
                       trendingItems.isEmpty,
                       recommendItems.isEmpty
                    {
                        Text(discoveryErrorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }

                    if trendingItems.isEmpty,
                       recommendItems.isEmpty,
                       !isLoadingDiscovery,
                       discoveryErrorMessage == nil
                    {
                        Text("暂时没有可显示的搜索发现内容")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
    }

    private var searchResultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isSearching {
                    ProgressView("搜索中…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let searchErrorMessage {
                    Text(searchErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if filteredModules.isEmpty {
                    Text("没有找到相关结果")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ForEach(filteredModules) { module in
                        resultModuleView(module)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
    }

    private func discoverySection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content()
        }
    }

    private func discoveryChip<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func resultModuleView(_ module: SearchComprehensiveModule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedTab == .comprehensive {
                Text(module.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if module.resultType == "bili_user" {
                VStack(spacing: 14) {
                    ForEach(module.users) { user in
                        SearchUserLargeCardView(
                            user: user.cardUser,
                            videos: user.previewVideos,
                            onUserTap: {
                                selectedUserSpaceRoute = SearchUserSpaceRoute(mid: Int(user.mid))
                            },
                            onVideoTap: { previewVideo in
                                if let source = user.res.first(where: { $0.bvid == previewVideo.id }) {
                                    selectedVideo = source.toVideoItem(uploader: user.uname)
                                }
                            }
                        )
                    }
                }
            } else if module.resultType == "video" {
                VStack(spacing: 12) {
                    ForEach(module.videos) { video in
                        VideoCardSingleView(
                            video: video.toVideoItem(),
                            namespace: videoHeroNamespace,
                            onTap: { selectedVideo = video.toVideoItem() }
                        )
                    }
                }
            }
        }
    }

    private func submitKeyword(_ keyword: String) {
        searchText = keyword
        submitSearch()
    }

    private func submitSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            clearSearch()
            return
        }

        activeSearchKeyword = keyword
        selectedTab = .comprehensive
        isSearchFieldFocused = false

        Task {
            await performSearch(keyword: keyword)
        }
    }

    private func clearSearch() {
        searchText = ""
        activeSearchKeyword = nil
        searchModules = []
        searchErrorMessage = nil
        selectedTab = .comprehensive
        isSearchFieldFocused = true
    }

    private func httpsURL(from urlString: String) -> URL? {
        if urlString.hasPrefix("http://") {
            return URL(string: "https://" + urlString.dropFirst("http://".count))
        }
        return URL(string: urlString)
    }

    @MainActor
    private func loadDiscovery() async {
        isLoadingDiscovery = true
        discoveryErrorMessage = nil

        do {
            async let trending = BiliAPI.shared.fetchSearchTrending(limit: 10)
            async let recommend = BiliAPI.shared.fetchSearchRecommend()
            trendingItems = try await trending
            recommendItems = try await recommend
        } catch {
            discoveryErrorMessage = error.localizedDescription
        }

        isLoadingDiscovery = false
    }

    @MainActor
    private func performSearch(keyword: String) async {
        isSearching = true
        searchErrorMessage = nil

        do {
            searchModules = try await BiliAPI.shared.fetchComprehensiveSearch(keyword: keyword)
        } catch {
            searchModules = []
            searchErrorMessage = error.localizedDescription
        }

        isSearching = false
    }

    @MainActor
    private func focusSearchField() async {
        try? await Task.sleep(for: .milliseconds(150))
        isSearchFieldFocused = true
    }
}

private struct SearchUserSpaceRoute: Identifiable, Hashable {
    let mid: Int

    var id: Int { mid }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}

//
//  SearchView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/4.
//

import SwiftUI

struct SearchView: View {
    private let searchResultsTopID = "searchResultsTop"
    private let suggestionHighlightClass = "suggest_high_light"

    private enum SearchTab: String, CaseIterable, Identifiable {
        case comprehensive = "综合"
        case video = "视频"
        case user = "用户"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchText = ""
    @State private var searchSuggestions: [SearchSuggestItem] = []
    @State private var isLoadingSuggestions = false
    @State private var suggestionRequestID = UUID()
    @State private var trendingItems: [SearchTrendingItem] = []
    @State private var recommendItems: [SearchRecommendItem] = []
    @State private var isLoadingDiscovery = false
    @State private var discoveryErrorMessage: String?
    @State private var activeSearchKeyword: String?
    @State private var selectedTab: SearchTab = .comprehensive
    @State private var searchModules: [SearchComprehensiveModule] = []
    @State private var isSearching = false
    @State private var searchErrorMessage: String?
    @State private var didPerformInitialAutoFocus = false
    @State private var videoResults: [SearchComprehensiveVideo] = []
    @State private var userResults: [SearchComprehensiveUser] = []
    @State private var videoCurrentPage = 0
    @State private var userCurrentPage = 0
    @State private var videoHasMorePages = false
    @State private var userHasMorePages = false
    @State private var isLoadingMore = false
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

            ZStack(alignment: .top) {
                if isShowingSearchResults {
                    VStack(spacing: 0) {
                        resultTabs

                        Divider()

                        searchResultsContent
                    }
                } else {
                    discoveryContent
                }

                if shouldShowSuggestions {
                    suggestionsContent
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                        .zIndex(1)
                }
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
        .onAppear {
            guard !didPerformInitialAutoFocus else { return }
            didPerformInitialAutoFocus = true
            Task {
                await focusSearchField()
            }
        }
        .task {
            await loadDiscovery()
        }
        .onChange(of: searchText) { newValue in
            handleSearchTextChange(newValue)
        }
        .animation(.bouncy(duration: 0.42, extraBounce: 0.12), value: shouldShowSuggestions)
    }

    private var isShowingSearchResults: Bool {
        activeSearchKeyword != nil
    }

    private var shouldShowSuggestions: Bool {
        let keyword = trimmedSearchText
        guard !keyword.isEmpty else { return false }
        guard isSearchFieldFocused || activeSearchKeyword != keyword else { return false }
        return !searchSuggestions.isEmpty
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var estimatedSuggestionHeight: CGFloat {
        let rowHeight: CGFloat = 52
        let dividerHeight = max(CGFloat(searchSuggestions.count - 1), 0) * 1
        let verticalPadding: CGFloat = 12
        return CGFloat(searchSuggestions.count) * rowHeight + dividerHeight + verticalPadding
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
                        Task {
                            await loadSelectedTabIfNeeded()
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
                                                CachedAsyncImage(url: iconURL) { phase in
                                                    if case .success(let image) = phase {
                                                        image
                                                            .resizable()
                                                            .scaledToFit()
                                                    } else {
                                                        EmptyView()
                                                    }
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
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemBackground))
    }

    private var searchResultsContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Color.clear
                        .frame(height: 1)
                        .id(searchResultsTopID)

                    if isSearching {
                        ProgressView("搜索中…")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else if let searchErrorMessage {
                        Text(searchErrorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else if isCurrentTabEmpty {
                        Text("没有找到相关结果")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        switch selectedTab {
                        case .comprehensive:
                            ForEach(searchModules) { module in
                                resultModuleView(module)
                            }
                        case .video:
                            VStack(spacing: 12) {
                                ForEach(videoResults) { video in
                                    VideoCardSingleView(
                                        video: video.toVideoItem(),
                                        namespace: videoHeroNamespace,
                                        onTap: { selectedVideo = video.toVideoItem() }
                                    )
                                }
                            }
                        case .user:
                            VStack(spacing: 14) {
                                ForEach(userResults) { user in
                                    UserSmallCardView(
                                        user: user.cardUser,
                                        onTap: {
                                            selectedUserSpaceRoute = SearchUserSpaceRoute(mid: Int(user.mid))
                                        }
                                    )
                                }
                            }
                        }

                        if shouldShowPaginationSentinel {
                            paginationSentinel
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .onChange(of: selectedTab) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(searchResultsTopID, anchor: .top)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemBackground))
    }

    private var suggestionsContent: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(searchSuggestions) { item in
                        Button {
                            submitSuggestedKeyword(item.value)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)

                                suggestionText(for: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if item.id != searchSuggestions.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollDismissesKeyboard(.immediately)
            .frame(height: min(estimatedSuggestionHeight, max(proxy.size.height - 12, 0)))
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 6)
            .scaleEffect(1, anchor: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.94, anchor: .top)
                    .combined(with: .opacity)
                    .combined(with: .offset(y: -10)),
                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
            )
        )
    }

    private var shouldShowPaginationSentinel: Bool {
        switch selectedTab {
        case .comprehensive:
            return false
        case .video:
            return videoHasMorePages && !videoResults.isEmpty
        case .user:
            return userHasMorePages && !userResults.isEmpty
        }
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

    private var isCurrentTabEmpty: Bool {
        switch selectedTab {
        case .comprehensive:
            return searchModules.isEmpty
        case .video:
            return videoResults.isEmpty
        case .user:
            return userResults.isEmpty
        }
    }

    private var paginationSentinel: some View {
        Color.clear
            .frame(height: 1)
            .onAppear {
                Task { await loadMoreIfNeeded() }
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
            if module.resultType == "bili_user" {
                VStack(spacing: 14) {
                    ForEach(module.users) { user in
                        UserLargeCardView(
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

    private func submitSuggestedKeyword(_ keyword: String) {
        searchText = keyword
        searchSuggestions = []
        suggestionRequestID = UUID()
        submitSearch()
    }

    private func submitSearch() {
        let keyword = trimmedSearchText
        guard !keyword.isEmpty else {
            clearSearch()
            return
        }

        activeSearchKeyword = keyword
        selectedTab = .comprehensive
        isSearchFieldFocused = false
        resetTypedSearchState()

        Task {
            await performSearch(keyword: keyword)
        }
    }

    private func clearSearch() {
        searchText = ""
        searchSuggestions = []
        isLoadingSuggestions = false
        suggestionRequestID = UUID()
        activeSearchKeyword = nil
        searchModules = []
        searchErrorMessage = nil
        selectedTab = .comprehensive
        resetTypedSearchState()
        isSearchFieldFocused = true
    }

    private func handleSearchTextChange(_ newValue: String) {
        let keyword = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestionRequestID = UUID()

        guard !keyword.isEmpty else {
            searchSuggestions = []
            isLoadingSuggestions = false
            if activeSearchKeyword != nil, newValue.isEmpty {
                activeSearchKeyword = nil
                searchModules = []
                searchErrorMessage = nil
                selectedTab = .comprehensive
                resetTypedSearchState()
            }
            return
        }

        guard activeSearchKeyword != keyword || isSearchFieldFocused else {
            searchSuggestions = []
            isLoadingSuggestions = false
            return
        }

        let requestID = suggestionRequestID
        isLoadingSuggestions = true

        Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await loadSuggestions(for: keyword, requestID: requestID)
        }
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
    private func loadSuggestions(for keyword: String, requestID: UUID) async {
        guard requestID == suggestionRequestID else { return }

        do {
            let suggestions = try await BiliAPI.shared.fetchSearchSuggestions(term: keyword)
            guard requestID == suggestionRequestID else { return }
            searchSuggestions = suggestions
        } catch {
            guard requestID == suggestionRequestID else { return }
            searchSuggestions = []
        }

        if requestID == suggestionRequestID {
            isLoadingSuggestions = false
        }
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
    private func loadSelectedTabIfNeeded() async {
        guard let keyword = activeSearchKeyword, !isSearching else { return }

        switch selectedTab {
        case .comprehensive:
            return
        case .video where videoResults.isEmpty:
            await loadTypedVideoSearch(keyword: keyword, page: 1, append: false)
        case .user where userResults.isEmpty:
            await loadTypedUserSearch(keyword: keyword, page: 1, append: false)
        default:
            return
        }
    }

    @MainActor
    private func loadMoreIfNeeded() async {
        guard let keyword = activeSearchKeyword, !isSearching, !isLoadingMore else { return }

        switch selectedTab {
        case .comprehensive:
            return
        case .video:
            guard videoHasMorePages else { return }
            await loadTypedVideoSearch(keyword: keyword, page: videoCurrentPage + 1, append: true)
        case .user:
            guard userHasMorePages else { return }
            await loadTypedUserSearch(keyword: keyword, page: userCurrentPage + 1, append: true)
        }
    }

    @MainActor
    private func loadTypedVideoSearch(keyword: String, page: Int, append: Bool) async {
        if append {
            isLoadingMore = true
        } else {
            isSearching = true
            searchErrorMessage = nil
        }

        do {
            let payload = try await BiliAPI.shared.fetchTypedVideoSearch(keyword: keyword, page: page)
            if append {
                videoResults.append(contentsOf: payload.result)
            } else {
                videoResults = payload.result
            }
            videoCurrentPage = payload.page
            videoHasMorePages = payload.page < payload.numPages
        } catch {
            if !append {
                videoResults = []
                searchErrorMessage = error.localizedDescription
            }
        }

        isSearching = false
        isLoadingMore = false
    }

    @MainActor
    private func loadTypedUserSearch(keyword: String, page: Int, append: Bool) async {
        if append {
            isLoadingMore = true
        } else {
            isSearching = true
            searchErrorMessage = nil
        }

        do {
            let payload = try await BiliAPI.shared.fetchTypedUserSearch(keyword: keyword, page: page)
            if append {
                userResults.append(contentsOf: payload.result)
            } else {
                userResults = payload.result
            }
            userCurrentPage = payload.page
            userHasMorePages = payload.page < payload.numPages
        } catch {
            if !append {
                userResults = []
                searchErrorMessage = error.localizedDescription
            }
        }

        isSearching = false
        isLoadingMore = false
    }

    private func resetTypedSearchState() {
        videoResults = []
        userResults = []
        videoCurrentPage = 0
        userCurrentPage = 0
        videoHasMorePages = false
        userHasMorePages = false
        isLoadingMore = false
    }

    @MainActor
    private func focusSearchField() async {
        try? await Task.sleep(for: .milliseconds(150))
        isSearchFieldFocused = true
    }

    @ViewBuilder
    private func suggestionText(for item: SearchSuggestItem) -> some View {
        let source = item.name.isEmpty ? item.value : item.name
        let segments = parseSuggestionSegments(from: source)
        let resolvedSegments = segments.isEmpty ? [(item.value, false)] : segments

        resolvedSegments.reduce(Text("")) { partial, segment in
            partial + Text(SearchResultFormatter.plainText(segment.text))
                .foregroundStyle(segment.isHighlighted ? .biliPink : .primary)
        }
        .font(.system(size: 17))
    }

    private func parseSuggestionSegments(from raw: String) -> [(text: String, isHighlighted: Bool)] {
        let pattern = #"<em class="suggest_high_light">(.*?)</em>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [(raw, false)]
        }

        let nsRange = NSRange(raw.startIndex..., in: raw)
        let matches = regex.matches(in: raw, range: nsRange)
        guard !matches.isEmpty else {
            return [(raw, false)]
        }

        var segments: [(text: String, isHighlighted: Bool)] = []
        var location = raw.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: raw),
                  let highlightRange = Range(match.range(at: 1), in: raw)
            else {
                continue
            }

            if location < fullRange.lowerBound {
                segments.append((String(raw[location ..< fullRange.lowerBound]), false))
            }

            segments.append((String(raw[highlightRange]), true))
            location = fullRange.upperBound
        }

        if location < raw.endIndex {
            segments.append((String(raw[location...]), false))
        }

        return segments.isEmpty ? [(raw, false)] : segments
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

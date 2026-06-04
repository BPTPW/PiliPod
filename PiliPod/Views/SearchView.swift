//
//  SearchView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/4.
//

import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchText = ""
    @State private var trendingItems: [SearchTrendingItem] = []
    @State private var recommendItems: [SearchRecommendItem] = []
    @State private var isLoadingDiscovery = false
    @State private var discoveryErrorMessage: String?

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

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            isSearchFieldFocused = true
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
            
            Divider()

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
                                            fillKeyword(item.keyword)
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
                                            fillKeyword(item.keyword)
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
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await focusSearchField()
        }
        .task {
            await loadDiscovery()
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

    private func fillKeyword(_ keyword: String) {
        searchText = keyword
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
    private func focusSearchField() async {
        try? await Task.sleep(for: .milliseconds(150))
        isSearchFieldFocused = true
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}

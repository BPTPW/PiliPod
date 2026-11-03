import SwiftUI

/// 收藏夹内的视频列表
struct FavoriteVideoListView: View {
    let folder: FavoriteFolderItem

    @StateObject private var viewModel: FavoriteVideoListViewModel
    @Namespace private var videoHeroNamespace
    @State private var selectedVideo: VideoItem?
    @State private var searchText = ""
    @State private var isSearchPresented = false

    init(folder: FavoriteFolderItem) {
        self.folder = folder
        _viewModel = StateObject(wrappedValue: FavoriteVideoListViewModel(folderId: folder.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = viewModel.errorMessage, viewModel.videos.isEmpty {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if viewModel.videos.isEmpty {
                    Text(viewModel.keyword.isEmpty ? "收藏夹中还没有视频" : "没有找到相关内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.videos) { video in
                            VideoCardSingleView(
                                video: video,
                                namespace: videoHeroNamespace,
                                onTap: { selectedVideo = video }
                            )
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(current: video) }
                            }
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(16)
        }
        .refreshable {
            await viewModel.refresh(force: true)
        }
        .background(Color(.systemBackground))
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("搜索收藏夹内容")
        )
        .onSubmit(of: .search) {
            Task { await viewModel.applyKeyword(searchText) }
        }
        .onChange(of: searchText) { _, newValue in
            // 清除搜索框内容或点击取消时恢复完整列表
            if newValue.isEmpty {
                Task { await viewModel.applyKeyword("") }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(FavoriteVideoListViewModel.SortOption.allCases) { option in
                        Button {
                            Task { await viewModel.applySort(option) }
                        } label: {
                            if viewModel.sortOption == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }

                Button {
                    isSearchPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
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
        .task {
            await viewModel.refresh()
        }
    }
}

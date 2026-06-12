import Combine
import SwiftUI

struct PopularVideosPage: View {
    @StateObject private var viewModel = PopularVideosViewModel()

    let namespace: Namespace.ID
    let onSelectVideo: (VideoItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    ProgressView("加载热门视频中…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = viewModel.errorMessage, viewModel.videos.isEmpty {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if viewModel.videos.isEmpty {
                    Text("暂时没有热门视频")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.videos) { video in
                            VideoCardSingleView(
                                video: video,
                                namespace: namespace,
                                onTap: { onSelectVideo(video) }
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
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

@MainActor
private final class PopularVideosViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true

    private let pageSize = 20
    private var currentPage = 1
    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchPopularVideos(
                page: 1,
                pageSize: pageSize
            )
            videos.removeAll()
            videos.append(contentsOf: page.videos)
            currentPage = 1
            hasMore = !page.noMore
        } catch is CancellationError {
            return
        } catch {
            if videos.isEmpty {
                errorMessage = error.localizedDescription
                hasMore = false
            }
        }
    }

    func loadMoreIfNeeded(current item: VideoItem) async {
        guard item.id == videos.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }

        isLoading = true
        errorMessage = nil
        let nextPage = currentPage + 1
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchPopularVideos(
                page: nextPage,
                pageSize: pageSize
            )
            videos.append(contentsOf: page.videos.filter { candidate in
                !videos.contains(where: { $0.id == candidate.id })
            })
            currentPage = nextPage
            hasMore = !page.noMore
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            PopularVideosPage(namespace: namespace, onSelectVideo: { _ in })
        }
    }

    return PreviewWrapper()
}

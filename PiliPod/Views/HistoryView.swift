import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @Namespace private var videoHeroNamespace
    @State private var selectedVideo: VideoItem?

    var body: some View {
        ScrollView {
            if viewModel.errorMessage == nil && !viewModel.videos.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.videos) { video in
                        VideoCardSingleView(
                            video: video,
                            progress: video.progressSeconds,
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
            } else {
                // 防止 overlay 内容被挤压在中间
                Color.clear.frame(maxWidth: .infinity).frame(height: 1)
            }
        }
        .refreshable {
            await viewModel.refreshFromUser()
        }
        .overlay {
            if let error = viewModel.errorMessage, viewModel.videos.isEmpty {
                ContentUnavailableView {
                    Label(error, systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("重试") {
                        Task {
                            await viewModel.refreshFromUser()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            } else if !viewModel.isLoading && viewModel.errorMessage == nil && viewModel.videos.isEmpty {
                ContentUnavailableView {
                    Label("还没有观看记录", systemImage: "memories")
                }
            } else if viewModel.isLoading && viewModel.videos.isEmpty {
                ProgressView()
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("观看记录")
        .navigationBarTitleDisplayMode(.inline)
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
        .task {
            await viewModel.refresh()
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}

import SwiftUI

struct WatchLaterView: View {
    @StateObject private var viewModel = WatchLaterViewModel()
    @Namespace private var videoHeroNamespace
    @State private var selectedVideo: VideoItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    ProgressView("加载稍后再看列表中…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = viewModel.errorMessage, viewModel.videos.isEmpty {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if viewModel.videos.isEmpty {
                    Text("还没有稍后再看的内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.videos) { video in
                            VideoCardSingleView(
                                video: video,
                                progress: nil,
                                namespace: videoHeroNamespace,
                                onTap: { selectedVideo = video }
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("稍后再看")
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
        WatchLaterView()
    }
}

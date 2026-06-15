import SwiftUI

struct WatchLaterView: View {
    @StateObject private var viewModel = WatchLaterViewModel()
    @Namespace private var videoHeroNamespace
    @State private var selectedVideo: VideoItem?
    @State private var toastMessage: String?

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .watchLaterListRow()
            } else if let error = viewModel.errorMessage, viewModel.videos.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .watchLaterListRow()
            } else if viewModel.videos.isEmpty {
                Text("暂无稍后再看的内容")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .watchLaterListRow()
            } else {
                ForEach(viewModel.videos) { video in
                    VideoCardSingleView(
                        video: video,
                        progress: nil,
                        namespace: videoHeroNamespace,
                        onTap: { selectedVideo = video }
                    )
                    .padding(.vertical, 6)
                    .watchLaterListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            remove(video)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .navigationTitle("稍后再看")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toast(message: $toastMessage)
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

    private func remove(_ video: VideoItem) {
        Task {
            do {
                try await viewModel.remove(video)
            } catch {
                toastMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        WatchLaterView()
    }
}

private extension View {
    func watchLaterListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

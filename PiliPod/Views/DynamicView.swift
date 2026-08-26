import SwiftUI

struct DynamicView: View {
    @StateObject private var viewModel = DynamicViewModel()
    @State private var selectedVideo: VideoItem?
    @State private var selectedLiveRoom: LiveCardModel?
    @State private var selectedAuthorMID: Int?
    @State private var selectedDynamic: UserSpaceDynamicItem?
    @Namespace private var videoHeroNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("动态")
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.refresh() }
            .navigationDestination(item: $selectedVideo) { video in
                VideoDetailPage(
                    video: video,
                    namespace: videoHeroNamespace,
                    onBack: { selectedVideo = nil }
                )
            }
            .navigationDestination(item: $selectedLiveRoom) { room in
                LivePlaybackPage(room: room)
            }
            .navigationDestination(item: $selectedAuthorMID) { mid in
                UserSpaceView(mid: mid)
            }
            .navigationDestination(item: $selectedDynamic) { dynamic in
                UserSpaceDynamicDetailView(
                    item: dynamic,
                    onVideoTap: openVideo,
                    onLiveTap: openLive,
                    onAuthorTap: { selectedAuthorMID = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView("加载动态中…")
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            VStack(spacing: 12) {
                Text(error).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("重试") { Task { await viewModel.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if viewModel.items.isEmpty {
            Text("暂无动态").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 240)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.items) { item in
                    DynamicCardView(
                        item: item,
                        onVideoTap: openVideo,
                        onLiveTap: openLive,
                        onAuthorTap: { selectedAuthorMID = $0 },
                        onCommentTap: { _ in selectedDynamic = item },
                        onTapDetail: { selectedDynamic = item }
                    )
                    .onAppear { Task { await viewModel.loadMoreIfNeeded(current: item) } }
                }
                if viewModel.isLoading {
                    ProgressView().padding(.vertical, 8)
                } else if !viewModel.hasMore {
                    Text("没有更多动态").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                }
            }
        }
    }

    private func openVideo(_ video: UserSpaceDynamicItem.Video) {
        guard let bvid = video.bvid, !bvid.isEmpty else { return }
        selectedVideo = VideoItem(
            bvid: bvid, cid: nil, cover: video.coverURL ?? "", title: video.title,
            playCount: VideoItem.formatCount(video.playCount),
            danmakuCount: VideoItem.formatCount(video.danmakuCount), uploader: "",
            duration: video.duration, progressSeconds: nil, publishTimeText: "--",
            bottomRcmdReasonText: nil
        )
    }

    private func openLive(_ live: UserSpaceDynamicItem.Live) {
        selectedLiveRoom = LiveCardModel(
            roomId: live.roomID, uid: nil, title: live.title, coverURL: live.coverURL ?? "",
            onlineCount: live.onlineCount, anchorName: "", faceURL: "",
            areaName: live.areaName, badgeText: "直播中", link: live.link
        )
    }
}

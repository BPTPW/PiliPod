import Combine
import Foundation

@MainActor
final class WatchLaterViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await BiliAPI.shared.fetchWatchLaterList()
            videos = (data.list ?? []).map { VideoItem(from: $0) }
        } catch {
            ErrorLogService.record(error, context: "加载稍后再看")
            videos = []
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ video: VideoItem) async throws {
        let previousVideos = videos
        videos.removeAll { $0.bvid == video.bvid }

        do {
            try await BiliAPI.shared.removeFromWatchLater(bvid: video.bvid)
        } catch {
            ErrorLogService.record(error, context: "移除稍后再看")
            videos = previousVideos
            throw error
        }
    }
}

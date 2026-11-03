import Combine
import Foundation

@MainActor
final class FavoriteVideoListViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true

    private let folderId: Int64
    private let pageSize = 20
    private var currentPage = 1
    private var hasLoadedOnce = false

    init(folderId: Int64) {
        self.folderId = folderId
    }

    func refresh(force: Bool = false) async {
        guard force || !hasLoadedOnce, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await BiliAPI.shared.fetchFavoriteResources(
                mediaId: folderId,
                pn: 1,
                ps: pageSize
            )
            currentPage = 1
            videos = Self.videoItems(from: data.medias ?? [])
            hasMore = data.hasMore ?? false
            hasLoadedOnce = true
        } catch {
            ErrorLogService.record(error, context: "加载收藏夹内容")
            if videos.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreIfNeeded(current video: VideoItem) async {
        guard hasMore, !isLoading, video.id == videos.last?.id else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await BiliAPI.shared.fetchFavoriteResources(
                mediaId: folderId,
                pn: currentPage + 1,
                ps: pageSize
            )
            currentPage += 1
            let existing = Set(videos.map(\.id))
            videos.append(
                contentsOf: Self.videoItems(from: data.medias ?? []).filter { !existing.contains($0.id) }
            )
            hasMore = data.hasMore ?? false
        } catch {
            ErrorLogService.record(error, context: "加载更多收藏夹内容")
        }
    }

    private static func videoItems(from medias: [FavoriteResourceItem]) -> [VideoItem] {
        medias.filter(\.isPlayableVideo).map { VideoItem(from: $0) }
    }
}

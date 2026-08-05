import Combine
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true

    private var nextCursor: HistoryCursor?
    private let pageSize = 20
    private let type = "archive"

    func refresh() async {
        isLoading = true
        errorMessage = nil
        hasMore = true
        nextCursor = nil
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchHistoryList(type: type, ps: pageSize)
            let items = (page.list ?? []).filter { $0.history?.business == type }
            videos = items.map { VideoItem(from: $0) }
            nextCursor = page.cursor
            hasMore = shouldLoadMore(items: items, cursor: page.cursor)
        } catch {
            ErrorLogService.record(error, context: "加载观看历史")
            videos = []
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }

    func loadMoreIfNeeded(current item: VideoItem) async {
        guard item.id == videos.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, hasMore, let cursor = nextCursor else { return }
        guard let max = cursor.max, let viewAt = cursor.viewAt else {
            hasMore = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchHistoryList(
                max: max,
                business: cursor.business,
                viewAt: viewAt,
                type: type,
                ps: pageSize
            )
            let items = (page.list ?? []).filter { $0.history?.business == type }
            let moreVideos = items.map { VideoItem(from: $0) }

            videos.append(contentsOf: moreVideos.filter { candidate in
                !videos.contains(where: { $0.id == candidate.id })
            })
            nextCursor = page.cursor
            hasMore = shouldLoadMore(items: items, cursor: page.cursor)
        } catch {
            ErrorLogService.record(error, context: "加载更多观看历史")
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }

    private func shouldLoadMore(items: [HistoryItem], cursor: HistoryCursor?) -> Bool {
        guard !items.isEmpty else { return false }
        return cursor?.viewAt != nil
    }
}

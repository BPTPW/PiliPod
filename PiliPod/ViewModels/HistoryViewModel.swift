import Combine
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true

    private var nextCursor: HistoryCursor?
    private var hasLoadedOnce = false
    private let pageSize = 20
    private let type = "archive"

    func refreshFromUser() async {
        let task = Task { @MainActor in
            await refresh(force: true)
        }
        await task.value
    }

    func refresh(force: Bool = false) async {
        guard force || !hasLoadedOnce else { return }

        // 首次加载或分页请求尚未结束时，等待它完成后再执行用户主动刷新，
        // 避免 refreshable 因 isLoading 直接返回而看起来没有反应。
        while isLoading {
            guard !Task.isCancelled else { return }
            await Task.yield()
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchHistoryList(type: type, ps: pageSize)
            let items = (page.list ?? []).filter { $0.history?.business == type }
            videos = items.map { VideoItem(from: $0) }
            nextCursor = page.cursor
            hasMore = shouldLoadMore(items: items, cursor: page.cursor)
            hasLoadedOnce = true
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                // 下拉刷新任务可能因手势结束或页面离开而被取消，不应清空现有列表。
                return
            }
            ErrorLogService.record(error, context: "加载观看历史")
            // 已有内容时刷新失败仍保留旧列表，仅提示错误；首次加载失败才显示空状态。
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
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
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

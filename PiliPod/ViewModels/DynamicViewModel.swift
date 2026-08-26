import Combine
import Foundation

@MainActor
final class DynamicViewModel: ObservableObject {
    @Published private(set) var items: [UserSpaceDynamicItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = true

    private var offset: String?

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        offset = nil
        hasMore = true
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchAllDynamics()
            items = page.items
            offset = page.nextOffset
            hasMore = page.hasMore && page.nextOffset != nil && !page.items.isEmpty
        } catch is CancellationError {
            // 下拉刷新或页面离开时，SwiftUI 可能取消当前任务。
            // 取消不是网络错误，不应显示“已取消”并覆盖已有内容。
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            ErrorLogService.record(error, context: "加载全部动态")
            items = []
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }

    func loadMoreIfNeeded(current item: UserSpaceDynamicItem) async {
        guard item.id == items.last?.id else { return }
        guard !isLoading, hasMore, let offset else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await BiliAPI.shared.fetchAllDynamics(offset: offset)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            self.offset = page.nextOffset
            hasMore = page.hasMore && page.nextOffset != nil && !page.items.isEmpty
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            ErrorLogService.record(error, context: "加载更多全部动态")
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }
}

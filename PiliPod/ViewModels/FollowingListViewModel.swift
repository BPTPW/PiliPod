import Combine
import Foundation

@MainActor
final class FollowingListViewModel: ObservableObject {
    enum SortOption: String, CaseIterable, Identifiable {
        case followSequence = "关注顺序"
        case frequentlyVisited = "最常访问"

        var id: String { rawValue }

        var orderType: String? {
            switch self {
            case .followSequence:
                return nil
            case .frequentlyVisited:
                return "attention"
            }
        }
    }

    @Published var users: [FollowingUser] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true
    @Published var sortOption: SortOption = .followSequence
    @Published private(set) var searchUsers: [FollowingUser] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchErrorMessage: String?
    @Published private(set) var searchKeyword: String?

    private let mid: Int
    private let pageSize = 50
    private var currentPage = 1
    private var totalCount = 0
    private var searchRequestID = UUID()

    init(mid: Int) {
        self.mid = mid
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        hasMore = true
        currentPage = 1
        totalCount = 0
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchFollowingList(
                vmid: mid,
                pn: currentPage,
                ps: pageSize,
                orderType: sortOption.orderType
            )
            let items = page.list ?? []
            users = items
            totalCount = page.total
            hasMore = shouldLoadMore(loadedCount: items.count, receivedCount: items.count)
        } catch {
            ErrorLogService.record(error, context: "加载关注列表")
            users = []
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let nextPage = currentPage + 1
            let page = try await BiliAPI.shared.fetchFollowingList(
                vmid: mid,
                pn: nextPage,
                ps: pageSize,
                orderType: sortOption.orderType
            )
            let items = page.list ?? []
            currentPage = nextPage
            totalCount = page.total

            let existingIDs = Set(users.map(\.id))
            let deduped = items.filter { !existingIDs.contains($0.id) }
            users.append(contentsOf: deduped)
            hasMore = shouldLoadMore(loadedCount: users.count, receivedCount: items.count)
        } catch {
            ErrorLogService.record(error, context: "加载更多关注")
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }

    func search(keyword: String) async {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else {
            return
        }

        let requestID = UUID()
        searchRequestID = requestID
        searchKeyword = trimmedKeyword
        isSearching = true
        searchErrorMessage = nil
        searchUsers = []

        do {
            let page = try await BiliAPI.shared.searchFollowingList(
                vmid: mid,
                keyword: trimmedKeyword,
                ps: pageSize
            )
            guard searchRequestID == requestID else { return }
            searchUsers = page.list ?? []
        } catch {
            guard searchRequestID == requestID else { return }
            ErrorLogService.record(error, context: "搜索关注列表")
            searchErrorMessage = error.localizedDescription
        }

        guard searchRequestID == requestID else { return }
        isSearching = false
    }

    func clearSearch() {
        searchRequestID = UUID()
        searchKeyword = nil
        searchUsers = []
        searchErrorMessage = nil
        isSearching = false
    }

    private func shouldLoadMore(loadedCount: Int, receivedCount: Int) -> Bool {
        guard receivedCount > 0 else { return false }
        guard totalCount > 0 else { return receivedCount >= pageSize }
        return loadedCount < totalCount
    }
}

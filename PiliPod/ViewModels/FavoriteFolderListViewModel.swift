import Combine
import Foundation

@MainActor
final class FavoriteFolderListViewModel: ObservableObject {
    @Published var folders: [FavoriteFolderItem] = []
    @Published var totalCount = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true

    private let pageSize = 20
    private var currentPage = 1

    func refresh() async {
        guard !isLoading else { return }
        guard let mid = Self.currentUserMid() else {
            folders = []
            totalCount = 0
            hasMore = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchFavoriteFolderPage(
                upMid: mid,
                pn: 1,
                ps: pageSize
            )
            currentPage = 1
            folders = page.list ?? []
            totalCount = page.count
            hasMore = page.hasMore ?? false
        } catch {
            ErrorLogService.record(error, context: "加载收藏夹列表")
            if folders.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreIfNeeded(current folder: FavoriteFolderItem) async {
        guard hasMore, !isLoading, folder.id == folders.last?.id else { return }
        guard let mid = Self.currentUserMid() else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchFavoriteFolderPage(
                upMid: mid,
                pn: currentPage + 1,
                ps: pageSize
            )
            currentPage += 1
            let existing = Set(folders.map(\.id))
            folders.append(contentsOf: (page.list ?? []).filter { !existing.contains($0.id) })
            totalCount = page.count
            hasMore = page.hasMore ?? false
        } catch {
            ErrorLogService.record(error, context: "加载更多收藏夹")
        }
    }

    private static func currentUserMid() -> Int64? {
        guard LoginSession.shared.isLogin,
              let uid = LoginSession.shared.cookies?.DedeUserID
        else { return nil }
        return Int64(uid)
    }
}

import Combine
import Foundation

@MainActor
final class FavoriteVideoListViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true
    @Published var sortOption: SortOption = .favoriteTime
    @Published private(set) var keyword = ""

    enum SortOption: String, CaseIterable, Identifiable {
        case favoriteTime = "mtime"
        case playCount = "view"
        case publishTime = "pubtime"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .favoriteTime: return L10n.string("按收藏时间")
            case .playCount: return L10n.string("按播放量")
            case .publishTime: return L10n.string("按投稿时间")
            }
        }
    }

    private let folderId: Int64
    private let pageSize = 20
    private var currentPage = 1
    private var hasLoadedOnce = false
    private var requestSerial = 0

    init(folderId: Int64) {
        self.folderId = folderId
    }

    func applySort(_ option: SortOption) async {
        guard option != sortOption else { return }
        sortOption = option
        await refresh(force: true)
    }

    func applyKeyword(_ newKeyword: String) async {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != keyword else { return }
        keyword = trimmed
        await refresh(force: true)
    }

    func refresh(force: Bool = false) async {
        guard force || !hasLoadedOnce else { return }
        // 切换排序/搜索时取消不了旧请求，用序号丢弃过期结果
        guard !isLoading || force else { return }
        requestSerial += 1
        let serial = requestSerial
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await BiliAPI.shared.fetchFavoriteResources(
                mediaId: folderId,
                pn: 1,
                ps: pageSize,
                keyword: keyword,
                order: sortOption.rawValue
            )
            guard serial == requestSerial else { return }
            currentPage = 1
            videos = Self.videoItems(from: data.medias ?? [])
            hasMore = data.hasMore ?? false
            hasLoadedOnce = true
        } catch {
            guard serial == requestSerial else { return }
            ErrorLogService.record(error, context: "加载收藏夹内容")
            videos = []
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current video: VideoItem) async {
        guard hasMore, !isLoading, video.id == videos.last?.id else { return }
        isLoading = true
        let serial = requestSerial
        defer { isLoading = false }

        do {
            let data = try await BiliAPI.shared.fetchFavoriteResources(
                mediaId: folderId,
                pn: currentPage + 1,
                ps: pageSize,
                keyword: keyword,
                order: sortOption.rawValue
            )
            guard serial == requestSerial else { return }
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

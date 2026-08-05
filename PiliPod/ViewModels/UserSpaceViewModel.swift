import Combine
import Foundation

@MainActor
final class UserSpaceViewModel: ObservableObject {
    @Published var data: UserSpaceData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isFollowRequesting = false
    @Published var archiveVideos: [VideoItem] = []
    @Published var archiveIsLoading = false
    @Published var archiveErrorMessage: String?
    @Published var archiveHasMore = true

    private var archiveNextAid: Int?
    private var archiveMid: Int?

    func load(mid: Int, fromViewAid: Int?) async {
        archiveMid = mid
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            data = try await BiliAPI.shared.fetchUserSpace(mid: mid, fromViewAid: fromViewAid)
            await refreshArchive()
        } catch {
            ErrorLogService.record(error, context: "加载用户空间")
            data = nil
            errorMessage = error.localizedDescription
        }
    }

    func refreshArchive() async {
        guard let mid = archiveMid else { return }

        archiveIsLoading = true
        archiveErrorMessage = nil
        archiveHasMore = true
        archiveNextAid = nil
        defer { archiveIsLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchSpaceArchiveCursor(
                mid: mid,
                aid: nil,
                order: "pubdate",
                ps: 20,
                qn: 80
            )
            let items = page.item ?? []
            archiveVideos = items.map { VideoItem(from: $0) }
            archiveNextAid = items.last?.resolvedAid
            archiveHasMore = (page.hasNext ?? false) && archiveNextAid != nil && !items.isEmpty
        } catch {
            ErrorLogService.record(error, context: "加载用户投稿")
            archiveVideos = []
            archiveErrorMessage = error.localizedDescription
            archiveHasMore = false
        }
    }

    func loadMoreArchiveIfNeeded(current item: VideoItem) async {
        guard item.id == archiveVideos.last?.id else { return }
        await loadMoreArchive()
    }

    func loadMoreArchive() async {
        guard let mid = archiveMid else { return }
        print(archiveHasMore)
        guard !archiveIsLoading, archiveHasMore, let aid = archiveNextAid else { return }

        archiveIsLoading = true
        defer { archiveIsLoading = false }

        do {
            let page = try await BiliAPI.shared.fetchSpaceArchiveCursor(
                mid: mid,
                aid: aid,
                order: "pubdate",
                ps: 20,
                qn: 80
            )
            let items = page.item ?? []
            let more = items.map { VideoItem(from: $0) }
            archiveVideos.append(contentsOf: more)
            archiveNextAid = items.last?.resolvedAid
            archiveHasMore = (page.hasNext ?? false) && archiveNextAid != nil && !items.isEmpty
        } catch {
            ErrorLogService.record(error, context: "加载更多用户投稿")
            archiveErrorMessage = error.localizedDescription
            archiveHasMore = false
        }
    }

    var coverURL: URL? {
        guard let raw = data?.images?.imgURL, let url = URL(string: raw) else { return nil }
        return url
    }

    var avatarURL: URL? {
        guard let raw = data?.card?.face, let url = URL(string: raw) else { return nil }
        return url
    }

    var displayName: String { data?.card?.name ?? "用户名称" }
    var signature: String { data?.card?.sign?.isEmpty == false ? data?.card?.sign ?? "" : "这个人很神秘，什么都没有写。" }
    var uidText: String { data?.card?.mid ?? "-" }

    var ipLocationText: String {
        let raw = data?.card?.spaceTag?.first(where: { $0.type == "location" })?.title ?? ""
        return normalizeIPLocation(raw)
    }

    var fansText: String { formatCount(data?.card?.fans) }
    var attentionText: String { formatCount(data?.card?.attention) }
    var likesText: String { formatCount(data?.card?.likes?.likeNum) }

    var isFollowed: Bool { (data?.card?.relation?.isFollow ?? 0) == 1 }
    var isLiveNow: Bool { data?.live?.liveStatus == 1 }
    var liveRoomID: String? {
        guard isLiveNow, let roomID = data?.live?.roomID, roomID > 0 else { return nil }
        return String(roomID)
    }

    var liveRoomModel: LiveCardModel? {
        guard let roomId = liveRoomID else { return nil }
        return LiveCardModel(
            roomId: roomId,
            uid: Int(data?.card?.mid ?? ""),
            title: displayName,
            coverURL: "",
            onlineCount: "",
            anchorName: displayName,
            faceURL: data?.card?.face ?? "",
            areaName: "",
            badgeText: "直播中",
            link: nil
        )
    }

    func toggleFollow() async throws {
        guard !isFollowRequesting else { return }
        guard let midText = data?.card?.mid, let fid = Int(midText), fid > 0 else { return }

        isFollowRequesting = true
        let wasFollowed = isFollowed
        let previousFans = data?.card?.fans

        if wasFollowed {
            data?.card?.relation?.isFollow = 0
            if let fans = data?.card?.fans {
                data?.card?.fans = max(0, fans - 1)
            }
        } else {
            data?.card?.relation?.isFollow = 1
            if let fans = data?.card?.fans {
                data?.card?.fans = fans + 1
            }
        }

        do {
            let act = wasFollowed ? 2 : 1
            try await BiliAPI.shared.modifyUserRelation(fid: fid, act: act)
        } catch {
            ErrorLogService.record(error, context: "关注用户")
            data?.card?.relation?.isFollow = wasFollowed ? 1 : 0
            data?.card?.fans = previousFans
            isFollowRequesting = false
            throw error
        }

        isFollowRequesting = false
    }

    private func formatCount(_ value: Int?) -> String {
        guard let value else { return "-" }
        return value.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func normalizeIPLocation(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未知" }

        let prefixes = ["IP属地：", "IP属地:", "ip属地：", "ip属地:"]
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "未知" : value
        }

        return trimmed
    }
}

private extension VideoItem {
    init(from archive: SpaceArchiveItem) {
        let bvid = archive.bvid ?? ""
        self.bvid = bvid.isEmpty ? "av\(archive.aid ?? 0)" : bvid
        self.cid = archive.firstCid
        self.cover = (archive.cover ?? "").replacingOccurrences(of: "http://", with: "https://")
        self.title = archive.title ?? ""
        self.playCount = Self.formatCount(archive.play ?? 0)
        self.danmakuCount = Self.formatCount(archive.danmaku ?? 0)
        self.uploader = ""
        self.duration = archive.duration ?? 0
        self.progressSeconds = nil
        self.publishTimeText = archive.publishTimeText ?? "--"
        self.bottomRcmdReasonText = nil
    }
}

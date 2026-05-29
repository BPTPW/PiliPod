import Combine
import Foundation

@MainActor
final class UserSpaceViewModel: ObservableObject {
    @Published var data: UserSpaceData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isFollowRequesting = false

    func load(mid: Int, fromViewAid: Int?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            data = try await BiliAPI.shared.fetchUserSpace(mid: mid, fromViewAid: fromViewAid)
        } catch {
            data = nil
            errorMessage = error.localizedDescription
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
            data?.card?.relation?.isFollow = wasFollowed ? 1 : 0
            data?.card?.fans = previousFans
            isFollowRequesting = false
            throw error
        }

        isFollowRequesting = false
    }

    private func formatCount(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000.0)
        }
        return "\(value)"
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

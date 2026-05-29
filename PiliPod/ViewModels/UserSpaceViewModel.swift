import Combine
import Foundation

@MainActor
final class UserSpaceViewModel: ObservableObject {
    @Published var data: UserSpaceData?
    @Published var isLoading = false
    @Published var errorMessage: String?

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
        data?.card?.spaceTag?.first(where: { $0.type == "location" })?.title ?? "未知"
    }

    var fansText: String { formatCount(data?.card?.fans) }
    var attentionText: String { formatCount(data?.card?.attention) }
    var likesText: String { formatCount(data?.card?.likes?.likeNum) }

    var isFollowed: Bool { (data?.card?.relation?.isFollow ?? 0) == 1 }

    private func formatCount(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000.0)
        }
        return "\(value)"
    }
}

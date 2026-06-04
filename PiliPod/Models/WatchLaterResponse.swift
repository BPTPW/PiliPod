import Foundation

struct WatchLaterResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: WatchLaterData?
}

struct WatchLaterData: Codable {
    let count: Int?
    let list: [WatchLaterItem]?
}

struct WatchLaterItem: Codable {
    let aid: Int?
    let bvid: String
    let title: String
    let pic: String
    let duration: Int
    let pubdate: Int?
    let addAt: Int?
    let owner: WatchLaterOwner?
    let stat: WatchLaterStat?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, pic, duration, pubdate
        case addAt = "add_at"
        case owner, stat
    }
}

struct WatchLaterOwner: Codable {
    let mid: Int?
    let name: String?
    let face: String?
}

struct WatchLaterStat: Codable {
    let view: Int?
    let danmaku: Int?
}

extension VideoItem {
    init(from watchLater: WatchLaterItem) {
        self.bvid = watchLater.bvid
        self.cid = nil
        self.cover = watchLater.pic.replacingOccurrences(of: "http://", with: "https://")
        self.title = watchLater.title
        self.playCount = Self.formatCount(watchLater.stat?.view ?? 0)
        self.danmakuCount = Self.formatCount(watchLater.stat?.danmaku ?? 0)
        self.uploader = watchLater.owner?.name ?? ""
        self.duration = watchLater.duration
        self.progressSeconds = nil
        self.publishTimeText = Self.formatHistoryTimestamp(watchLater.addAt)
        self.bottomRcmdReasonText = nil
    }
}

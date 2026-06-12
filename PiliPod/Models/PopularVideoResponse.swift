import Foundation

struct PopularVideoResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: PopularVideoData?
}

struct PopularVideoData: Codable {
    let list: [PopularVideo]
    let noMore: Bool

    enum CodingKeys: String, CodingKey {
        case list
        case noMore = "no_more"
    }
}

struct PopularVideo: Codable {
    let bvid: String
    let cid: Int?
    let title: String
    let pic: String
    let duration: Int
    let pubdate: Int?
    let owner: Owner
    let stat: Stat
}

extension VideoItem {
    init(from popularVideo: PopularVideo) {
        self.bvid = popularVideo.bvid
        self.cid = popularVideo.cid
        self.cover = popularVideo.pic.replacingOccurrences(of: "http://", with: "https://")
        self.title = popularVideo.title
        self.playCount = Self.formatCount(popularVideo.stat.view)
        self.danmakuCount = Self.formatCount(popularVideo.stat.danmaku)
        self.uploader = popularVideo.owner.name
        self.duration = popularVideo.duration
        self.progressSeconds = nil
        self.publishTimeText = Self.formatTimestamp(popularVideo.pubdate)
        self.bottomRcmdReasonText = nil
    }
}

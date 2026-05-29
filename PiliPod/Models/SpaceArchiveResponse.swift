import Foundation

struct SpaceArchiveResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: SpaceArchiveData?
}

struct SpaceArchiveData: Codable {
    let count: Int?
    let item: [SpaceArchiveItem]?
    let hasNext: Bool?
    let hasPrev: Bool?
    let next: Int?

    enum CodingKeys: String, CodingKey {
        case count
        case item
        case hasNext = "has_next"
        case hasPrev = "has_prev"
        case next
    }
}

struct SpaceArchiveItem: Codable {
    let aid: Int?
    let bvid: String?
    let firstCid: Int?
    let cover: String?
    let title: String?
    let duration: Int?
    let play: Int?
    let danmaku: Int?
    let author: String?
    let publishTimeText: String?

    enum CodingKeys: String, CodingKey {
        case aid
        case bvid
        case firstCid = "first_cid"
        case cover
        case title
        case duration
        case play
        case danmaku
        case author
        case publishTimeText = "publish_time_text"
    }

    var resolvedAid: Int? {
        if let aid {
            return aid
        }
        guard let bvid, !bvid.isEmpty else {
            return nil
        }
        return Int(BiliIdConverter.bv2av(bvid: bvid))
    }
}

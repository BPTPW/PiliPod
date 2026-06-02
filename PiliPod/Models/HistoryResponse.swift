import Foundation

struct HistoryResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: HistoryData?
}

struct HistoryData: Codable {
    let cursor: HistoryCursor?
    let tab: [HistoryTabItem]?
    let list: [HistoryItem]?
}

struct HistoryCursor: Codable {
    let max: Int?
    let viewAt: Int?
    let business: String?
    let ps: Int?

    enum CodingKeys: String, CodingKey {
        case max
        case viewAt = "view_at"
        case business
        case ps
    }
}

struct HistoryTabItem: Codable {
    let type: String?
    let name: String?
}

struct HistoryItem: Codable {
    let title: String?
    let longTitle: String?
    let cover: String?
    let authorName: String?
    let viewAt: Int?
    let progress: Int?
    let badge: String?
    let showTitle: String?
    let duration: Int?
    let kid: Int?
    let history: HistoryDetail?

    enum CodingKeys: String, CodingKey {
        case title
        case longTitle = "long_title"
        case cover
        case authorName = "author_name"
        case viewAt = "view_at"
        case progress
        case badge
        case showTitle = "show_title"
        case duration
        case kid
        case history
    }
}

struct HistoryDetail: Codable {
    let oid: Int?
    let bvid: String?
    let page: Int?
    let cid: Int?
    let part: String?
    let business: String?
}

import Foundation

struct SearchTrendingResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: SearchTrendingData?
}

struct SearchTrendingData: Codable {
    let trackid: String?
    let list: [SearchTrendingItem]
}

struct SearchTrendingItem: Codable, Identifiable {
    let position: Int
    let keyword: String
    let showName: String
    let wordType: Int?
    let icon: String?
    let hotID: Int?

    var id: String { "\(position)-\(keyword)" }

    enum CodingKeys: String, CodingKey {
        case position
        case keyword
        case showName = "show_name"
        case wordType = "word_type"
        case icon
        case hotID = "hot_id"
    }
}

struct SearchRecommendResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: SearchRecommendData?
}

struct SearchRecommendData: Codable {
    let trackid: String?
    let list: [SearchRecommendItem]
}

struct SearchRecommendItem: Codable, Identifiable {
    let rawID: Int64?
    let position: Int?
    let keyword: String
    let showName: String
    let recommendReason: String?

    var stableID: String {
        if let rawID {
            return String(rawID)
        }
        return "\(position ?? 0)-\(keyword)"
    }

    var id: String { stableID }

    enum CodingKeys: String, CodingKey {
        case rawID = "id"
        case position
        case keyword
        case showName = "show_name"
        case recommendReason = "recommend_reason"
    }
}

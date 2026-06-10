import Foundation

struct UserSpaceResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: UserSpaceData?
}

struct UserSpaceData: Codable {
    let defaultTab: String?
    var card: UserSpaceCard?
    let images: UserSpaceImages?
    let live: UserSpaceLive?

    enum CodingKeys: String, CodingKey {
        case defaultTab = "default_tab"
        case card
        case images
        case live
    }
}

struct UserSpaceImages: Codable {
    let imgURL: String?

    enum CodingKeys: String, CodingKey {
        case imgURL = "imgUrl"
    }
}

struct UserSpaceCard: Codable {
    let mid: String?
    let name: String?
    let face: String?
    var fans: Int?
    let attention: Int?
    let sign: String?
    let likes: UserSpaceLikes?
    var relation: UserSpaceRelation?
    let spaceTag: [UserSpaceTag]?

    enum CodingKeys: String, CodingKey {
        case mid
        case name
        case face
        case fans
        case attention
        case sign
        case likes
        case relation
        case spaceTag = "space_tag"
    }
}

struct UserSpaceLikes: Codable {
    let likeNum: Int?

    enum CodingKeys: String, CodingKey {
        case likeNum = "like_num"
    }
}

struct UserSpaceRelation: Codable {
    var isFollow: Int?

    enum CodingKeys: String, CodingKey {
        case isFollow = "is_follow"
    }
}

struct UserSpaceTag: Codable {
    let type: String?
    let title: String?
}

struct UserSpaceLive: Codable {
    let liveStatus: Int?
    let roomID: Int?

    enum CodingKeys: String, CodingKey {
        case liveStatus
        case roomID = "roomid"
    }
}

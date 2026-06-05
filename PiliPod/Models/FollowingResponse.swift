import Foundation

struct FollowingResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: FollowingData?
}

struct FollowingData: Codable {
    let list: [FollowingUser]?
    let reVersion: Int?
    let total: Int

    enum CodingKeys: String, CodingKey {
        case list
        case reVersion = "re_version"
        case total
    }
}

struct FollowingUser: Codable, Identifiable, Hashable {
    let mid: Int
    let attribute: Int?
    let mtime: Int?
    let special: Int?
    let uname: String
    let face: String
    let sign: String
    let followTime: String?

    enum CodingKeys: String, CodingKey {
        case mid
        case attribute
        case mtime
        case special
        case uname
        case face
        case sign
        case followTime = "follow_time"
    }

    var id: Int { mid }

    var cardUser: SearchUserLargeCardUser {
        SearchUserLargeCardUser(
            id: String(mid),
            name: uname,
            avatarURL: face,
            followerCount: 0,
            videoCount: 0
        )
    }
}

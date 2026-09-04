//
//  ActionResponses.swift
//  PiliPod
//
//  Created by co on 2026/5/25.
//

import Foundation

struct SimpleAPIResponse<T: Codable>: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: T?
}

struct MessageFeedUnreadData: Codable {
    let coin: Int
    let danmu: Int
    let favorite: Int
    let recvLike: Int
    let recvReply: Int
    let sysMsg: Int
    let up: Int
    let reply: Int
    let at: Int

    var total: Int {
        coin + danmu + favorite + recvLike + recvReply + sysMsg + up
    }

    enum CodingKeys: String, CodingKey {
        case coin
        case danmu
        case favorite
        case recvLike = "recv_like"
        case recvReply = "recv_reply"
        case sysMsg = "sys_msg"
        case up
        case reply
        case at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decodeIfPresent(Int.self, forKey: .coin) ?? 0
        danmu = try container.decodeIfPresent(Int.self, forKey: .danmu) ?? 0
        favorite = try container.decodeIfPresent(Int.self, forKey: .favorite) ?? 0
        recvLike = try container.decodeIfPresent(Int.self, forKey: .recvLike) ?? 0
        recvReply = try container.decodeIfPresent(Int.self, forKey: .recvReply) ?? 0
        sysMsg = try container.decodeIfPresent(Int.self, forKey: .sysMsg) ?? 0
        up = try container.decodeIfPresent(Int.self, forKey: .up) ?? 0
        reply = try container.decodeIfPresent(Int.self, forKey: .reply) ?? 0
        at = try container.decodeIfPresent(Int.self, forKey: .at) ?? 0
    }
}

struct MessageUnreadCounts: Sendable {
    let reply: Int
    let at: Int
    let receivedLike: Int
    let total: Int
}

struct MessageFeedUser: Codable, Hashable {
    let mid: Int
    let nickname: String
    let avatar: String

    enum CodingKeys: String, CodingKey {
        case mid, nickname, avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = try container.decodeIfPresent(Int.self, forKey: .mid) ?? 0
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname) ?? "未知用户"
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
    }
}

struct MessageFeedAtDetail: Codable, Hashable {
    let mid: Int
    let nickname: String

    enum CodingKeys: String, CodingKey { case mid, nickname }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = try container.decodeIfPresent(Int.self, forKey: .mid) ?? 0
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname) ?? ""
    }
}

struct MessageFeedItem: Codable, Hashable {
    let type: String
    let business: String
    let title: String
    let image: String
    let uri: String
    let sourceContent: String
    let atDetails: [MessageFeedAtDetail]

    enum CodingKeys: String, CodingKey {
        case type, business, title, image, uri
        case sourceContent = "source_content"
        case atDetails = "at_details"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "video"
        business = try container.decodeIfPresent(String.self, forKey: .business) ?? "视频"
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        image = try container.decodeIfPresent(String.self, forKey: .image) ?? ""
        uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? ""
        sourceContent = try container.decodeIfPresent(String.self, forKey: .sourceContent) ?? ""
        atDetails = try container.decodeIfPresent([MessageFeedAtDetail].self, forKey: .atDetails) ?? []
    }
}

struct ReplyMessageFeedItem: Codable, Hashable {
    let id: Int
    let user: MessageFeedUser
    let item: MessageFeedItem
    let replyTime: Int

    enum CodingKeys: String, CodingKey {
        case id, user, item
        case replyTime = "reply_time"
    }
}

struct AtMessageFeedItem: Codable, Hashable {
    let id: Int
    let user: MessageFeedUser
    let item: MessageFeedItem
    let atTime: Int

    enum CodingKeys: String, CodingKey {
        case id, user, item
        case atTime = "at_time"
    }
}

struct LikeMessageFeedItem: Codable, Hashable {
    let id: Int
    let users: [MessageFeedUser]
    let item: MessageFeedItem
    let counts: Int
    let likeTime: Int

    enum CodingKeys: String, CodingKey {
        case id, users, item, counts
        case likeTime = "like_time"
    }
}

struct MessageFeedCursor: Codable {
    let isEnd: Bool
    let id: Int
    let time: Int

    enum CodingKeys: String, CodingKey {
        case isEnd = "is_end"
        case id, time
    }
}

struct ReplyMessageFeedData: Codable {
    let cursor: MessageFeedCursor
    let items: [ReplyMessageFeedItem]
}

struct AtMessageFeedData: Codable {
    let cursor: MessageFeedCursor
    let items: [AtMessageFeedItem]
}

struct LikeMessageFeedTotal: Codable {
    let cursor: MessageFeedCursor
    let items: [LikeMessageFeedItem]
}

struct LikeMessageFeedData: Codable {
    let total: LikeMessageFeedTotal
}

struct PrivateMessageUnreadData: Codable {
    let unfollowUnread: Int
    let followUnread: Int
    let unfollowPushMsg: Int
    let dustbinPushMsg: Int
    let dustbinUnread: Int
    let bizMsgUnfollowUnread: Int
    let bizMsgFollowUnread: Int
    let customUnread: Int

    var total: Int {
        unfollowUnread + followUnread + unfollowPushMsg + dustbinPushMsg
            + dustbinUnread + bizMsgUnfollowUnread + bizMsgFollowUnread + customUnread
    }

    enum CodingKeys: String, CodingKey {
        case unfollowUnread = "unfollow_unread"
        case followUnread = "follow_unread"
        case unfollowPushMsg = "unfollow_push_msg"
        case dustbinPushMsg = "dustbin_push_msg"
        case dustbinUnread = "dustbin_unread"
        case bizMsgUnfollowUnread = "biz_msg_unfollow_unread"
        case bizMsgFollowUnread = "biz_msg_follow_unread"
        case customUnread = "custom_unread"
    }
}

struct LikeToastData: Codable {
    let toast: String?
}

struct CoinAddData: Codable {
    let like: Bool?
}

struct FavoriteDealData: Codable {
    let prompt: Bool?
}

struct TripleLikeData: Codable {
    let like: Bool
    let coin: Bool
    let fav: Bool
    let multiply: Int?
}

struct TripleLikeVisualState: Sendable {
    let isLiked: Bool
    let isCoined: Bool
    let isFavorited: Bool
}

struct SkipSegment: Codable, Identifiable {
    let segment: [Double]
    let cid: String
    let segmentID: String
    let category: String
    let actionType: String
    let locked: Int
    let votes: Int
    let videoDuration: Double
    let description: String?

    var id: String { segmentID }

    enum CodingKeys: String, CodingKey {
        case segment
        case cid
        case segmentID = "UUID"
        case category
        case actionType
        case locked
        case votes
        case videoDuration
        case description
    }
}

struct SubmittedSkipSegment: Codable, Identifiable {
    let segmentID: String
    let category: String
    let segment: [Double]

    var id: String { segmentID }

    enum CodingKeys: String, CodingKey {
        case segmentID = "UUID"
        case category
        case segment
    }
}

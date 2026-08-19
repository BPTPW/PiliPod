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
    }
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

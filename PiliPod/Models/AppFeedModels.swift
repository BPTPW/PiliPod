//
//  AppFeedModels.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import Foundation

// MARK: - App 推荐接口顶层响应

struct AppFeedResponse: Codable {
    let code: Int
    let message: String
    let data: AppFeedData?
}

struct AppFeedData: Codable {
    let items: [AppFeedRawItem]?
    let config: AppFeedConfig?
}

struct AppFeedConfig: Codable {
    let idx: Int?
}

// MARK: - 原始 Feed 卡片（对应 JSON 中 items 数组元素）

struct AppFeedRawItem: Codable {
    let cardType: String?
    let cardGoto: String?
    let goto: String?
    let param: String?
    let title: String?
    let cover: String?
    let uri: String?
    let coverLeftText1: String?
    let coverLeftText2: String?
    let coverLeftText3: String?
    let coverRightText: String?
    let bottomRcmdReasonStyle: AppFeedBottomRcmdReasonStyle?
    let args: AppFeedArgs?
    let playerArgs: AppFeedPlayerArgs?

    enum CodingKeys: String, CodingKey {
        case cardType = "card_type"
        case cardGoto = "card_goto"
        case goto
        case param
        case title
        case cover
        case uri
        case coverLeftText1 = "cover_left_text_1"
        case coverLeftText2 = "cover_left_text_2"
        case coverLeftText3 = "cover_left_text_3"
        case coverRightText = "cover_right_text"
        case bottomRcmdReasonStyle = "bottom_rcmd_reason_style"
        case args
        case playerArgs = "player_args"
    }
}

struct AppFeedBottomRcmdReasonStyle: Codable {
    let text: String?
}

struct AppFeedArgs: Codable {
    let upId: Int?
    let upName: String?
    let aid: Int?

    enum CodingKeys: String, CodingKey {
        case upId = "up_id"
        case upName = "up_name"
        case aid
    }
}

struct AppFeedPlayerArgs: Codable {
    let duration: Int?
    let aid: Int?
    let cid: Int?
}

// MARK: - 多态 Feed 卡片枚举

enum FeedCardItem: Identifiable {
    case video(VideoItem)
    case live(LiveCardModel)

    var id: String {
        switch self {
        case .video(let model): return "video_\(model.bvid)"
        case .live(let model): return "live_\(model.roomId)"
        }
    }
}

// MARK: - 直播卡片模型

struct LiveCardModel {
    let roomId: String
    let title: String
    let coverURL: String
    let onlineCount: String
    let anchorName: String
}

//
//  PlayerWbiV2.swift
//  PiliPod
//
//  Created by co on 2026/5/25.
//

import Foundation

struct FlexibleInt: Codable {
    let value: Int?

    init(_ value: Int?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
            return
        }
        if let stringVal = try? container.decode(String.self) {
            value = Int(stringVal)
            return
        }
        value = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

struct PlayerWbiV2Response: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: PlayerWbiV2Data?
}

struct PlayerWbiV2Data: Codable {
    let aid: Int?
    let bvid: String?
    let allowBp: Bool?
    let noShare: Bool?
    let cid: Int?
    let subtitle: PlayerSubtitle?
    let viewPoints: [PlayerViewPoint]?
    let loginMid: Int?
    let loginMidHash: String?
    let isOwner: Bool?
    let name: String?
    let permission: FlexibleInt?
    let lastPlayTime: Int?
    let lastPlayCid: Int?
    let nowTime: Int?
    let onlineCount: Int?
    let needLoginSubtitle: Bool?
    let toastBlock: Bool?
    let isUpowerExclusive: Bool?
    let isUpowerPlay: Bool?
    let isUgcPayPreview: Bool?
    let disableShowUpInfo: Bool?

    enum CodingKeys: String, CodingKey {
        case aid
        case bvid
        case allowBp = "allow_bp"
        case noShare = "no_share"
        case cid
        case subtitle
        case viewPoints = "view_points"
        case loginMid = "login_mid"
        case loginMidHash = "login_mid_hash"
        case isOwner = "is_owner"
        case name
        case permission
        case lastPlayTime = "last_play_time"
        case lastPlayCid = "last_play_cid"
        case nowTime = "now_time"
        case onlineCount = "online_count"
        case needLoginSubtitle = "need_login_subtitle"
        case toastBlock = "toast_block"
        case isUpowerExclusive = "is_upower_exclusive"
        case isUpowerPlay = "is_upower_play"
        case isUgcPayPreview = "is_ugc_pay_preview"
        case disableShowUpInfo = "disable_show_up_info"
    }
}

struct PlayerSubtitle: Codable {
    let subtitles: [PlayerSubtitleItem]?
}

struct PlayerSubtitleItem: Codable, Identifiable {
    let aiStatus: Int?
    let aiType: Int?
    let subtitleId: Int?
    let subtitleIdStr: String?
    let isLock: Bool?
    let lan: String?
    let lanDoc: String?
    let subtitleUrl: String?
    let type: Int?

    var identity: String {
        if let subtitleIdStr, !subtitleIdStr.isEmpty { return subtitleIdStr }
        if let subtitleId { return String(subtitleId) }
        return UUID().uuidString
    }

    var id: String { identity }

    enum CodingKeys: String, CodingKey {
        case aiStatus = "ai_status"
        case aiType = "ai_type"
        case subtitleId = "id"
        case subtitleIdStr = "id_str"
        case isLock = "is_lock"
        case lan
        case lanDoc = "lan_doc"
        case subtitleUrl = "subtitle_url"
        case type
    }
}

struct PlayerViewPoint: Codable, Identifiable {
    let from: Int?
    let to: Int?
    let content: String?
    let type: Int?

    var id: String {
        "\(from ?? -1)-\(to ?? -1)-\(content ?? "")"
    }
}

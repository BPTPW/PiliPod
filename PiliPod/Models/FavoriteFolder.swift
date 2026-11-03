//
//  FavoriteFolder.swift
//  PiliPod
//
//  Created by co on 2026/5/25.
//

import Foundation

struct FavoriteFolderListResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: FavoriteFolderListData?
}

struct FavoriteFolderListData: Codable {
    let count: Int
    let list: [FavoriteFolderItem]?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case count
        case list
        case hasMore = "has_more"
    }
}

struct FavoriteFolderItem: Codable, Identifiable, Hashable {
    let id: Int64
    let fid: Int64
    let mid: Int64
    let attr: Int
    let title: String
    let favState: Int
    let mediaCount: Int
    let cover: String?

    var isPrivate: Bool { (attr & 1) == 1 }
    var isDefault: Bool { (attr & 2) == 2 }
    var isSelectedInitially: Bool { favState == 1 }

    enum CodingKeys: String, CodingKey {
        case id
        case fid
        case mid
        case attr
        case title
        case favState = "fav_state"
        case mediaCount = "media_count"
        case cover
    }
}

// MARK: - 收藏夹内容明细

struct FavoriteResourceListResponse: Codable {
    let code: Int
    let message: String?
    let data: FavoriteResourceListData?
}

struct FavoriteResourceListData: Codable {
    let medias: [FavoriteResourceItem]?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case medias
        case hasMore = "has_more"
    }
}

struct FavoriteResourceItem: Codable {
    struct Upper: Codable {
        let name: String?
    }

    struct CountInfo: Codable {
        let play: Int?
        let danmaku: Int?
    }

    let id: Int64
    let type: Int
    let title: String
    let cover: String?
    let duration: Int?
    let upper: Upper?
    let attr: Int?
    let cntInfo: CountInfo?
    let favTime: Int?
    let bvid: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, cover, duration, upper, attr, bvid
        case cntInfo = "cnt_info"
        case favTime = "fav_time"
    }

    /// 仅展示正常的视频稿件
    var isPlayableVideo: Bool {
        type == 2 && (attr ?? 0) == 0 && !(bvid ?? "").isEmpty
    }
}

extension VideoItem {
    init(from item: FavoriteResourceItem) {
        self.bvid = item.bvid ?? ""
        self.cid = nil
        self.cover = (item.cover ?? "").replacingOccurrences(of: "http://", with: "https://")
        self.title = item.title
        self.playCount = Self.formatCount(item.cntInfo?.play ?? 0)
        self.danmakuCount = Self.formatCount(item.cntInfo?.danmaku ?? 0)
        self.uploader = item.upper?.name ?? ""
        self.duration = item.duration ?? 0
        self.progressSeconds = nil
        self.publishTimeText = Self.formatTimestamp(item.favTime)
        self.bottomRcmdReasonText = nil
    }
}

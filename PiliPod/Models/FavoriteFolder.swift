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
}

struct FavoriteFolderItem: Codable, Identifiable, Hashable {
    let id: Int64
    let fid: Int64
    let mid: Int64
    let attr: Int
    let title: String
    let favState: Int
    let mediaCount: Int

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
    }
}

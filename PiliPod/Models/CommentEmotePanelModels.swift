//
//  CommentEmotePanelModels.swift
//  PiliPod
//
//  Created by Codex on 2026/6/1.
//

import Foundation

struct UserReplyEmotePanelResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: UserReplyEmotePanelData?
}

struct UserReplyEmotePanelData: Codable {
    let packages: [ReplyEmotePackage]
}

struct ReplyEmotePackage: Codable, Identifiable {
    let id: Int
    let text: String
    let url: String
    let meta: ReplyEmotePackageMeta?
    let emote: [ReplyEmoteItem]
    let flags: ReplyEmotePackageFlags?
}

struct ReplyEmotePackageMeta: Codable {
    let size: Int?
    let itemID: Int?
    let itemURL: String?

    enum CodingKeys: String, CodingKey {
        case size
        case itemID = "item_id"
        case itemURL = "item_url"
    }
}

struct ReplyEmotePackageFlags: Codable {
    let added: Bool?
}

struct ReplyEmoteItem: Codable, Identifiable {
    let id: Int
    let packageID: Int
    let text: String
    let url: String
    let mtime: Int64?
    let type: Int?
    let meta: ReplyEmoteItemMeta?

    enum CodingKeys: String, CodingKey {
        case id
        case packageID = "package_id"
        case text
        case url
        case mtime
        case type
        case meta
    }
}

struct ReplyEmoteItemMeta: Codable {
    let size: Int?
    let alias: String?
}

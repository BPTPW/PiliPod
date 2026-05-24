//
//  ArchiveRelation.swift
//  PiliPod
//
//  Created by co on 2026/5/24.
//

import Foundation

struct ArchiveRelationResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: ArchiveRelationData?
}

struct ArchiveRelationData: Codable {
    let attention: Bool
    let favorite: Bool
    let seasonFav: Bool
    let like: Bool
    let dislike: Bool
    let coin: Int

    enum CodingKeys: String, CodingKey {
        case attention
        case favorite
        case seasonFav = "season_fav"
        case like
        case dislike
        case coin
    }
}

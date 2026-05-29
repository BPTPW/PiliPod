//
//  UserCardStats.swift
//  PiliPod
//
//  Created by co on 2026/5/24.
//

import Foundation

struct UserCardStats: Codable, Sendable {
    let follower: Int
    let archiveCount: Int
    let following: Bool

    enum CodingKeys: String, CodingKey {
        case follower
        case archiveCount = "archive_count"
        case following
    }
}

struct UserCardStatsResponse: Codable, Sendable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: UserCardStats?
}

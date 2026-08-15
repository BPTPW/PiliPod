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

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

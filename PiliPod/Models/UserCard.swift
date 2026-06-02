//
//  UserCard.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

struct UserCard: Codable {
    let mid: Int
    let name: String
    let face: String
    let money: Double
    let levelInfo: UserLevelInfo

    enum CodingKeys: String, CodingKey {
        case mid
        case name = "uname"
        case face
        case money
        case levelInfo = "level_info"
    }
}

struct UserLevelInfo: Codable {
    let currentLevel: Int
    let currentMin: Int
    let currentExp: Int
    let nextExp: String

    enum CodingKeys: String, CodingKey {
        case currentLevel = "current_level"
        case currentMin = "current_min"
        case currentExp = "current_exp"
        case nextExp = "next_exp"
    }
}

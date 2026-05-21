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

    enum CodingKeys: String, CodingKey {
        case mid
        case name = "uname"
        case face
    }
}

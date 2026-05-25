//
//  RelatedVideosResponse.swift
//  PiliPod
//
//  Created by co on 2026/5/25.
//

import Foundation

struct RelatedVideosResponse: Codable {
    let code: Int
    let message: String?
    let ttl: Int?
    let data: [RelatedVideo]?
}

struct RelatedVideo: Codable {
    let bvid: String
    let pic: String
    let title: String
    let pubdate: Int?
    let duration: Int
    let owner: Owner
    let stat: Stat
}


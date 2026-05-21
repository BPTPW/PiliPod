//
//  RecommendResponse.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

struct RecommendResponse: Codable {
    let data: RecommendData
}

struct RecommendData: Codable {
    let item: [RecommendVideo]
}

struct RecommendVideo: Codable {
    let title: String
    let pic: String
    let owner: Owner
    let stat: Stat
    let bvid: String
}

struct Owner: Codable {
    let name: String
}

struct Stat: Codable {
    let view: Int
    let danmaku: Int
}

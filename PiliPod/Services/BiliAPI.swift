//
//  BiliAPI.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

class BiliAPI {

    static let shared = BiliAPI()

    private init() {}

    func fetchRecommendVideos() async throws -> [VideoItem] {

        guard let url = URL(
            string: "https://api.bilibili.com/x/web-interface/index/top/feed/rcmd"
        ) else {
            return []
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        let response = try JSONDecoder().decode(
            RecommendResponse.self,
            from: data
        )

        return response.data.item.map {
            VideoItem(from: $0)
        }
    }
}

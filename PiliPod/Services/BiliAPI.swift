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

    func fetchRecommendVideos(
        freshIdx: Int,
        freshType: Int,
        brush: Int
    ) async throws -> [VideoItem] {

        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/index/top/feed/rcmd"
        )
        components?.queryItems = [
            URLQueryItem(name: "fresh_idx", value: String(freshIdx)),
            URLQueryItem(name: "fresh_type", value: String(freshType)),
            URLQueryItem(name: "brush", value: String(brush))
        ]

        guard let url = components?.url else {
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

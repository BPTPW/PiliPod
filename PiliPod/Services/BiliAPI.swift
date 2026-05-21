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

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)

        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        return request
    }

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

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            RecommendResponse.self,
            from: data
        )

        return response.data.item.map {
            VideoItem(from: $0)
        }
    }

    func fetchMyInfo() async throws -> UserCard {
        let url = URL(string: "https://api.bilibili.com/x/web-interface/nav")!
        let request = makeRequest(url: url)

        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            NavResponse.self,
            from: data
        )

        return response.data
    }
}

struct NavResponse: Codable {
    let data: UserCard
}


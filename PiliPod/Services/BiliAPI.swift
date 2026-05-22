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

    // MARK: - 创建带登录状态的http请求

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)

        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        return request
    }

    // MARK: - 获取推荐视频

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

    // MARK: - 视频详情

    func fetchVideoDetail(bvid: String) async throws -> VideoDetailData {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/web-interface/view"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            VideoDetailResponse.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        return response.data
    }

    // MARK: - 播放链接

    func fetchPlayUrl(
        bvid: String,
        cid: Int,
        fnval: Int = 4048,
        qn: Int = 127
    ) async throws -> PlayUrlResponse {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/player/wbi/playurl"
        )
        components?.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: String(cid)),
            URLQueryItem(name: "fnval", value: String(fnval)),
            URLQueryItem(name: "fourk", value: "4048"),
            URLQueryItem(name: "qn", value: String(qn))
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(
            PlayUrlResponse.self,
            from: data
        )

        if response.code != 0 {
            throw APIError.responseError(response.code)
        }

        return response
    }

    // MARK: - 上报播放记录

    func reportHistory(
        aid: Int,
        cid: Int,
        progress: Int
    ) async throws {
        var components = URLComponents(
            string: "https://api.bilibili.com/x/v2/history/report"
        )
        components?.queryItems = [
            URLQueryItem(name: "aid", value: String(aid)),
            URLQueryItem(name: "cid", value: String(cid)),
            URLQueryItem(name: "progress", value: String(progress)),
            URLQueryItem(name: "platform", value: "web"),
            URLQueryItem(name: "csrf", value: LoginSession.shared.cookies?.bili_jct ?? "")
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = makeRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw APIError.requestFailed
        }
    }
}

// MARK: - 错误处理

enum APIError: LocalizedError {
    case invalidURL
    case responseError(Int)
    case noVideoOrAudio
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .responseError(let code):
            return "API 错误: \(code)"
        case .noVideoOrAudio:
            return "未找到视频或音频流"
        case .requestFailed:
            return "请求失败"
        }
    }
}

struct NavResponse: Codable {
    let data: UserCard
}

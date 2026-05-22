//
//  BiliAPI.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import CryptoKit
import Foundation

class BiliAPI {
    static let shared = BiliAPI()

    // PiliPlus 中通用的 Bilibili 移动端 AppKey 和 Secret
    private static let appKey = "27eb53fc9058fad3"
    private static let appSecret = "c2ed53a74eeefe3cf99fbd01d8c9c375"

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

    // MARK: - 构建移动端 App 请求（加签 + 公共参数）

    private func makeAppRequest(
        baseURLString: String,
        method: String = "GET",
        parameters: [String: String] = [:]
    ) -> URLRequest? {
        guard let baseURL = URL(string: baseURLString) else { return nil }

        // 1. 合并业务参数与系统公共移动端参数
        var allParams = parameters
        allParams["appkey"] = Self.appKey
        allParams["mobi_app"] = "iphone"
        allParams["platform"] = "ios"
        allParams["ts"] = String(Int(Date().timeIntervalSince1970))

        // 2. 注入通过 LoginSession 导入的移动端特有凭证 accessKey
        if let accessKey = LoginSession.shared.accessKey, !accessKey.isEmpty {
            allParams["access_key"] = accessKey
        }

        // 3. 将所有参数按照 Key 的字母顺序（ASCII 码）升序排列
        let sortedParams = allParams.sorted { $0.key < $1.key }

        // 4. 拼接成未编码的 Raw Query 字符串用于加签
        let rawQueryString = sortedParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        // 5. 尾部加上移动端 Secret，计算 MD5 得到核心 sign
        let signString = rawQueryString + Self.appSecret
        let sign = md5(signString)

        // 将计算出的签名也加入最终的参数中
        allParams["sign"] = sign

        // 6. 组装真正的 URLRequest
        var request = URLRequest(url: baseURL)
        request.httpMethod = method

        // 伪造符合 iOS 移动端行为的公共 Header
        request.setValue("bili-universal/103300 (iPhone; iOS 18.2; Scale/3.00)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // 移动端请求作为稳妥保障，一并带上 Cookie
        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        // 7. 根据 GET 还是 POST 将带 sign 的参数绑定到 Request 中
        if method.uppercased() == "GET" {
            if var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
                components.queryItems = allParams.map { URLQueryItem(name: $0.key, value: $0.value) }
                if let finalURL = components.url {
                    request.url = finalURL
                }
            }
        } else {
            var bodyComponents = URLComponents()
            bodyComponents.queryItems = allParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let bodyString = bodyComponents.percentEncodedQuery {
                request.httpBody = bodyString.data(using: .utf8)
            }
        }

        return request
    }

    // MARK: - MD5 工具

    private func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - 获取网页版推荐视频

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
    
    // MARK: - 获取App版推荐视频
    
    func fetchAppRecommendVideos(idx: Int, flush: Int) async throws -> Data {
            // App 推荐数据的基准接口地址
            let appRcmdHost = "https://app.bilibili.com/x/v2/feed/index"
            
            // 组装所需的特定业务参数
            let businessParams: [String: String] = [
                "idx": String(idx),
                "flush": String(flush),
                "pull": flush == 1 ? "true" : "false",
                "device": "phone",
                "login_event": "1"
            ]
            
            // 使用新封装的加签构造器创建请求
            guard let request = makeAppRequest(baseURLString: appRcmdHost, method: "GET", parameters: businessParams) else {
                throw APIError.invalidURL
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                throw APIError.requestFailed
            }
            
            return data
        }
    
    // MARK: - 获取用户数据

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

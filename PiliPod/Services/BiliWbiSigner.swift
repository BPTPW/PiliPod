//
//  BiliWbiSigner.swift
//  PiliPod
//
//  Created by Codex on 2026/6/4.
//

import CryptoKit
import Foundation

enum BiliWbiSignature {
    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
        33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
        61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
        36, 20, 34, 44, 52,
    ]

    static func makeMixinKey(imgKey: String, subKey: String) -> String {
        let rawKey = Array(imgKey + subKey)
        let mixed = mixinKeyEncTab.compactMap { index in
            rawKey.indices.contains(index) ? rawKey[index] : nil
        }
        return String(mixed.prefix(32))
    }

    static func sign(
        queryItems: [URLQueryItem],
        imgKey: String,
        subKey: String,
        timestamp: Int
    ) -> [URLQueryItem] {
        let mixinKey = makeMixinKey(imgKey: imgKey, subKey: subKey)
        let sanitizedItems = queryItems
            .filter { $0.name != "w_rid" && $0.name != "wts" }
            .map { URLQueryItem(name: $0.name, value: sanitizeValue($0.value)) }

        let signingItems = sanitizedItems + [
            URLQueryItem(name: "wts", value: String(timestamp))
        ]
        let canonicalQuery = signingItems
            .sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }
            .map { item in
                let encodedKey = item.name.biliUrlEncoded()
                let encodedValue = (item.value ?? "").biliUrlEncoded()
                return encodedValue.isEmpty ? encodedKey : "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")

        let digest = Insecure.MD5.hash(data: Data((canonicalQuery + mixinKey).utf8))
        let wRid = digest.map { String(format: "%02hhx", $0) }.joined()

        return sanitizedItems + [
            URLQueryItem(name: "w_rid", value: wRid),
            URLQueryItem(name: "wts", value: String(timestamp)),
        ]
    }

    static func sign(
        url: URL,
        imgKey: String,
        subKey: String,
        timestamp: Int
    ) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BiliWbiSignerError.invalidURL
        }

        components.queryItems = sign(
            queryItems: components.queryItems ?? [],
            imgKey: imgKey,
            subKey: subKey,
            timestamp: timestamp
        )

        guard let signedURL = components.url else {
            throw BiliWbiSignerError.invalidURL
        }
        return signedURL
    }

    private static func sanitizeValue(_ value: String?) -> String {
        guard let value else { return "" }
        return String(value.filter { !"!'()*".contains($0) })
    }
}

enum BiliWbiSignerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingWbiKeys
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 WBI URL"
        case .invalidResponse:
            return "WBI key 响应无效"
        case .missingWbiKeys:
            return "未获取到 WBI key"
        case let .requestFailed(statusCode):
            return "WBI key 请求失败: \(statusCode)"
        }
    }
}

actor BiliWbiSigner {
    static let shared = BiliWbiSigner()

    private let session: URLSession
    private let cacheTTL: TimeInterval
    private var cachedKeys: CachedWbiKeys?

    init(session: URLSession = .shared, cacheTTL: TimeInterval = 12 * 60 * 60) {
        self.session = session
        self.cacheTTL = cacheTTL
    }

    func sign(url: URL, timestamp: Int = Int(Date().timeIntervalSince1970)) async throws -> URL {
        let keys = try await currentKeys()
        return try BiliWbiSignature.sign(
            url: url,
            imgKey: keys.imgKey,
            subKey: keys.subKey,
            timestamp: timestamp
        )
    }

    func sign(
        queryItems: [URLQueryItem],
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) async throws -> [URLQueryItem] {
        let keys = try await currentKeys()
        return BiliWbiSignature.sign(
            queryItems: queryItems,
            imgKey: keys.imgKey,
            subKey: keys.subKey,
            timestamp: timestamp
        )
    }

    func refreshKeys() async throws {
        cachedKeys = try await fetchKeys()
    }

    private func currentKeys() async throws -> CachedWbiKeys {
        if let cachedKeys, !cachedKeys.isExpired(ttl: cacheTTL) {
            return cachedKeys
        }

        let freshKeys = try await fetchKeys()
        cachedKeys = freshKeys
        return freshKeys
    }

    private func fetchKeys() async throws -> CachedWbiKeys {
        guard let url = URL(string: "https://api.bilibili.com/x/web-interface/nav") else {
            throw BiliWbiSignerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BiliWbiSignerError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw BiliWbiSignerError.requestFailed(httpResponse.statusCode)
        }

        let payload = try JSONDecoder().decode(WbiNavResponse.self, from: data)
        guard
            let imgURL = payload.data.wbiImage.imgURL,
            let subURL = payload.data.wbiImage.subURL,
            let imgKey = Self.extractKey(from: imgURL),
            let subKey = Self.extractKey(from: subURL)
        else {
            throw BiliWbiSignerError.missingWbiKeys
        }

        return CachedWbiKeys(
            imgKey: imgKey,
            subKey: subKey,
            fetchedAt: Date()
        )
    }

    private static func extractKey(from urlString: String) -> String? {
        URL(string: urlString)?
            .lastPathComponent
            .split(separator: ".")
            .first
            .map(String.init)
    }
}

private struct CachedWbiKeys {
    let imgKey: String
    let subKey: String
    let fetchedAt: Date

    func isExpired(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) >= ttl
    }
}

private struct WbiNavResponse: Decodable {
    let data: WbiNavData
}

private struct WbiNavData: Decodable {
    let wbiImage: WbiImage

    enum CodingKeys: String, CodingKey {
        case wbiImage = "wbi_img"
    }
}

private struct WbiImage: Decodable {
    let imgURL: String?
    let subURL: String?

    enum CodingKeys: String, CodingKey {
        case imgURL = "img_url"
        case subURL = "sub_url"
    }
}

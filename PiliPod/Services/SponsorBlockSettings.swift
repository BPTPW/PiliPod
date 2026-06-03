import Foundation
import SwiftUI

enum SponsorBlockSegmentBehavior: String, Codable, CaseIterable, Hashable {
    case autoSkip
    case manualSkip
    case showOnly
    case disabled

    var title: String {
        switch self {
        case .autoSkip:
            return "自动跳过"
        case .manualSkip:
            return "手动跳过"
        case .showOnly:
            return "仅显示"
        case .disabled:
            return "禁用"
        }
    }
}

enum SponsorBlockCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case sponsor
    case selfpromo
    case exclusiveAccess = "exclusive_access"
    case interaction
    case poiHighlight = "poi_highlight"
    case intro
    case outro
    case preview
    case padding
    case filler
    case musicOfftopic = "music_offtopic"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sponsor:
            return "赞助/恰饭"
        case .selfpromo:
            return "无偿/自我推广"
        case .exclusiveAccess:
            return "独家访问/抢先体验"
        case .interaction:
            return "互动提醒"
        case .poiHighlight:
            return "精彩时刻/重点"
        case .intro:
            return "过场/开场动画"
        case .outro:
            return "鸣谢/结束画面"
        case .preview:
            return "回顾/概要"
        case .padding:
            return "填充内容/前黑/后黑"
        case .filler:
            return "离题闲聊/玩笑"
        case .musicOfftopic:
            return "音乐:非音乐部分"
        }
    }

    var color: Color {
        switch self {
        case .sponsor:
            return .green
        case .selfpromo:
            return .yellow
        case .exclusiveAccess:
            return .mint
        case .interaction:
            return .purple
        case .poiHighlight:
            return .pink
        case .intro:
            return .cyan
        case .outro:
            return .indigo
        case .preview:
            return .blue
        case .padding:
            return .black
        case .filler:
            return .purple
        case .musicOfftopic:
            return .orange
        }
    }

    var defaultBehavior: SponsorBlockSegmentBehavior {
        switch self {
        case .sponsor:
            return .autoSkip
        case .selfpromo:
            return .manualSkip
        case .exclusiveAccess:
            return .showOnly
        case .interaction:
            return .showOnly
        case .poiHighlight:
            return .showOnly
        case .intro:
            return .manualSkip
        case .outro:
            return .showOnly
        case .preview:
            return .manualSkip
        case .padding:
            return .autoSkip
        case .filler:
            return .showOnly
        case .musicOfftopic:
            return .manualSkip
        }
    }
}

struct SponsorBlockSettings: Codable, Equatable {
    var isEnabled = false
    var shouldTrackSkipCount = true
    var showsSkipToast = true
    var userID: String?
    var behaviors: [String: SponsorBlockSegmentBehavior] = [:]

    func clamped() -> SponsorBlockSettings {
        var copy = self
        var normalized: [String: SponsorBlockSegmentBehavior] = [:]
        for category in SponsorBlockCategory.allCases {
            normalized[category.rawValue] = behaviors[category.rawValue] ?? category.defaultBehavior
        }
        copy.behaviors = normalized

        if let userID = copy.userID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userID.isEmpty
        {
            copy.userID = String(userID.prefix(36))
        } else {
            copy.userID = nil
        }

        return copy
    }

    func behavior(for category: SponsorBlockCategory) -> SponsorBlockSegmentBehavior {
        behaviors[category.rawValue] ?? category.defaultBehavior
    }

    mutating func setBehavior(_ behavior: SponsorBlockSegmentBehavior, for category: SponsorBlockCategory) {
        behaviors[category.rawValue] = behavior
    }
}

enum SponsorBlockSettingsStore {
    private static let key = "sponsor_block_settings"

    static func load() -> SponsorBlockSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SponsorBlockSettings.self, from: data)
        else {
            return SponsorBlockSettings().clamped()
        }

        return decoded.clamped()
    }

    static func save(_ settings: SponsorBlockSettings) {
        let clamped = settings.clamped()
        guard let data = try? JSONEncoder().encode(clamped) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func ensureUserIDIfNeeded(for settings: inout SponsorBlockSettings) {
        guard settings.isEnabled else { return }
        if settings.userID == nil {
            settings.userID = generateUserID()
        }
        settings = settings.clamped()
        save(settings)
    }

    static func generateUserID() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0 ..< 36).compactMap { _ in characters.randomElement() })
    }
}

struct SponsorBlockUserInfo: Codable {
    let minutesSaved: Double
    let segmentCount: Int
    let viewCount: Int
}

enum SponsorBlockServerStatus: Equatable {
    case idle
    case loading
    case healthy
    case error(statusCode: Int)
    case timeout
    case failed

    var text: String {
        switch self {
        case .idle:
            return "未检查"
        case .loading:
            return "检查中"
        case .healthy:
            return "正常"
        case .error(let statusCode):
            return "错误: \(statusCode)"
        case .timeout:
            return "超时"
        case .failed:
            return "请求失败"
        }
    }

    var color: Color {
        switch self {
        case .healthy:
            return .green
        case .error, .timeout, .failed:
            return .red
        case .idle, .loading:
            return .secondary
        }
    }
}

enum SponsorBlockAPI {
    static func fetchSkipSegments(
        videoID: String,
        cid: Int? = nil
    ) async throws -> [SkipSegment] {
        guard var components = URLComponents(string: "https://www.bsbsb.top/api/skipSegments") else {
            throw URLError(.badURL)
        }

        var queryItems = [URLQueryItem(name: "videoID", value: videoID)]
        if let cid, cid > 0 {
            queryItems.append(URLQueryItem(name: "cid", value: String(cid)))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 404 {
            return []
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([SkipSegment].self, from: data)
    }

    static func fetchStatus() async -> SponsorBlockServerStatus {
        guard let url = URL(string: "https://www.bsbsb.top/api/status/") else {
            return .failed
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed
            }
            if httpResponse.statusCode == 200 {
                return .healthy
            }
            return .error(statusCode: httpResponse.statusCode)
        } catch let error as URLError where error.code == .timedOut {
            return .timeout
        } catch {
            return .failed
        }
    }

    static func fetchUserInfo(userID: String) async throws -> SponsorBlockUserInfo {
        guard var components = URLComponents(string: "https://www.bsbsb.top/api/userInfo") else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "userID", value: userID),
            URLQueryItem(name: "values", value: "[\"minutesSaved\",\"segmentCount\",\"viewCount\"]")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(SponsorBlockUserInfo.self, from: data)
    }

    static func markSegmentViewed(uuid: String) async {
        guard var components = URLComponents(string: "https://bsbsb.top/api/viewedVideoSponsorTime") else {
            return
        }
        components.queryItems = [
            URLQueryItem(name: "UUID", value: uuid)
        ]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5

        _ = try? await URLSession.shared.data(for: request)
    }

    static func voteOnSegment(uuid: String, userID: String, type: Int) async throws {
        guard let url = URL(string: "https://www.bsbsb.top/api/voteOnSponsorTime") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "UUID": uuid,
            "userID": userID,
            "type": type
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }
    }

    static func changeSegmentCategory(uuid: String, userID: String, category: String) async throws {
        guard let url = URL(string: "https://www.bsbsb.top/api/voteOnSponsorTime") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "UUID": uuid,
            "userID": userID,
            "category": category
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }
    }
}

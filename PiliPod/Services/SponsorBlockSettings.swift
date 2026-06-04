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
    static let defaultServerBaseURL = "https://www.bsbsb.top"

    var isEnabled = false
    var shouldTrackSkipCount = true
    var showsSkipToast = true
    var showsVideoLabelOnCover = true
    var serverBaseURL = SponsorBlockSettings.defaultServerBaseURL
    var userID: String?
    var behaviors: [String: SponsorBlockSegmentBehavior] = [:]

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case shouldTrackSkipCount
        case showsSkipToast
        case showsVideoLabelOnCover
        case serverBaseURL
        case userID
        case behaviors
    }

    func clamped() -> SponsorBlockSettings {
        var copy = self
        var normalized: [String: SponsorBlockSegmentBehavior] = [:]
        for category in SponsorBlockCategory.allCases {
            normalized[category.rawValue] = behaviors[category.rawValue] ?? category.defaultBehavior
        }
        copy.behaviors = normalized

        let trimmedBaseURL = copy.serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBaseURL.isEmpty {
            copy.serverBaseURL = SponsorBlockSettings.defaultServerBaseURL
        } else {
            copy.serverBaseURL = normalizedSponsorBlockBaseURL(trimmedBaseURL) ?? SponsorBlockSettings.defaultServerBaseURL
        }

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

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        shouldTrackSkipCount = try container.decodeIfPresent(Bool.self, forKey: .shouldTrackSkipCount) ?? true
        showsSkipToast = try container.decodeIfPresent(Bool.self, forKey: .showsSkipToast) ?? true
        showsVideoLabelOnCover = try container.decodeIfPresent(Bool.self, forKey: .showsVideoLabelOnCover) ?? true
        serverBaseURL = try container.decodeIfPresent(String.self, forKey: .serverBaseURL) ?? SponsorBlockSettings.defaultServerBaseURL
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        behaviors = try container.decodeIfPresent([String: SponsorBlockSegmentBehavior].self, forKey: .behaviors) ?? [:]
    }
}

private func normalizedSponsorBlockBaseURL(_ rawValue: String) -> String? {
    var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty else { return nil }

    if !candidate.contains("://") {
        candidate = "https://" + candidate
    }

    guard var components = URLComponents(string: candidate) else { return nil }
    components.path = ""
    components.query = nil
    components.fragment = nil

    guard let scheme = components.scheme?.lowercased(),
          let host = components.host?.lowercased(),
          !host.isEmpty
    else {
        return nil
    }

    components.scheme = scheme
    components.host = host

    if let port = components.port {
        return "\(scheme)://\(host):\(port)"
    }
    return "\(scheme)://\(host)"
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

struct SponsorBlockVideoLabel: Codable, Identifiable {
    let cid: String
    let category: String
    let uuid: String
    let locked: Int
    let votes: Int
    let videoDuration: Double

    var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case cid
        case category
        case uuid = "UUID"
        case locked
        case votes
        case videoDuration
    }
}

struct SubmitSkipSegmentRequestItem {
    let segment: [Double]
    let category: String
    let actionType: String
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
    private actor VideoLabelCache {
        var results: [String: SponsorBlockVideoLabel?] = [:]
        var tasks: [String: Task<SponsorBlockVideoLabel?, Never>] = [:]

        func cachedValue(for videoID: String) -> SponsorBlockVideoLabel?? {
            if let value = results[videoID] {
                return .some(value)
            }
            return nil
        }

        func task(for videoID: String) -> Task<SponsorBlockVideoLabel?, Never>? {
            tasks[videoID]
        }

        func setTask(_ task: Task<SponsorBlockVideoLabel?, Never>, for videoID: String) {
            tasks[videoID] = task
        }

        func finish(videoID: String, result: SponsorBlockVideoLabel?) {
            results[videoID] = result
            tasks[videoID] = nil
        }
    }

    private static let videoLabelCache = VideoLabelCache()

    private static var baseURLString: String {
        SponsorBlockSettingsStore.load().serverBaseURL
    }

    private static func endpointURL(_ path: String) -> URL? {
        guard let baseURL = URL(string: baseURLString) else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    static func fetchPrimaryVideoLabelIfAvailable(videoID: String) async -> SponsorBlockVideoLabel? {
        let settings = SponsorBlockSettingsStore.load()
        guard settings.isEnabled, settings.showsVideoLabelOnCover, videoID.hasPrefix("BV"), videoID.count > 2 else { return nil }

        if let cached = await videoLabelCache.cachedValue(for: videoID) {
            return cached
        }

        if let existingTask = await videoLabelCache.task(for: videoID) {
            return await existingTask.value
        }

        let task = Task<SponsorBlockVideoLabel?, Never> {
            let result = try? await fetchVideoLabels(videoID: videoID).first
            await videoLabelCache.finish(videoID: videoID, result: result)
            return result
        }

        await videoLabelCache.setTask(task, for: videoID)
        return await task.value
    }

    static func fetchSkipSegments(
        videoID: String,
        cid: Int? = nil
    ) async throws -> [SkipSegment] {
        guard let endpoint = endpointURL("/api/skipSegments"),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else {
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
        guard let url = endpointURL("/api/status/") else {
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
        guard let endpoint = endpointURL("/api/userInfo"),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else {
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

    private static func fetchVideoLabels(videoID: String) async throws -> [SponsorBlockVideoLabel] {
        guard let endpoint = endpointURL("/api/videoLabels"),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "videoID", value: videoID)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([SponsorBlockVideoLabel].self, from: data)
    }

    static func markSegmentViewed(uuid: String) async {
        guard let endpoint = endpointURL("/api/viewedVideoSponsorTime"),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else {
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
        guard let url = endpointURL("/api/voteOnSponsorTime") else {
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
        guard let url = endpointURL("/api/voteOnSponsorTime") else {
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

    static func submitSegments(
        videoID: String,
        cid: String,
        userID: String,
        videoDuration: Double,
        segments: [SubmitSkipSegmentRequestItem]
    ) async throws -> [SubmittedSkipSegment] {
        guard let url = endpointURL("/api/skipSegments") else {
            throw URLError(.badURL)
        }

        let payload: [String: Any] = [
            "videoID": videoID,
            "cid": cid,
            "userID": userID,
            "videoDuration": videoDuration,
            "segments": segments.map { item in
                [
                    "segment": item.segment,
                    "category": item.category,
                    "actionType": item.actionType
                ]
            }
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([SubmittedSkipSegment].self, from: data)
    }
}

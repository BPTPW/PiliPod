import Foundation

/// A static, user-selectable playback route. These values are only used for
/// final media URLs; they must never be applied to Bilibili API endpoints.
enum PlaybackCDNRoute: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case original
    case backup
    case ali
    case alib
    case alio1
    case cos
    case cosb
    case coso1
    case tfTX = "tf_tx"
    case hw
    case hwb
    case hwo1
    case mirror08c = "08c"
    case mirror08h = "08h"
    case mirror08ct = "08ct"
    case tfHW = "tf_hw"
    case akamai
    case aliov
    case cosov
    case hwov
    case hongKong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "自动/原始地址"
        case .backup: "备用 URL"
        case .ali: "阿里云 ali"
        case .alib: "阿里云 alib"
        case .alio1: "阿里云 alio1"
        case .cos: "腾讯云 cos"
        case .cosb: "腾讯云 cosb"
        case .coso1: "腾讯云 coso1"
        case .tfTX: "腾讯云 tf_tx"
        case .hw: "华为云 hw"
        case .hwb: "华为云 hwb"
        case .hwo1: "华为云 hwo1"
        case .mirror08c: "华为云 08c"
        case .mirror08h: "华为云 08h"
        case .mirror08ct: "华为云 08ct"
        case .tfHW: "华为云 tf_hw"
        case .akamai: "Akamai 海外"
        case .aliov: "阿里云海外 aliov"
        case .cosov: "腾讯云海外 cosov"
        case .hwov: "华为云海外 hwov"
        case .hongKong: "Bilibili 香港"
        }
    }

    var host: String? {
        switch self {
        case .original, .backup: nil
        case .ali: "upos-sz-mirrorali.bilivideo.com"
        case .alib: "upos-sz-mirroralib.bilivideo.com"
        case .alio1: "upos-sz-mirroralio1.bilivideo.com"
        case .cos: "upos-sz-mirrorcos.bilivideo.com"
        case .cosb: "upos-sz-mirrorcosb.bilivideo.com"
        case .coso1: "upos-sz-mirrorcoso1.bilivideo.com"
        case .tfTX: "upos-tf-all-tx.bilivideo.com"
        case .hw: "upos-sz-mirrorhw.bilivideo.com"
        case .hwb: "upos-sz-mirrorhwb.bilivideo.com"
        case .hwo1: "upos-sz-mirrorhwo1.bilivideo.com"
        case .mirror08c: "upos-sz-mirror08c.bilivideo.com"
        case .mirror08h: "upos-sz-mirror08h.bilivideo.com"
        case .mirror08ct: "upos-sz-mirror08ct.bilivideo.com"
        case .tfHW: "upos-tf-all-hw.bilivideo.com"
        case .akamai: "upos-hz-mirrorakam.akamaized.net"
        case .aliov: "upos-sz-mirroraliov.bilivideo.com"
        case .cosov: "upos-sz-mirrorcosov.bilivideo.com"
        case .hwov: "upos-sz-mirrorhwov.bilivideo.com"
        case .hongKong: "cn-hk-eq-bcache-01.bilivideo.com"
        }
    }

    static var manualRoutes: [PlaybackCDNRoute] {
        allCases.filter { $0.host != nil }
    }
}

/// Pure URL policy for final DASH media resources.
enum PlaybackCDNPlanner {
    static func canRewriteMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), isKnownMediaHost(host) else { return false }
        let path = url.path.lowercased()
        return path.contains("/upgcxcode/")
            || path.hasSuffix(".m4s") && path.contains("/ugc/")
    }

    /// Replaces just the host using URLComponents, preserving scheme, port,
    /// path, query (including signatures), fragments, and all other parts.
    static func safelyRewritingHost(of url: URL, to host: String) -> URL? {
        guard canRewriteMediaURL(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = host
        return components.url
    }

    static func candidates(
        primary: URL,
        backups: [URL],
        route: PlaybackCDNRoute
    ) -> [URL] {
        let originals = deduplicated([primary] + backups)
        guard !originals.isEmpty else { return [] }

        switch route {
        case .original:
            return originals
        case .backup:
            return deduplicated(backups + [primary])
        default:
            guard let host = route.host else { return originals }
            let rewritten = originals.compactMap { safelyRewritingHost(of: $0, to: host) }.first
            return deduplicated(([rewritten].compactMap { $0 }) + originals)
        }
    }

    static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func isKnownMediaHost(_ host: String) -> Bool {
        host == "bilivideo.com" || host.hasSuffix(".bilivideo.com")
            || host == "acgvideo.com" || host.hasSuffix(".acgvideo.com")
            || host == "akamaized.net" || host.hasSuffix(".akamaized.net")
    }
}

/// Keeps the most recently received real play URLs in memory for Settings'
/// manual probe. It is intentionally not persisted because play URL signatures expire.
final class PlaybackCDNProbeURLStore: @unchecked Sendable {
    static let shared = PlaybackCDNProbeURLStore()

    private let lock = NSLock()
    private var urls: [URL] = []

    func update(_ urls: [URL]) {
        lock.lock()
        self.urls = PlaybackCDNPlanner.deduplicated(urls)
        lock.unlock()
    }

    func currentURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

enum PlaybackCDNProbeMode: Sendable { case realPlaybackURL, hostConnectivityReference }

struct PlaybackCDNProbeResult: Identifiable, Sendable {
    let route: PlaybackCDNRoute
    let elapsedMilliseconds: Int?
    let httpStatusCode: Int?
    let didSucceed: Bool
    let mode: PlaybackCDNProbeMode

    var id: PlaybackCDNRoute { route }
    var isWeakReference: Bool { mode == .hostConnectivityReference }

    var statusText: String {
        if isWeakReference, let status = httpStatusCode, status == 403 || status == 959 {
            return "拒绝裸探测"
        }
        if didSucceed {
            let time = elapsedMilliseconds.map { "\($0) ms" } ?? ""
            let status = httpStatusCode.map { "HTTP \($0)" } ?? ""
            let reference = isWeakReference ? "Host 连通性参考" : ""
            return [time, status, reference].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        if let status = httpStatusCode { return "HTTP \(status)" }
        return "错误"
    }
}

enum PlaybackCDNProbeService {
    private static let timeout: TimeInterval = 2.5
    private static let bareProbePath = "/upgcxcode/00/00/1/1.m4s"
    private static let smallResponseLimit = 16 * 1024

    static func probeAll(playbackURLs: [URL]) async -> [PlaybackCDNProbeResult] {
        await withTaskGroup(of: PlaybackCDNProbeResult.self) { group in
            for route in PlaybackCDNRoute.manualRoutes {
                group.addTask { await probe(route: route, playbackURLs: playbackURLs) }
            }
            var results = [PlaybackCDNProbeResult]()
            for await result in group { results.append(result) }
            return results.sorted(by: sort)
        }
    }

    private static func probe(route: PlaybackCDNRoute, playbackURLs: [URL]) async -> PlaybackCDNProbeResult {
        guard let host = route.host else {
            return PlaybackCDNProbeResult(route: route, elapsedMilliseconds: nil, httpStatusCode: nil, didSucceed: false, mode: .hostConnectivityReference)
        }
        let realURL = playbackURLs.compactMap { PlaybackCDNPlanner.safelyRewritingHost(of: $0, to: host) }.first
        let mode: PlaybackCDNProbeMode = realURL == nil ? .hostConnectivityReference : .realPlaybackURL
        guard let url = realURL ?? URL(string: "https://\(host)\(bareProbePath)") else {
            return PlaybackCDNProbeResult(route: route, elapsedMilliseconds: nil, httpStatusCode: nil, didSucceed: false, mode: mode)
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 BiliIOS/1.0", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1_000)
            let status = (response as? HTTPURLResponse)?.statusCode
            let success = status == 206
                || status == 200 && data.count <= smallResponseLimit
                || mode == .realPlaybackURL && (300 ... 399).contains(status ?? 0)
            return PlaybackCDNProbeResult(route: route, elapsedMilliseconds: elapsed, httpStatusCode: status, didSucceed: success, mode: mode)
        } catch is CancellationError {
            return PlaybackCDNProbeResult(route: route, elapsedMilliseconds: nil, httpStatusCode: nil, didSucceed: false, mode: mode)
        } catch {
            return PlaybackCDNProbeResult(route: route, elapsedMilliseconds: nil, httpStatusCode: nil, didSucceed: false, mode: mode)
        }
    }

    private static func sort(_ lhs: PlaybackCDNProbeResult, _ rhs: PlaybackCDNProbeResult) -> Bool {
        if lhs.didSucceed != rhs.didSucceed { return lhs.didSucceed }
        switch (lhs.elapsedMilliseconds, rhs.elapsedMilliseconds) {
        case let (left?, right?): return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return lhs.route.title < rhs.route.title
        }
    }
}

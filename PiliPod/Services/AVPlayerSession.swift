//
//  AVPlayerSession.swift
//  PiliPod
//

import AVFoundation
import AVKit
import Network
import UIKit

final class AVPlayerSession: NSObject, AVPictureInPictureControllerDelegate {
    enum PlaybackError: LocalizedError {
        case unsupportedVideoCodec(String)
        case unsupportedAudioCodec(String)
        case missingSegmentIndex
        case preparationFailed

        var errorDescription: String? {
            switch self {
            case let .unsupportedVideoCodec(codec): "AVPlayer 不支持当前视频编码（\(codec)），请切换 MPVKit。"
            case let .unsupportedAudioCodec(codec): "AVPlayer 不支持当前音频编码（\(codec)），请切换 MPVKit。"
            case .missingSegmentIndex: "该 DASH 流不含可用的 SegmentBase/SIDX 索引，无法使用 AVPlayer。"
            case .preparationFailed: "AVPlayer 本地 HLS 准备失败，请切换 MPVKit 重试。"
            }
        }
    }

    private let player = AVPlayer()
    private let headers: [String: String]
    private var bridge: LocalDASHHLSBridge?
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var prepareTask: Task<Void, Never>?
    private var generation = 0
    private weak var surface: UIView?
    private var layer: AVPlayerLayer?
    private var pictureInPictureController: AVPictureInPictureController?
    private var playbackSettings: AudioVideoSettings
    private var wantsPlayback = false
    private var pendingSeekTime: TimeInterval?
    private(set) var playbackRate = 1.0
    private(set) var snapshot = PlayerUIPlaybackSnapshot()
    private(set) var seekRevision = 0
    private(set) var errorMessage: String?
    var onSnapshot: ((PlayerUIPlaybackSnapshot) -> Void)?

    init(headers: [String: String], playbackSettings: AudioVideoSettings) {
        self.headers = headers
        self.playbackSettings = playbackSettings.clamped()
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        player.audiovisualBackgroundPlaybackPolicy = .automatic
    }

    func attach(to view: UIView) {
        surface = view
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        applyDynamicRangePreference(to: layer)
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        self.layer?.removeFromSuperlayer()
        self.layer = layer
    }

    func layout(in bounds: CGRect) { layer?.frame = bounds }

    func startPictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let layer,
              layer.player === player
        else { return }

        if pictureInPictureController?.playerLayer !== layer {
            pictureInPictureController = AVPictureInPictureController(playerLayer: layer)
            pictureInPictureController?.delegate = self
        }

        guard let pictureInPictureController,
              !pictureInPictureController.isPictureInPictureActive,
              pictureInPictureController.isPictureInPicturePossible
        else { return }
        pictureInPictureController.startPictureInPicture()
    }

    func stopPictureInPicture() {
        pictureInPictureController?.stopPictureInPicture()
    }

    func applyPlaybackSettings(_ settings: AudioVideoSettings) {
        playbackSettings = settings.clamped()
        applyDynamicRangePreference(to: layer)
        if let item = player.currentItem {
            applyBufferPreference(to: item)
        }
        publish()
    }

    func play(stream: DashStream) {
        configureBackgroundPlayback(allowsPlayback: playbackSettings.allowsBackgroundPlayback)
        guard Self.supports(videoCodec: stream.videoCodec) else {
            fail(PlaybackError.unsupportedVideoCodec(stream.videoCodec)); return
        }
        guard Self.supports(audioCodec: stream.audioCodec) else {
            fail(PlaybackError.unsupportedAudioCodec(stream.audioCodec)); return
        }
        guard stream.videoSegmentBase?.initialization != nil,
              stream.videoSegmentBase?.indexRange != nil,
              stream.audioSegmentBase?.initialization != nil,
              stream.audioSegmentBase?.indexRange != nil
        else { fail(PlaybackError.missingSegmentIndex); return }

        generation &+= 1
        let requestGeneration = generation
        prepareTask?.cancel()
        tearDownItem()
        wantsPlayback = true
        errorMessage = nil
        prepareTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bridge = try await LocalDASHHLSBridge.make(stream: stream, headers: self.headers)
                guard !Task.isCancelled, requestGeneration == self.generation else { bridge.stop(); return }
                self.bridge = bridge
                let asset = AVURLAsset(url: bridge.masterPlaylistURL)
                let item = AVPlayerItem(asset: asset)
                self.install(item)
            } catch is CancellationError {
            } catch {
                guard requestGeneration == self.generation else { return }
                self.fail(error)
            }
        }
    }

    func play(liveURL: URL) {
        configureBackgroundPlayback(allowsPlayback: playbackSettings.allowsLiveBackgroundPlayback)
        generation &+= 1
        prepareTask?.cancel()
        tearDownItem()
        wantsPlayback = true
        errorMessage = nil
        let asset = AVURLAsset(url: liveURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        install(item)
        player.playImmediately(atRate: Float(playbackRate))
    }

    func resume() { wantsPlayback = true; player.playImmediately(atRate: Float(playbackRate)); publish() }
    func pause() { wantsPlayback = false; player.pause(); publish() }
    func stop() { wantsPlayback = false; generation &+= 1; prepareTask?.cancel(); tearDownItem(); publish() }
    func setRate(_ rate: Double) { playbackRate = max(rate, 0.1); if wantsPlayback { player.rate = Float(playbackRate) }; publish() }
    func seek(to time: TimeInterval) {
        seekRevision &+= 1
        let targetTime = max(time, 0)
        guard player.currentItem?.status == .readyToPlay else {
            pendingSeekTime = targetTime
            return
        }
        performSeek(to: targetTime)
        publish()
    }

    private func install(_ item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
        observations = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, self.player.currentItem === item else { return }
                    if item.status == .failed {
                        self.fail(item.error ?? PlaybackError.preparationFailed)
                    } else if item.status == .readyToPlay {
                        self.applyBufferPreference(to: item)
                        self.applyPendingSeekAndPlayback()
                    } else {
                        self.publish()
                    }
                }
            },
            item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.publish() } },
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in Task { @MainActor in self?.publish() } }
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] _ in self?.publish() }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleEnd() }
        }
        publish()
    }

    private func handleEnd() { wantsPlayback = false; publish() }

    private func performSeek(to time: TimeInterval, completion: (() -> Void)? = nil) {
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            completion?()
        }
        publish()
    }

    private func applyPendingSeekAndPlayback() {
        let startPlayback = { [weak self] in
            guard let self, self.wantsPlayback else { return }
            self.player.playImmediately(atRate: Float(self.playbackRate))
        }
        if let pendingSeekTime {
            self.pendingSeekTime = nil
            performSeek(to: pendingSeekTime, completion: startPlayback)
        } else {
            startPlayback()
        }
    }

    private func publish() {
        let item = player.currentItem
        let time = player.currentTime().seconds
        let duration = item?.duration.seconds ?? 0
        let buffered = item?.loadedTimeRanges.compactMap { range -> TimeInterval? in
            let r = range.timeRangeValue
            return CMTimeRangeGetEnd(r).seconds
        }.max() ?? 0
        var hdrDiagnostics = HDRPlaybackDiagnostics()
        hdrDiagnostics.isEnabledInSettings = playbackSettings.highDynamicRangeEnabled
        hdrDiagnostics.prefersEDROutput = playbackSettings.prefersEDROutput
        hdrDiagnostics.requestsExtendedRange = layer?.wantsExtendedDynamicRangeContent ?? false
        snapshot = PlayerUIPlaybackSnapshot(
            currentTime: time.isFinite ? max(time, 0) : 0,
            duration: duration.isFinite ? max(duration, 0) : 0,
            bufferedUntil: buffered.isFinite ? max(buffered, 0) : 0,
            isPlaying: wantsPlayback && player.timeControlStatus != .paused,
            isBuffering: wantsPlayback && player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
            loadingSpeedBytesPerSecond: 0,
            hdrDiagnostics: hdrDiagnostics
        )
        onSnapshot?(snapshot)
    }

    private func tearDownItem() {
        stopPictureInPicture()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.removeAll()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
        bridge?.stop(); bridge = nil
    }

    private func fail(_ error: Error) { errorMessage = error.localizedDescription; wantsPlayback = false; tearDownItem(); publish() }

    private func applyBufferPreference(to item: AVPlayerItem) {
        let duration = item.duration.seconds
        item.preferredForwardBufferDuration = preferredForwardBufferDuration(
            for: playbackSettings.bufferSize,
            mediaDuration: duration.isFinite && duration > 0 ? duration : nil
        )
    }

    /// This is advisory: AVFoundation may shorten the buffer under memory pressure.
    private func preferredForwardBufferDuration(
        for option: VideoBufferSizeOption,
        mediaDuration: TimeInterval?
    ) -> TimeInterval {
        switch option {
        case .auto:
            return 0
        case .huge:
            return mediaDuration ?? 120
        case .mb1: return 2
        case .mb2: return 5
        case .mb4: return 10
        case .mb8: return 20
        case .mb16: return 30
        case .mb32: return 60
        case .mb64: return 120
        }
    }

    private func applyDynamicRangePreference(to layer: AVPlayerLayer?) {
        layer?.wantsExtendedDynamicRangeContent = playbackSettings.highDynamicRangeEnabled
            && playbackSettings.prefersEDROutput
    }

    private func configureBackgroundPlayback(allowsPlayback: Bool) {
        player.audiovisualBackgroundPlaybackPolicy = allowsPlayback
            ? .continuesIfPossible
            : .automatic
    }

    func pictureInPictureController(
        _: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        errorMessage = "无法启动系统画中画：\(error.localizedDescription)"
        publish()
    }

    private static func supports(videoCodec: String) -> Bool {
        let value = videoCodec.lowercased()
        return value.contains("avc1") || value.contains("hvc1") || value.contains("hev1") || value.contains("dvhe") || value.contains("dvh1")
    }
    private static func supports(audioCodec: String) -> Bool {
        let value = audioCodec.lowercased()
        return value.contains("mp4a") || value.contains("aac") || value.contains("ec-3") || value.contains("ac-3")
    }

    deinit { prepareTask?.cancel(); tearDownItem(); layer?.removeFromSuperlayer() }
}

private struct DASHByteRange { let start: Int64; let end: Int64; var header: String { "bytes=\(start)-\(end)" } }
private struct DASHSegment { let range: DASHByteRange; let duration: Double; let start: Double; let startTicks: UInt64; let timescale: UInt32 }

private enum DASHBridgeError: Error { case invalidRange, invalidIndex, unsupported }

private final class LocalDASHHLSBridge: @unchecked Sendable {
    let masterPlaylistURL: URL
    private let server: LoopbackHTTPServer
    private init(server: LoopbackHTTPServer, masterPlaylistURL: URL) { self.server = server; self.masterPlaylistURL = masterPlaylistURL }
    func stop() { server.stop() }

    static func make(stream: DashStream, headers: [String: String]) async throws -> LocalDASHHLSBridge {
        guard let videoBase = stream.videoSegmentBase, let audioBase = stream.audioSegmentBase else { throw DASHBridgeError.unsupported }
        async let video = rendition(url: stream.videoURL, base: videoBase, headers: headers)
        async let audio = rendition(url: stream.audioURL, base: audioBase, headers: headers)
        let (v, a) = try await (video, audio)
        let server = try LoopbackHTTPServer.make(headers: headers)
        let base = server.baseURL
        server.add(path: "/master.m3u8", route: .data(master(stream: stream, base: base)))
        server.add(path: "/video.m3u8", route: .data(v.playlist(base: base, prefix: "v")))
        server.add(path: "/audio.m3u8", route: .data(a.playlist(base: base, prefix: "a")))
        v.register(prefix: "v", into: server)
        a.register(prefix: "a", into: server)
        try await server.start()
        return LocalDASHHLSBridge(server: server, masterPlaylistURL: base.appendingPathComponent("master.m3u8"))
    }

    private static func master(stream: DashStream, base: URL) -> Data {
        let codec = "\(stream.videoCodec),\(stream.audioCodec)"
        let text = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"Audio\",DEFAULT=YES,AUTOSELECT=YES,URI=\"\(base.appendingPathComponent("audio.m3u8").absoluteString)\"\n#EXT-X-STREAM-INF:BANDWIDTH=\(stream.videoBitrate + stream.audioBitrate),CODECS=\"\(codec)\",RESOLUTION=\(stream.width)x\(stream.height),AUDIO=\"audio\"\n\(base.appendingPathComponent("video.m3u8").absoluteString)\n"
        return Data(text.utf8)
    }

    private static func rendition(url: URL, base: DASHSegmentBase, headers: [String: String]) async throws -> DASHRendition {
        guard let initRange = parse(base.initialization), let indexRange = parse(base.indexRange) else { throw DASHBridgeError.invalidRange }
        let index = try await fetch(url: url, range: indexRange, headers: headers)
        let segments = try SIDX.parse(index, offset: indexRange.start)
        guard !segments.isEmpty else { throw DASHBridgeError.invalidIndex }
        return DASHRendition(url: url, initialization: initRange, segments: segments)
    }

    private static func parse(_ value: String?) -> DASHByteRange? {
        guard let value else { return nil }; let parts = value.split(separator: "-")
        guard parts.count == 2, let start = Int64(parts[0]), let end = Int64(parts[1]), start >= 0, end >= start else { return nil }
        return DASHByteRange(start: start, end: end)
    }
    private static func fetch(url: URL, range: DASHByteRange, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url); request.setValue(range.header, forHTTPHeaderField: "Range"); request.timeoutInterval = 15
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw DASHBridgeError.unsupported }
        return data
    }
}

private struct DASHRendition {
    let url: URL; let initialization: DASHByteRange; let segments: [DASHSegment]
    func playlist(base: URL, prefix: String) -> Data {
        let target = max(1, Int(ceil(segments.map(\.duration).max() ?? 1)))
        let lines = segments.enumerated().map { "#EXTINF:\(String(format: "%.6f", $0.element.duration)),\n\(base.appendingPathComponent("media/\(prefix)/\($0.offset).m4s").absoluteString)" }.joined(separator: "\n")
        return Data("#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-TARGETDURATION:\(target)\n#EXT-X-MAP:URI=\"\(base.appendingPathComponent("media/\(prefix)/init.mp4").absoluteString)\"\n\(lines)\n#EXT-X-ENDLIST\n".utf8)
    }
    func register(prefix: String, into server: LoopbackHTTPServer) {
        server.add(path: "/media/\(prefix)/init.mp4", route: .remote(url, initialization, 0))
        for (index, segment) in segments.enumerated() { server.add(path: "/media/\(prefix)/\(index).m4s", route: .remote(url, segment.range, segment.startTicks)) }
    }
}

private enum SIDX {
    static func parse(_ data: Data, offset: Int64) throws -> [DASHSegment] {
        let b = [UInt8](data); guard b.count >= 32 else { throw DASHBridgeError.invalidIndex }
        var p = 0
        while p + 8 <= b.count && String(bytes: b[(p + 4)..<(p + 8)], encoding: .ascii) != "sidx" { let size = Int(u32(b, p)); guard size >= 8 else { throw DASHBridgeError.invalidIndex }; p += size }
        guard p + 32 <= b.count else { throw DASHBridgeError.invalidIndex }
        let size = Int64(u32(b, p)); let version = b[p + 8]; var c = p + 12 + 4; let scale = u32(b, c); c += 4; guard scale > 0 else { throw DASHBridgeError.invalidIndex }
        let earliest: UInt64; let first: Int64
        if version == 0 { earliest = UInt64(u32(b, c)); c += 4; first = Int64(u32(b, c)); c += 4 } else { earliest = u64(b, c); c += 8; first = Int64(u64(b, c)); c += 8 }
        c += 2; let count = Int(u16(b, c)); c += 2; var media = offset + Int64(p) + size + first; var ticks = earliest; var out: [DASHSegment] = []
        for _ in 0..<count where c + 12 <= b.count { let info = u32(b, c); c += 4; let durationTicks = u32(b, c); c += 8; let length = Int64(info & 0x7fff_ffff); guard length > 0 else { continue }; if info & 0x8000_0000 == 0 { out.append(DASHSegment(range: .init(start: media, end: media + length - 1), duration: Double(durationTicks) / Double(scale), start: Double(ticks - earliest) / Double(scale), startTicks: earliest, timescale: scale)); ticks += UInt64(durationTicks) }; media += length }
        return out
    }
    static func u16(_ b: [UInt8], _ p: Int) -> UInt16 { UInt16(b[p]) << 8 | UInt16(b[p + 1]) }
    static func u32(_ b: [UInt8], _ p: Int) -> UInt32 { UInt32(b[p]) << 24 | UInt32(b[p + 1]) << 16 | UInt32(b[p + 2]) << 8 | UInt32(b[p + 3]) }
    static func u64(_ b: [UInt8], _ p: Int) -> UInt64 { UInt64(u32(b, p)) << 32 | UInt64(u32(b, p + 4)) }
}

private final class LoopbackHTTPServer: @unchecked Sendable {
    enum Route { case data(Data); case remote(URL, DASHByteRange, UInt64) }
    let baseURL: URL
    private let listener: NWListener; private let queue = DispatchQueue(label: "pilipod.avplayer.hls"); private let headers: [String: String]
    private var routes: [String: Route] = [:]; private var connections: [ObjectIdentifier: NWConnection] = [:]
    init(headers: [String: String]) throws { let port = NWEndpoint.Port(rawValue: UInt16.random(in: 49152...61000))!; let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any); listener = try NWListener(using: parameters, on: port); baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)")!; self.headers = headers }
    static func make(headers: [String: String]) throws -> LoopbackHTTPServer {
        var lastError: Error?
        for _ in 0..<24 {
            do { return try LoopbackHTTPServer(headers: headers) }
            catch { lastError = error }
        }
        throw lastError ?? DASHBridgeError.unsupported
    }
    func add(path: String, route: Route) { routes[path] = route }
    func start() async throws { try await withCheckedThrowingContinuation { continuation in var resumed = false; listener.stateUpdateHandler = { state in if resumed { return }; switch state { case .ready: resumed = true; continuation.resume(); case let .failed(error): resumed = true; continuation.resume(throwing: error); default: break } }; listener.newConnectionHandler = { [weak self] in self?.accept($0) }; listener.start(queue: queue) } }
    func stop() { listener.cancel(); connections.values.forEach { $0.cancel() }; connections.removeAll() }
    private func accept(_ connection: NWConnection) { guard case let .hostPort(host, _) = connection.endpoint, host == .ipv4(IPv4Address("127.0.0.1")!) || host == .ipv6(IPv6Address("::1")!) else { connection.cancel(); return }; let id = ObjectIdentifier(connection); connections[id] = connection; connection.start(queue: queue); connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in self?.respond(connection, data ?? Data(), id: id) } }
    private func respond(_ c: NWConnection, _ data: Data, id: ObjectIdentifier) { defer { connections[id] = nil }; guard let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first else { return send(c, status: "400 Bad Request", data: Data(), type: "text/plain") }; let pieces = line.split(separator: " "); guard pieces.count > 1, let route = routes[String(pieces[1])] else { return send(c, status: "404 Not Found", data: Data(), type: "text/plain") }; switch route { case let .data(payload): send(c, status: "200 OK", data: payload, type: "application/vnd.apple.mpegurl"); case let .remote(url, range, timeOffset): Task { [headers] in do { var req = URLRequest(url: url); req.setValue(range.header, forHTTPHeaderField: "Range"); headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }; let (payload, _) = try await URLSession.shared.data(for: req); self.queue.async { self.send(c, status: "200 OK", data: MP4Timeline.normalize(payload, subtracting: timeOffset), type: "video/iso.segment") } } catch { self.queue.async { self.send(c, status: "502 Bad Gateway", data: Data(), type: "text/plain") } } } } }
    private func send(_ c: NWConnection, status: String, data: Data, type: String) { let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"; var response = Data(head.utf8); response.append(data); c.send(content: response, completion: .contentProcessed { _ in c.cancel() }) }
    deinit { stop() }
}

private enum MP4Timeline {
    static func normalize(_ data: Data, subtracting offset: UInt64) -> Data { guard offset > 0 else { return data }; var value = data; let byteCount = value.count; value.withUnsafeMutableBytes { raw in guard let b = raw.bindMemory(to: UInt8.self).baseAddress else { return }; rewrite(b, length: byteCount, offset: 0, subtracting: offset) }; return value }
    private static func rewrite(_ b: UnsafeMutablePointer<UInt8>, length: Int, offset: Int, subtracting adjustment: UInt64) { var p = offset; while p + 8 <= offset + length { let size = Int(read32(b, p)); guard size >= 8, p + size <= offset + length else { return }; if String(bytes: UnsafeBufferPointer(start: b + p + 4, count: 4), encoding: .ascii) == "tfdt", p + 16 <= offset + length { let version = b[p + 8]; if version == 1, p + 20 <= offset + length { write64(b, p + 12, max(read64(b, p + 12), adjustment) - adjustment) } else { write32(b, p + 12, UInt32(max(UInt64(read32(b, p + 12)), adjustment) - adjustment)) } } else if ["moof", "traf"].contains(String(bytes: UnsafeBufferPointer(start: b + p + 4, count: 4), encoding: .ascii) ?? "") { rewrite(b, length: size - 8, offset: p + 8, subtracting: adjustment) }; p += size } }
    private static func read32(_ b: UnsafeMutablePointer<UInt8>, _ p: Int) -> UInt32 { UInt32(b[p]) << 24 | UInt32(b[p+1]) << 16 | UInt32(b[p+2]) << 8 | UInt32(b[p+3]) }; private static func read64(_ b: UnsafeMutablePointer<UInt8>, _ p: Int) -> UInt64 { UInt64(read32(b,p)) << 32 | UInt64(read32(b,p+4)) }; private static func write32(_ b: UnsafeMutablePointer<UInt8>, _ p: Int, _ n: UInt32) { b[p] = UInt8(n >> 24); b[p+1] = UInt8(n >> 16); b[p+2] = UInt8(n >> 8); b[p+3] = UInt8(n) }; private static func write64(_ b: UnsafeMutablePointer<UInt8>, _ p: Int, _ n: UInt64) { write32(b,p,UInt32(n >> 32)); write32(b,p+4,UInt32(n)) }
}

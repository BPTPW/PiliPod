//
//  LiveDanmakuService.swift
//  PiliPod
//
//  Created by Codex on 2026/6/8.
//

import Compression
import CoreGraphics
import Foundation

struct LiveDanmakuEmoticon: Equatable {
    let placeholder: String
    let url: URL?
    let width: CGFloat
    let height: CGFloat
}

enum LiveDanmakuSegment: Equatable {
    case text(String)
    case emoticon(LiveDanmakuEmoticon)
}

struct LiveDanmakuMessage: Identifiable, Equatable {
    let id = UUID()
    let username: String
    let content: String
    let sentAt: Date?
    let segments: [LiveDanmakuSegment]

    init(
        username: String,
        content: String,
        sentAt: Date?,
        emoticons: [LiveDanmakuEmoticon] = []
    ) {
        self.username = username
        self.content = content
        self.sentAt = sentAt
        self.segments = LiveDanmakuMessage.makeSegments(content: content, emoticons: emoticons)
    }

    private static func makeSegments(content: String, emoticons: [LiveDanmakuEmoticon]) -> [LiveDanmakuSegment] {
        guard !content.isEmpty else { return [] }

        let sortedEmoticons = emoticons
            .filter { !$0.placeholder.isEmpty }
            .sorted { $0.placeholder.count > $1.placeholder.count }

        guard !sortedEmoticons.isEmpty else {
            return [.text(content)]
        }

        var segments: [LiveDanmakuSegment] = []
        var currentIndex = content.startIndex

        while currentIndex < content.endIndex {
            var matchedEmoticon: LiveDanmakuEmoticon?

            for emoticon in sortedEmoticons {
                guard content[currentIndex...].hasPrefix(emoticon.placeholder) else { continue }
                matchedEmoticon = emoticon
                break
            }

            if let matchedEmoticon {
                segments.append(.emoticon(matchedEmoticon))
                currentIndex = content.index(currentIndex, offsetBy: matchedEmoticon.placeholder.count)
                continue
            }

            var nextIndex = content.index(after: currentIndex)
            while nextIndex < content.endIndex {
                let remaining = content[nextIndex...]
                let shouldStop = sortedEmoticons.contains { remaining.hasPrefix($0.placeholder) }
                if shouldStop {
                    break
                }
                nextIndex = content.index(after: nextIndex)
            }

            let text = String(content[currentIndex..<nextIndex])
            if !text.isEmpty {
                segments.append(.text(text))
            }
            currentIndex = nextIndex
        }

        return segments
    }
}

struct LiveDanmakuInfo {
    let token: String
    let hosts: [LiveDanmakuHost]
}

struct LiveDanmakuHost {
    let host: String
    let wssPort: Int
}

@MainActor
final class LiveDanmakuService: NSObject {
    var onMessage: ((LiveDanmakuMessage) -> Void)?
    var onError: ((String) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var sequence: UInt32 = 1
    private var isClosed = false

    func connect(roomID: Int) async {
        close()

        do {
            let info = try await BiliAPI.shared.fetchLiveDanmakuInfo(roomID: roomID)
            guard let host = info.hosts.first else {
                onError?("未获取到弹幕服务器")
                return
            }
            guard let url = URL(string: "wss://\(host.host):\(host.wssPort)/sub") else {
                onError?("弹幕服务器地址无效")
                return
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let cookie = LoginSession.shared.cookieString
            if !cookie.isEmpty {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            request.setValue("https://live.bilibili.com", forHTTPHeaderField: "Origin")
            request.setValue("https://live.bilibili.com/\(roomID)", forHTTPHeaderField: "Referer")

            let session = URLSession(configuration: .default)
            self.session = session
            let task = session.webSocketTask(with: request)
            webSocketTask = task
            isClosed = false
            task.resume()

            try await sendAuthentication(token: info.token, roomID: roomID)
            startHeartbeat()
            receiveLoop()
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func close() {
        isClosed = true
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func receiveLoop() {
        guard let webSocketTask else { return }

        webSocketTask.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isClosed else { return }

                switch result {
                case .failure(let error):
                    self.onError?(error.localizedDescription)
                case .success(let message):
                    switch message {
                    case .data(let data):
                        self.handleIncomingPacket(data)
                    case .string(let text):
                        self.handleIncomingPacket(Data(text.utf8))
                    @unknown default:
                        break
                    }
                    self.receiveLoop()
                }
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                try? await self.sendHeartbeat()
            }
        }
    }

    private func sendAuthentication(token: String, roomID: Int) async throws {
        let payload: [String: Any] = [
            "uid": Int(LoginSession.shared.cookies?.DedeUserID ?? "") ?? 0,
            "roomid": roomID,
            "protover": 3,
            "platform": "web",
            "type": 2,
            "key": token
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await sendPacket(body: body, operation: 7)
    }

    private func sendHeartbeat() async throws {
        try await sendPacket(body: Data("[object Object]".utf8), operation: 2)
    }

    private func sendPacket(body: Data, operation: UInt32) async throws {
        guard let webSocketTask else { throw URLError(.badServerResponse) }
        let packet = makePacket(body: body, protocolVersion: 1, operation: operation)
        try await webSocketTask.send(.data(packet))
    }

    private func makePacket(body: Data, protocolVersion: UInt16, operation: UInt32) -> Data {
        let headerLength: UInt16 = 16
        let totalLength = UInt32(headerLength) + UInt32(body.count)
        var data = Data()
        data.append(totalLength.bigEndianData)
        data.append(headerLength.bigEndianData)
        data.append(protocolVersion.bigEndianData)
        data.append(operation.bigEndianData)
        data.append(sequence.bigEndianData)
        data.append(body)
        sequence &+= 1
        return data
    }

    private func handleIncomingPacket(_ data: Data) {
        for packet in decodePackets(from: data) {
            if packet.operation == 5 {
                decodeCommandPackets(from: packet.body, protocolVersion: packet.protocolVersion)
            }
        }
    }

    private func decodeCommandPackets(from body: Data, protocolVersion: UInt16) {
        switch protocolVersion {
        case 0, 1:
            decodeNestedPackets(from: body)
        case 2:
            if let inflated = decompress(body, algorithm: COMPRESSION_ZLIB) {
                decodeNestedPackets(from: inflated)
            }
        case 3:
            if let inflated = decompress(body, algorithm: COMPRESSION_BROTLI) {
                decodeNestedPackets(from: inflated)
            }
        default:
            break
        }
    }

    private func decodeNestedPackets(from data: Data) {
        for packet in decodePackets(from: data) {
            guard packet.operation == 5 else { continue }
            if let jsonObject = try? JSONSerialization.jsonObject(with: packet.body) as? [String: Any] {
                handleCommand(jsonObject)
            }
        }
    }

    private func handleCommand(_ payload: [String: Any]) {
        guard let command = payload["cmd"] as? String else { return }
        guard command.hasPrefix("DANMU_MSG") else { return }
        guard
            let info = payload["info"] as? [Any],
            info.count > 2,
            let content = info[1] as? String,
            let userInfo = info[2] as? [Any],
            userInfo.count > 1,
            let username = userInfo[1] as? String
        else {
            return
        }

        let emoticons = extractEmoticons(from: info)
        onMessage?(
            LiveDanmakuMessage(
                username: username,
                content: content,
                sentAt: nil,
                emoticons: emoticons
            )
        )
    }

    private func extractEmoticons(from info: [Any]) -> [LiveDanmakuEmoticon] {
        if let extraEmoticons = extractEmoticonsFromExtra(in: info), !extraEmoticons.isEmpty {
            return extraEmoticons
        }
        return extractEmoticonsRecursively(from: info)
    }

    private func extractEmoticonsFromExtra(in info: [Any]) -> [LiveDanmakuEmoticon]? {
        guard
            info.indices.contains(0),
            let meta = info[0] as? [Any],
            meta.indices.contains(15),
            let extraObject = meta[15] as? [String: Any],
            let extraJSONString = extraObject["extra"] as? String,
            let extraData = extraJSONString.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
            let emots = jsonObject["emots"] as? [String: Any]
        else {
            return nil
        }

        let mapped = mapEmoticonDictionary(emots)
        return mapped.isEmpty ? nil : mapped
    }

    private func extractEmoticonsRecursively(from value: Any?) -> [LiveDanmakuEmoticon] {
        guard let value else { return [] }

        if let dictionary = value as? [String: Any] {
            let mapped = mapEmoticonDictionary(dictionary)
            if !mapped.isEmpty {
                return mapped
            }

            for nestedValue in dictionary.values {
                let nested = extractEmoticonsRecursively(from: nestedValue)
                if !nested.isEmpty {
                    return nested
                }
            }
            return []
        }

        if let array = value as? [Any] {
            for item in array {
                let nested = extractEmoticonsRecursively(from: item)
                if !nested.isEmpty {
                    return nested
                }
            }
        }

        return []
    }

    private func mapEmoticonDictionary(_ dictionary: [String: Any]) -> [LiveDanmakuEmoticon] {
        dictionary.compactMap { key, value in
            guard let payload = value as? [String: Any] else { return nil }

            let placeholder = (payload["emoji"] as? String)
                ?? (payload["descript"] as? String)
                ?? key
            guard !placeholder.isEmpty else { return nil }

            let urlString = (payload["url"] as? String)?.replacingOccurrences(of: "http://", with: "https://")
            let width = CGFloat((payload["width"] as? Double) ?? Double(payload["width"] as? Int ?? 20))
            let height = CGFloat((payload["height"] as? Double) ?? Double(payload["height"] as? Int ?? 20))

            return LiveDanmakuEmoticon(
                placeholder: placeholder,
                url: urlString.flatMap(URL.init(string:)),
                width: max(width, 1),
                height: max(height, 1)
            )
        }
    }

    private func decodePackets(from data: Data) -> [DecodedPacket] {
        var packets: [DecodedPacket] = []
        var offset = 0

        while offset + 16 <= data.count {
            let packetLength = Int(data.readUInt32(at: offset))
            let headerLength = Int(data.readUInt16(at: offset + 4))
            let protocolVersion = data.readUInt16(at: offset + 6)
            let operation = data.readUInt32(at: offset + 8)

            guard packetLength > 0, offset + packetLength <= data.count, headerLength <= packetLength else {
                break
            }

            let bodyStart = offset + headerLength
            let body = data.subdata(in: bodyStart..<(offset + packetLength))
            packets.append(
                DecodedPacket(
                    protocolVersion: protocolVersion,
                    operation: operation,
                    body: body
                )
            )

            offset += packetLength
        }

        return packets
    }

    private func decompress(_ data: Data, algorithm: compression_algorithm) -> Data? {
        let bufferSize = 64 * 1024
        var output = Data()
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dstBuffer.deallocate() }

        return data.withUnsafeBytes { rawBuffer in
            guard let srcBase = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer { stream.deallocate() }

            var status = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, algorithm)
            guard status != COMPRESSION_STATUS_ERROR else { return nil }
            defer { compression_stream_destroy(stream) }

            stream.pointee.src_ptr = srcBase
            stream.pointee.src_size = data.count
            stream.pointee.dst_ptr = dstBuffer
            stream.pointee.dst_size = bufferSize

            repeat {
                status = compression_stream_process(stream, Int32(0))
                let produced = bufferSize - stream.pointee.dst_size
                if produced > 0 {
                    output.append(dstBuffer, count: produced)
                    stream.pointee.dst_ptr = dstBuffer
                    stream.pointee.dst_size = bufferSize
                }
            } while status == COMPRESSION_STATUS_OK

            guard status == COMPRESSION_STATUS_END else { return nil }
            return output
        }
    }
}

private struct DecodedPacket {
    let protocolVersion: UInt16
    let operation: UInt32
    let body: Data
}

private extension FixedWidthInteger {
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
}

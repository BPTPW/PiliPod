import Foundation

/// Bilibili's K/N markers describe segment independence, not segment duration.
/// Keep a fixed initial sequence floor; never chase a newer K on playlist reload.
struct LiveHLSPlaylist {
    let lines: [String]
    let mediaSequence: Int
    let segmentStarts: [Int]
    let latestKeyframeIndex: Int?

    init?(text: String) {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "#EXTM3U",
              let sequenceLine = lines.first(where: { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") }),
              let sequence = Int(sequenceLine.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)),
              sequence >= 0,
              !lines.contains(where: {
                  $0.hasPrefix("#EXT-X-BYTERANGE:") || $0.hasPrefix("#EXT-X-DISCONTINUITY")
                      || $0.hasPrefix("#EXT-X-SKIP:") || $0.hasPrefix("#EXT-X-PART:")
              }) else { return nil }
        var starts: [Int] = []
        var latestKey: Int?
        var pendingStart: Int?
        var pendingKey = false
        var hasDuration = false
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("#EXT-BILI-AUX:") {
                pendingStart = pendingStart ?? index
                let fields = line.dropFirst("#EXT-BILI-AUX:".count).split(separator: "|", omittingEmptySubsequences: false)
                pendingKey = fields.count >= 2 && fields[1] == "K"
            } else if line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
                pendingStart = pendingStart ?? index
            } else if line.hasPrefix("#EXTINF:") {
                guard !hasDuration,
                      let value = line.dropFirst("#EXTINF:".count).split(separator: ",").first,
                      let duration = Double(value), duration.isFinite, duration > 0 else { return nil }
                pendingStart = pendingStart ?? index
                hasDuration = true
            } else if !line.hasPrefix("#") {
                guard hasDuration, let start = pendingStart else { return nil }
                if pendingKey { latestKey = starts.count }
                starts.append(start)
                pendingStart = nil
                pendingKey = false
                hasDuration = false
            } else if !starts.isEmpty || pendingStart != nil {
                // Stateful tags between segments need a different trim policy.
                if line.hasPrefix("#EXT-X-MAP:") || line.hasPrefix("#EXT-X-KEY:") { return nil }
            }
        }
        guard !starts.isEmpty, !hasDuration, sequence <= Int.max - starts.count else { return nil }
        self.lines = lines
        mediaSequence = sequence
        segmentStarts = starts
        latestKeyframeIndex = latestKey
    }

    var latestKeyframeSequence: Int? {
        latestKeyframeIndex.map { mediaSequence + $0 }
    }

    func playbackText(startingAt sequence: Int, baseURL: URL) throws -> String {
        guard sequence < mediaSequence + segmentStarts.count else { throw URLError(.cannotParseResponse) }
        let index = max(sequence - mediaSequence, 0)
        let header = lines[..<segmentStarts[0]].filter {
            !$0.hasPrefix("#EXT-X-START:") && !$0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:")
        }
        let output = header + [
            "#EXT-X-MEDIA-SEQUENCE:\(mediaSequence + index)",
            "#EXT-X-START:TIME-OFFSET=0,PRECISE=YES"
        ] + lines[segmentStarts[index]...]
        return try Self.absolutize(output.joined(separator: "\n") + "\n", baseURL: baseURL)
    }

    /// The local playlist must leave media, initialization and key requests on
    /// the original CDN, resolving relative references against the response URL.
    static func absolutize(_ text: String, baseURL: URL) throws -> String {
        let uriPattern = try NSRegularExpression(pattern: #"URI="([^"]+)""#)
        return try text.split(whereSeparator: \.isNewline).map { raw in
            var line = String(raw)
            if !line.hasPrefix("#") {
                guard let url = URL(string: line, relativeTo: baseURL)?.absoluteURL else { throw URLError(.badURL) }
                return url.absoluteString
            }
            for match in uriPattern.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(match.range(at: 1), in: line),
                      let url = URL(string: String(line[range]), relativeTo: baseURL)?.absoluteURL else { throw URLError(.badURL) }
                line.replaceSubrange(range, with: url.absoluteString)
            }
            return line
        }.joined(separator: "\n") + "\n"
    }
}

actor LiveHLSPlaylistSource {
    private let url: URL
    private let headers: [String: String]
    private let initialSequence: Int
    private var initialData: Data?

    private init(url: URL, headers: [String: String], sequence: Int, data: Data) {
        self.url = url
        self.headers = headers
        initialSequence = sequence
        initialData = data
    }

    static func make(url: URL, headers: [String: String]) async throws -> LiveHLSPlaylistSource? {
        let (text, baseURL) = try await fetch(url: url, headers: headers)
        guard let playlist = LiveHLSPlaylist(text: text),
              let sequence = playlist.latestKeyframeSequence else { return nil }
        let data = Data(try playlist.playbackText(startingAt: sequence, baseURL: baseURL).utf8)
        return LiveHLSPlaylistSource(url: url, headers: headers, sequence: sequence, data: data)
    }

    func load() async throws -> Data {
        if let initialData {
            self.initialData = nil
            return initialData
        }
        let (text, baseURL) = try await Self.fetch(url: url, headers: headers)
        let output: String
        if let playlist = LiveHLSPlaylist(text: text) {
            output = try playlist.playbackText(startingAt: initialSequence, baseURL: baseURL)
        } else {
            // Preserve playback if the origin switches to another valid HLS layout.
            output = try LiveHLSPlaylist.absolutize(text, baseURL: baseURL)
        }
        return Data(output.utf8)
    }

    private static func fetch(url: URL, headers: [String: String]) async throws -> (String, URL) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 3)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") else {
            throw URLError(.cannotParseResponse)
        }
        return (text, response.url ?? url)
    }
}

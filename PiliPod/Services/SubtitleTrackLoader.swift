//
//  SubtitleTrackLoader.swift
//  PiliPod
//

import Foundation
import Observation

struct SubtitleCue: Identifiable, Equatable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

@MainActor
@Observable
final class SubtitleTrackLoader {
    private static let removesMusicMarkers = false

    private(set) var cues: [SubtitleCue] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var loadingTrackID: String?

    func load(track: PlayerSubtitleItem?) async {
        guard let track else {
            loadingTrackID = nil
            cues = []
            errorMessage = nil
            isLoading = false
            return
        }
        guard let url = Self.normalizedURL(from: track.subtitleUrl) else {
            cues = []
            errorMessage = "字幕地址无效"
            return
        }

        let trackID = track.id
        loadingTrackID = trackID
        cues = []
        errorMessage = nil
        isLoading = true
        defer {
            if loadingTrackID == trackID {
                isLoading = false
            }
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 BiliIOS/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
            request.setValue(LoginSession.shared.cookieString, forHTTPHeaderField: "Cookie")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard loadingTrackID == trackID else { return }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else { throw URLError(.badServerResponse) }

            let document = try JSONDecoder().decode(SubtitleDocument.self, from: data)
            cues = document.body.enumerated().compactMap { index, item in
                guard item.to > item.from else { return nil }
                let text = Self.normalizedText(item.content)
                guard !text.isEmpty else { return nil }
                return SubtitleCue(
                    id: item.sid ?? index,
                    start: item.from,
                    end: item.to,
                    text: text
                )
            }
            .sorted { $0.start < $1.start }
        } catch is CancellationError {
            return
        } catch {
            guard loadingTrackID == trackID else { return }
            cues = []
            errorMessage = "字幕加载失败"
            ErrorLogService.record(error, context: "加载视频字幕")
        }
    }

    private static func normalizedURL(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let urlString = value.hasPrefix("//") ? "https:\(value)" : value
        return URL(string: urlString)
    }

    private static func normalizedText(_ text: String) -> String {
        guard removesMusicMarkers else { return text }
        return text
            .replacingOccurrences(of: "♪ ", with: "")
            .replacingOccurrences(of: " ♪", with: "")
    }
}

private struct SubtitleDocument: Decodable {
    let body: [SubtitleDocumentItem]
}

private struct SubtitleDocumentItem: Decodable {
    let from: TimeInterval
    let to: TimeInterval
    let sid: Int?
    let content: String
}

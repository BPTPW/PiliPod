import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsBackupPayload: Codable {
    var appIdentifier = "PiliPod"
    var schemaVersion = 1
    var exportedAt = Date()
    var settings: SettingsSnapshot

    struct SettingsSnapshot: Codable {
        var recommendSource: RecommendAPIMode?
        var audioVideo: AudioVideoSettings?
        var danmaku: DanmakuEngineConfig?
        var sponsorBlock: SponsorBlockSettings?
    }
}

enum AppSettingsBackupError: LocalizedError {
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "无法识别该设置备份文件。"
        }
    }
}

enum AppSettingsBackupService {
    static func makePayload() -> AppSettingsBackupPayload {
        AppSettingsBackupPayload(
            settings: .init(
                recommendSource: RecommendSettingsStore.loadSource(),
                audioVideo: AudioVideoSettingsStore.load(),
                danmaku: DanmakuConfigStore.load(),
                sponsorBlock: SponsorBlockSettingsStore.load()
            )
        )
    }

    static func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(makePayload())
    }

    static func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let payload = try? decoder.decode(AppSettingsBackupPayload.self, from: data),
              payload.appIdentifier == "PiliPod"
        else {
            throw AppSettingsBackupError.invalidPayload
        }

        apply(payload)
    }

    static func importFrom(url: URL) throws {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        try importData(data)
    }

    static func apply(_ payload: AppSettingsBackupPayload) {
        if let recommendSource = payload.settings.recommendSource {
            RecommendSettingsStore.saveSource(recommendSource)
        }

        if let audioVideo = payload.settings.audioVideo {
            AudioVideoSettingsStore.save(audioVideo)
        }

        if let danmaku = payload.settings.danmaku {
            DanmakuConfigStore.save(danmaku)
        }

        if let sponsorBlock = payload.settings.sponsorBlock {
            var normalized = sponsorBlock.clamped()
            SponsorBlockSettingsStore.ensureUserIDIfNeeded(for: &normalized)
            SponsorBlockSettingsStore.save(normalized)
        }
    }
}

struct AppSettingsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

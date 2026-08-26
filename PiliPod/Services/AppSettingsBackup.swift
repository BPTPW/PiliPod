import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsBackupPayload: Codable {
    var appIdentifier = "PiliPod"
    var schemaVersion = 2
    var exportedAt = Date()
    var settings: SettingsSnapshot

    struct SettingsSnapshot: Codable {
        var recommendSource: RecommendAPIMode?
        var audioVideo: AudioVideoSettings?
        var subtitle: SubtitleSettings?
        var danmaku: DanmakuEngineConfig?
        var sponsorBlock: SponsorBlockSettings?
        var errorLogMaximumEntryCount: Int?

        private enum CodingKeys: String, CodingKey {
            case recommendSource
            case audioVideo
            case subtitle
            case danmaku
            case sponsorBlock
            case errorLogMaximumEntryCount
        }

        init(
            recommendSource: RecommendAPIMode? = nil,
            audioVideo: AudioVideoSettings? = nil,
            subtitle: SubtitleSettings? = nil,
            danmaku: DanmakuEngineConfig? = nil,
            sponsorBlock: SponsorBlockSettings? = nil,
            errorLogMaximumEntryCount: Int? = nil
        ) {
            self.recommendSource = recommendSource
            self.audioVideo = audioVideo
            self.subtitle = subtitle
            self.danmaku = danmaku
            self.sponsorBlock = sponsorBlock
            self.errorLogMaximumEntryCount = errorLogMaximumEntryCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            recommendSource = try container.decodeIfPresent(RecommendAPIMode.self, forKey: .recommendSource)
            audioVideo = try container.decodeIfPresent(AudioVideoSettings.self, forKey: .audioVideo)
            subtitle = try container.decodeIfPresent(SubtitleSettings.self, forKey: .subtitle)
            danmaku = try container.decodeIfPresent(DanmakuEngineConfig.self, forKey: .danmaku)
            sponsorBlock = try container.decodeIfPresent(SponsorBlockSettings.self, forKey: .sponsorBlock)
            errorLogMaximumEntryCount = try container.decodeIfPresent(Int.self, forKey: .errorLogMaximumEntryCount)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case appIdentifier
        case schemaVersion
        case exportedAt
        case settings
    }

    init(
        appIdentifier: String = "PiliPod",
        schemaVersion: Int = 2,
        exportedAt: Date = Date(),
        settings: SettingsSnapshot
    ) {
        self.appIdentifier = appIdentifier
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appIdentifier = try container.decodeIfPresent(String.self, forKey: .appIdentifier) ?? "PiliPod"
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        settings = try container.decodeIfPresent(SettingsSnapshot.self, forKey: .settings) ?? SettingsSnapshot()
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
                subtitle: SubtitleSettingsStore.load(),
                danmaku: DanmakuConfigStore.load(),
                sponsorBlock: SponsorBlockSettingsStore.load(),
                errorLogMaximumEntryCount: ErrorLogService.shared.maximumEntryCount
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

        if let subtitle = payload.settings.subtitle {
            SubtitleSettingsStore.save(subtitle)
        }

        if let danmaku = payload.settings.danmaku {
            DanmakuConfigStore.save(danmaku)
        }

        if let sponsorBlock = payload.settings.sponsorBlock {
            var normalized = sponsorBlock.clamped()
            SponsorBlockSettingsStore.ensureUserIDIfNeeded(for: &normalized)
            SponsorBlockSettingsStore.save(normalized)
        }

        if let maximumEntryCount = payload.settings.errorLogMaximumEntryCount {
            ErrorLogService.shared.setMaximumEntryCount(maximumEntryCount)
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

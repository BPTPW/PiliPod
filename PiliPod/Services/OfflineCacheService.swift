import Combine
import Foundation
import SwiftProtobuf
import UniformTypeIdentifiers
import ZIPFoundation

struct OfflineCacheQueryPrefill: Identifiable, Hashable {
    let id = UUID()
    let bvid: String
    let cid: Int?
}

struct OfflineCachePlayableAsset {
    let item: OfflineCacheItem
    let detail: VideoDetailData
    let stream: DashStream
}

struct OfflineCacheItem: Identifiable, Codable, Hashable {
    enum Status: String, Codable {
        case queued
        case downloading
        case paused
        case completed
        case failed
    }

    let id: UUID
    var bvid: String
    var aid: Int
    var cid: Int
    var title: String
    var cover: String
    var uploader: String
    var duration: Int
    var qualityCode: Int
    var qualityLabel: String
    var videoCodec: String
    var audioCodec: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var fileSizeBytes: Int64
    var speedBytesPerSecond: Double
    var status: Status
    var errorMessage: String?
    var relativeDirectory: String
    var createdAt: Date
    var updatedAt: Date

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
    }

    var isActive: Bool {
        status == .queued || status == .downloading
    }
}

struct OfflineCacheQueryResult {
    let detail: VideoDetailData
    let resolvedBVID: String
    let resolvedCID: Int
    let playURLResponse: PlayUrlResponse
    let qualityOptions: [VideoQualityOption]
    let defaultQualityCode: Int
}

enum OfflineCacheStorage {
    private static let rootDirectoryName = "OfflineVideoCache"
    private static let indexFileName = "offline-cache-index.json"
    private static let detailFileName = "detail.json"
    private static let manifestFileName = "manifest.json"

    static func rootDirectory() throws -> URL {
        let baseURL = try cacheBaseDirectory()
        let rootURL = baseURL.appendingPathComponent(rootDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return rootURL
    }

    static func indexFileURL() throws -> URL {
        try rootDirectory().appendingPathComponent(indexFileName)
    }

    static func itemDirectoryURL(relativeDirectory: String) throws -> URL {
        try rootDirectory().appendingPathComponent(relativeDirectory, isDirectory: true)
    }

    static func loadItems() -> [OfflineCacheItem] {
        do {
            let url = try indexFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([OfflineCacheItem].self, from: data)
        } catch {
            ErrorLogService.record(error, context: "读取离线缓存索引")
            print("读取离线缓存索引失败: \(error)")
            return []
        }
    }

    static func saveItems(_ items: [OfflineCacheItem]) throws {
        let url = try indexFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: url, options: .atomic)
    }

    static func relativeDirectoryName(
        bvid: String,
        cid: Int,
        qualityCode: Int
    ) -> String {
        let sanitizedBVID = bvid.replacingOccurrences(of: "/", with: "_")
        return "\(sanitizedBVID)_\(cid)_q\(qualityCode)"
    }

    static func loadPlayableAsset(
        bvid: String,
        cid: Int?
    ) -> OfflineCachePlayableAsset? {
        let items = loadItems()
        guard let item = items
            .filter({ $0.status == .completed && $0.bvid == bvid })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first(where: { cid == nil || $0.cid == cid })
        else {
            return nil
        }

        do {
            let directoryURL = try itemDirectoryURL(relativeDirectory: item.relativeDirectory)
            let manifestURL = directoryURL.appendingPathComponent(manifestFileName)
            let detailURL = directoryURL.appendingPathComponent(detailFileName)
            let manifestData = try Data(contentsOf: manifestURL)
            let detailData = try Data(contentsOf: detailURL)
            let manifest = try JSONDecoder().decode(OfflineCacheManifest.self, from: manifestData)
            let detail = try JSONDecoder().decode(VideoDetailData.self, from: detailData)

            let stream = DashStream(
                videoURL: directoryURL.appendingPathComponent(manifest.videoFileName),
                audioURL: directoryURL.appendingPathComponent(manifest.audioFileName),
                videoURLCandidates: [directoryURL.appendingPathComponent(manifest.videoFileName)],
                audioURLCandidates: [directoryURL.appendingPathComponent(manifest.audioFileName)],
                originalVideoURLs: [directoryURL.appendingPathComponent(manifest.videoFileName)],
                originalAudioURLs: [directoryURL.appendingPathComponent(manifest.audioFileName)],
                qualityCode: item.qualityCode,
                videoCodec: item.videoCodec,
                audioCodec: item.audioCodec,
                width: manifest.width,
                height: manifest.height,
                fps: manifest.fps,
                videoBitrate: manifest.videoBitrate,
                audioBitrate: manifest.audioBitrate,
                videoSegmentBase: nil,
                audioSegmentBase: nil
            )
            return OfflineCachePlayableAsset(item: item, detail: detail, stream: stream)
        } catch {
            ErrorLogService.record(error, context: "读取离线缓存视频")
            print("读取离线缓存视频失败: \(error)")
            return nil
        }
    }

    static func loadDanmakuElements(
        bvid: String,
        cid: Int
    ) -> [Bilibili_Community_Service_Dm_V1_DanmakuElem] {
        guard let asset = loadPlayableAsset(bvid: bvid, cid: cid) else { return [] }
        do {
            let directoryURL = try itemDirectoryURL(relativeDirectory: asset.item.relativeDirectory)
            let contents = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let danmakuFiles = contents
                .filter { $0.lastPathComponent.hasPrefix("danmaku-") && $0.pathExtension == "pb" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            var merged: [Bilibili_Community_Service_Dm_V1_DanmakuElem] = []
            for fileURL in danmakuFiles {
                let data = try Data(contentsOf: fileURL)
                let reply = try Bilibili_Community_Service_Dm_V1_DmSegMobileReply(serializedBytes: data)
                merged.append(contentsOf: reply.elems)
            }

            var seen = Set<Int64>()
            return merged
                .filter { element in
                    if seen.contains(element.id) { return false }
                    seen.insert(element.id)
                    return true
                }
                .sorted { lhs, rhs in
                    if lhs.progress == rhs.progress {
                        return lhs.id < rhs.id
                    }
                    return lhs.progress < rhs.progress
                }
        } catch {
            ErrorLogService.record(error, context: "读取离线弹幕")
            print("读取离线弹幕失败: \(error)")
            return []
        }
    }

    private static func cacheBaseDirectory() throws -> URL {
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return cachesURL
        }
        return FileManager.default.temporaryDirectory
    }
}

private struct OfflineCacheManifest: Codable {
    let videoFileName: String
    let audioFileName: String
    let width: Int
    let height: Int
    let fps: Double
    let videoBitrate: Int
    let audioBitrate: Int
    let videoCodec: String
    let audioCodec: String
}

enum OfflineCacheTransferError: LocalizedError {
    case itemNotCompleted
    case missingFile(String)
    case invalidArchive
    case unsupportedArchiveLayout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .itemNotCompleted:
            return "只有已完成的缓存才可以导出。"
        case let .missingFile(name):
            return "缓存文件不完整，缺少 \(name)。"
        case .invalidArchive:
            return "无法识别该缓存压缩包。"
        case .unsupportedArchiveLayout:
            return "压缩包内容不符合 PiliPod 离线缓存格式。"
        case .cancelled:
            return "导出已取消。"
        }
    }
}

struct OfflineCacheExportOption: Identifiable {
    enum Kind {
        case video
        case audio
        case danmaku
        case manifest
        case detail
        case packageZip
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String
}

struct OfflineCacheExportFile {
    let url: URL
    let filename: String
    let contentType: UTType
}

enum OfflineCacheTransferService {
    private static let videoFileName = "video.m4s"
    private static let audioFileName = "audio.m4s"
    private static let detailFileName = "detail.json"
    private static let manifestFileName = "manifest.json"

    static func exportOptions(for item: OfflineCacheItem) -> [OfflineCacheExportOption] {
        guard item.status == .completed else { return [] }

        do {
            let directoryURL = try OfflineCacheStorage.itemDirectoryURL(
                relativeDirectory: item.relativeDirectory
            )
            let contents = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            var options: [OfflineCacheExportOption] = []

            if contents.contains(where: { $0.lastPathComponent == videoFileName }) {
                options.append(.init(
                    kind: .video,
                    title: "导出视频",
                    subtitle: videoFileName
                ))
            }

            if contents.contains(where: { $0.lastPathComponent == audioFileName }) {
                options.append(.init(
                    kind: .audio,
                    title: "导出音频",
                    subtitle: audioFileName
                ))
            }

            let danmakuFiles = contents.filter {
                $0.lastPathComponent.hasPrefix("danmaku-") && $0.pathExtension == "pb"
            }
            if !danmakuFiles.isEmpty {
                let subtitle = danmakuFiles.count == 1
                    ? danmakuFiles[0].lastPathComponent
                    : "共 \(danmakuFiles.count) 个文件，导出为 zip"
                options.append(.init(
                    kind: .danmaku,
                    title: "导出弹幕数据",
                    subtitle: subtitle
                ))
            }

            if contents.contains(where: { $0.lastPathComponent == manifestFileName }) {
                options.append(.init(
                    kind: .manifest,
                    title: "导出 manifest",
                    subtitle: manifestFileName
                ))
            }

            if contents.contains(where: { $0.lastPathComponent == detailFileName }) {
                options.append(.init(
                    kind: .detail,
                    title: "导出详情数据",
                    subtitle: detailFileName
                ))
            }

            options.append(.init(
                kind: .packageZip,
                title: "导出缓存文件包",
                subtitle: "\(item.relativeDirectory).zip"
            ))

            return options
        } catch {
            return []
        }
    }

    static func prepareExport(
        for item: OfflineCacheItem,
        option: OfflineCacheExportOption.Kind,
        progress: @escaping (Int, Int, Double, String) -> Void = { _, _, _, _ in },
        isCancelled: @escaping () -> Bool = { false }
    ) throws -> OfflineCacheExportFile {
        guard item.status == .completed else {
            throw OfflineCacheTransferError.itemNotCompleted
        }

        let directoryURL = try OfflineCacheStorage.itemDirectoryURL(
            relativeDirectory: item.relativeDirectory
        )

        switch option {
        case .video:
            let url = directoryURL.appendingPathComponent(videoFileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OfflineCacheTransferError.missingFile(videoFileName)
            }
            return .init(url: url, filename: "\(item.relativeDirectory)-video.m4s", contentType: .data)

        case .audio:
            let url = directoryURL.appendingPathComponent(audioFileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OfflineCacheTransferError.missingFile(audioFileName)
            }
            return .init(url: url, filename: "\(item.relativeDirectory)-audio.m4s", contentType: .data)

        case .manifest:
            let url = directoryURL.appendingPathComponent(manifestFileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OfflineCacheTransferError.missingFile(manifestFileName)
            }
            return .init(url: url, filename: "\(item.relativeDirectory)-manifest.json", contentType: .json)

        case .detail:
            let url = directoryURL.appendingPathComponent(detailFileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OfflineCacheTransferError.missingFile(detailFileName)
            }
            return .init(url: url, filename: "\(item.relativeDirectory)-detail.json", contentType: .json)

        case .danmaku:
            let files = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.lastPathComponent.hasPrefix("danmaku-") && $0.pathExtension == "pb" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !files.isEmpty else {
                throw OfflineCacheTransferError.missingFile("danmaku-*.pb")
            }

            if files.count == 1, let file = files.first {
                return .init(
                    url: file,
                    filename: "\(item.relativeDirectory)-\(file.lastPathComponent)",
                    contentType: .data
                )
            }

            let zipURL = temporaryExportURL(filename: "\(item.relativeDirectory)-danmaku.zip")
            try recreateItem(at: zipURL)
            let stagingURL = temporaryDirectoryURL(name: "\(item.relativeDirectory)-danmaku")
            try recreateDirectory(at: stagingURL)
            for file in files {
                let targetURL = stagingURL.appendingPathComponent(file.lastPathComponent)
                try FileManager.default.copyItem(at: file, to: targetURL)
            }
            try zipDirectory(at: stagingURL, to: zipURL)
            return .init(url: zipURL, filename: zipURL.lastPathComponent, contentType: .zip)

        case .packageZip:
            let zipURL = temporaryExportURL(filename: "\(item.relativeDirectory).zip")
            try recreateItem(at: zipURL)
            let snapshotURL = temporaryDirectoryURL(name: "\(item.relativeDirectory)-export")
            try recreateDirectory(at: snapshotURL)
            let snapshotPayloadURL = snapshotURL.appendingPathComponent(item.relativeDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: snapshotPayloadURL, withIntermediateDirectories: true)
            progress(1, 2, 0, "正在准备缓存文件")
            let entries = try FileManager.default.subpathsOfDirectory(atPath: directoryURL.path)
            let fileEntries = entries.filter {
                var isDirectory: ObjCBool = false
                let source = directoryURL.appendingPathComponent($0)
                return FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            }
            let fileWeights = fileEntries.map { relativePath -> Int64 in
                let url = directoryURL.appendingPathComponent(relativePath)
                return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            let totalBytes = max(fileWeights.reduce(0, +), 1)
            var copiedBytes: Int64 = 0
            for (index, relativePath) in fileEntries.enumerated() {
                if isCancelled() { throw OfflineCacheTransferError.cancelled }
                progress(1, 2, Double(copiedBytes) / Double(totalBytes), "正在复制 \\(relativePath)")
                let source = directoryURL.appendingPathComponent(relativePath)
                let destination = snapshotPayloadURL.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: destination)
                copiedBytes += fileWeights[index]
                progress(1, 2, Double(copiedBytes) / Double(totalBytes), "已复制 \\(relativePath)")
            }
            guard FileManager.default.fileExists(atPath: snapshotPayloadURL.appendingPathComponent(detailFileName).path) else {
                throw OfflineCacheTransferError.missingFile(detailFileName)
            }
            guard FileManager.default.fileExists(atPath: snapshotPayloadURL.appendingPathComponent(manifestFileName).path) else {
                throw OfflineCacheTransferError.missingFile(manifestFileName)
            }
            progress(2, 2, 0, "正在压缩缓存文件")
            try zipDirectory(at: snapshotPayloadURL, to: zipURL, fileWeights: fileWeights, progress: { fraction, stage in
                progress(2, 2, fraction, stage.name)
            }, isCancelled: {
                isCancelled()
            })
            return .init(url: zipURL, filename: zipURL.lastPathComponent, contentType: .zip)
        }
    }

    static func importArchive(from sourceURL: URL) throws -> OfflineCacheItem {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let extractionRoot = temporaryDirectoryURL(name: "offline-cache-import")
        try recreateDirectory(at: extractionRoot)
        try unzipArchive(at: sourceURL, to: extractionRoot)

        let payloadDirectory = try locatePayloadDirectory(in: extractionRoot)
        let relativeDirectory = try parseRelativeDirectory(from: payloadDirectory.lastPathComponent)
        let detailURL = payloadDirectory.appendingPathComponent(detailFileName)
        let manifestURL = payloadDirectory.appendingPathComponent(manifestFileName)

        guard FileManager.default.fileExists(atPath: detailURL.path) else {
            throw OfflineCacheTransferError.missingFile(detailFileName)
        }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw OfflineCacheTransferError.missingFile(manifestFileName)
        }

        let detailData = try Data(contentsOf: detailURL)
        let manifestData = try Data(contentsOf: manifestURL)
        let detail = try JSONDecoder().decode(VideoDetailData.self, from: detailData)
        let manifest = try JSONDecoder().decode(OfflineCacheManifest.self, from: manifestData)

        let videoURL = payloadDirectory.appendingPathComponent(manifest.videoFileName)
        let audioURL = payloadDirectory.appendingPathComponent(manifest.audioFileName)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw OfflineCacheTransferError.missingFile(manifest.videoFileName)
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw OfflineCacheTransferError.missingFile(manifest.audioFileName)
        }

        let (_, cid, qualityCode) = try parseDirectoryComponents(from: relativeDirectory)
        let finalDirectoryURL = try OfflineCacheStorage.itemDirectoryURL(relativeDirectory: relativeDirectory)
        if FileManager.default.fileExists(atPath: finalDirectoryURL.path) {
            try FileManager.default.removeItem(at: finalDirectoryURL)
        }
        try FileManager.default.copyItem(at: payloadDirectory, to: finalDirectoryURL)

        let fileSizeBytes = try directorySize(at: finalDirectoryURL)
        return OfflineCacheItem(
            id: UUID(),
            bvid: detail.bvid,
            aid: detail.aid,
            cid: cid,
            title: detail.title,
            cover: detail.pic.replacingOccurrences(of: "http://", with: "https://"),
            uploader: detail.owner.name,
            duration: detail.duration,
            qualityCode: qualityCode,
            qualityLabel: DashStreamSelector.qualityLabel(for: qualityCode),
            videoCodec: manifest.videoCodec,
            audioCodec: manifest.audioCodec,
            totalBytes: fileSizeBytes,
            downloadedBytes: fileSizeBytes,
            fileSizeBytes: fileSizeBytes,
            speedBytesPerSecond: 0,
            status: .completed,
            errorMessage: nil,
            relativeDirectory: relativeDirectory,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private static func locatePayloadDirectory(in rootURL: URL) throws -> URL {
        let fm = FileManager.default
        if hasRequiredFiles(in: rootURL) {
            return rootURL
        }

        let children = try fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for child in children where hasRequiredFiles(in: child) {
            return child
        }
        throw OfflineCacheTransferError.invalidArchive
    }

    private static func hasRequiredFiles(in directoryURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }

        let detailURL = directoryURL.appendingPathComponent(detailFileName)
        let manifestURL = directoryURL.appendingPathComponent(manifestFileName)
        return FileManager.default.fileExists(atPath: detailURL.path)
            && FileManager.default.fileExists(atPath: manifestURL.path)
    }

    private static func parseRelativeDirectory(from name: String) throws -> String {
        _ = try parseDirectoryComponents(from: name)
        return name
    }

    private static func parseDirectoryComponents(from name: String) throws -> (String, Int, Int) {
        let parts = name.split(separator: "_")
        guard parts.count >= 3,
              let cid = Int(parts[parts.count - 2]),
              let qualityCode = Int(parts[parts.count - 1].dropFirst()),
              parts[parts.count - 1].hasPrefix("q")
        else {
            throw OfflineCacheTransferError.unsupportedArchiveLayout
        }
        let bvid = parts.dropLast(2).joined(separator: "_")
        guard !bvid.isEmpty else {
            throw OfflineCacheTransferError.unsupportedArchiveLayout
        }
        return (bvid, cid, qualityCode)
    }

    private static func temporaryExportURL(filename: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename)
    }

    private static func temporaryDirectoryURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func recreateItem(at url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func recreateDirectory(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func directorySize(at url: URL) throws -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private static func zipDirectory(at sourceURL: URL, to destinationURL: URL, fileWeights: [Int64] = [], progress: @escaping (Double, ZipProgressStage) -> Void = { _, _ in }, isCancelled: @escaping () -> Bool = { false }) throws {
        guard let archive = Archive(url: destinationURL, accessMode: .create) else {
            throw OfflineCacheTransferError.invalidArchive
        }

        let baseParentURL = sourceURL.deletingLastPathComponent()
        let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let allEntries = (enumerator?.allObjects as? [URL] ?? []).filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        let weights = allEntries.enumerated().map { index, url -> Int64 in
            if index < fileWeights.count { return fileWeights[index] }
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let totalWeight = max(weights.reduce(0, +), 1)
        var completedWeight: Int64 = 0
        try archive.addEntry(
            with: sourceURL.lastPathComponent,
            relativeTo: baseParentURL,
            compressionMethod: .deflate
        )

        if isCancelled() { throw OfflineCacheTransferError.cancelled }
        for (index, fileURL) in allEntries.enumerated() {
            let relativePath = fileURL.path.replacingOccurrences(
                of: baseParentURL.path + "/",
                with: ""
            )
            if isCancelled() { throw OfflineCacheTransferError.cancelled }
            let stepProgress = Progress()
            let monitorFinished = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                while monitorFinished.wait(timeout: .now()) == .timedOut {
                    if isCancelled() { stepProgress.cancel() }
                    let fraction = stepProgress.totalUnitCount > 0
                        ? Double(stepProgress.completedUnitCount) / Double(stepProgress.totalUnitCount)
                        : 0
                    let weighted = (Double(completedWeight) + Double(weights[index]) * fraction) / Double(totalWeight)
                    progress(weighted, .init(index: index, name: "正在压缩 \(relativePath)"))
                    usleep(50_000)
                }
            }
            do {
                try archive.addEntry(
                    with: relativePath,
                    relativeTo: baseParentURL,
                    compressionMethod: .deflate,
                    progress: stepProgress
                )
            } catch {
                monitorFinished.signal()
                throw error
            }
            monitorFinished.signal()
            completedWeight += weights[index]
            progress(Double(completedWeight) / Double(totalWeight), .init(index: index, name: "已压缩 \(relativePath)"))
        }
    }

    private struct ZipProgressStage {
        let index: Int
        let name: String
    }

    private static func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws {
        guard let archive = Archive(url: sourceURL, accessMode: .read) else {
            throw OfflineCacheTransferError.invalidArchive
        }

        for entry in archive {
            _ = try archive.extract(entry, to: destinationURL.appendingPathComponent(entry.path))
        }
    }
}

@MainActor
final class OfflineCacheManager: ObservableObject {
    static let shared = OfflineCacheManager()

    @Published private(set) var items: [OfflineCacheItem] = []

    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var activeDownloadBridges: [UUID: DownloadTaskBridge] = [:]
    private var resumeStates: [UUID: DownloadResumeState] = [:]
    private var pauseRequestedIDs: Set<UUID> = []

    private init() {
        items = OfflineCacheStorage.loadItems()
        for index in items.indices where items[index].status == .queued || items[index].status == .downloading {
            items[index].status = .failed
            items[index].errorMessage = "任务在上次运行中断。"
            items[index].speedBytesPerSecond = 0
        }
        persistItems()
    }

    var sortedItems: [OfflineCacheItem] {
        items.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func queryVideo(
        bvidOrAid rawIdentifier: String,
        cid rawCID: String
    ) async throws -> OfflineCacheQueryResult {
        let trimmed = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OfflineCacheError.invalidIdentifier
        }

        let resolvedBVID: String
        if trimmed.hasPrefix("BV") {
            resolvedBVID = trimmed
        } else if let aid = Int64(trimmed.replacing("av",with: "")) {
            resolvedBVID = BiliIdConverter.av2bv(aid: aid)
        } else {
            throw OfflineCacheError.invalidIdentifier
        }

        guard !resolvedBVID.isEmpty else {
            throw OfflineCacheError.invalidIdentifier
        }

        let detail = try await BiliAPI.shared.fetchVideoDetail(bvid: resolvedBVID)
        let resolvedCID = Int(rawCID.trimmingCharacters(in: .whitespacesAndNewlines)) ?? detail.cid
        let playURLResponse = try await BiliAPI.shared.fetchPlayUrl(
            bvid: resolvedBVID,
            cid: resolvedCID
        )
        let qualityOptions = DashStreamSelector.qualityOptions(from: playURLResponse)
            .sorted { $0.code > $1.code }
        let defaultQualityCode = qualityOptions.map(\.code).max() ?? playURLResponse.data.quality ?? 64

        return OfflineCacheQueryResult(
            detail: detail,
            resolvedBVID: resolvedBVID,
            resolvedCID: resolvedCID,
            playURLResponse: playURLResponse,
            qualityOptions: qualityOptions,
            defaultQualityCode: defaultQualityCode
        )
    }

    func addTask(
        from queryResult: OfflineCacheQueryResult,
        qualityCode: Int
    ) {
        guard let stream = DashStreamSelector.selectStream(
            from: queryResult.playURLResponse,
            qualityCode: qualityCode,
            preferredCodec: AudioVideoSettingsStore.load().preferredCodec
        ) else {
            return
        }

        if let existingIndex = items.firstIndex(where: {
            $0.bvid == queryResult.resolvedBVID &&
                $0.cid == queryResult.resolvedCID &&
                $0.qualityCode == qualityCode &&
                $0.status != .failed
        }) {
            items[existingIndex].updatedAt = Date()
            persistItems()
            return
        }

        let qualityLabel = DashStreamSelector.qualityLabel(for: qualityCode)
        let relativeDirectory = OfflineCacheStorage.relativeDirectoryName(
            bvid: queryResult.resolvedBVID,
            cid: queryResult.resolvedCID,
            qualityCode: qualityCode
        )

        let item = OfflineCacheItem(
            id: UUID(),
            bvid: queryResult.resolvedBVID,
            aid: queryResult.detail.aid,
            cid: queryResult.resolvedCID,
            title: queryResult.detail.title,
            cover: queryResult.detail.pic.replacingOccurrences(of: "http://", with: "https://"),
            uploader: queryResult.detail.owner.name,
            duration: queryResult.detail.duration,
            qualityCode: qualityCode,
            qualityLabel: qualityLabel,
            videoCodec: stream.videoCodec,
            audioCodec: stream.audioCodec,
            totalBytes: 0,
            downloadedBytes: 0,
            fileSizeBytes: 0,
            speedBytesPerSecond: 0,
            status: .queued,
            errorMessage: nil,
            relativeDirectory: relativeDirectory,
            createdAt: Date(),
            updatedAt: Date()
        )

        items.append(item)
        persistItems()
        startDownload(for: item.id, queryResult: queryResult, stream: stream)
    }

    func deleteItem(id: UUID) {
        deleteItems(ids: [id])
    }

    func stopDownload(id: UUID) {
        pauseRequestedIDs.insert(id)
        if let bridge = activeDownloadBridges[id] {
            bridge.pause()
        } else {
            runningTasks[id]?.cancel()
            runningTasks[id] = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.updateItem(id) { item in
                    item.status = .paused
                    item.errorMessage = "下载已暂停，点击继续下载"
                    item.speedBytesPerSecond = 0
                    item.updatedAt = Date()
                }
            }
        }
    }

    func restartDownload(id: UUID) {
        guard runningTasks[id] == nil,
              let item = items.first(where: { $0.id == id })
        else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let queryResult = try await self.queryVideo(
                    bvidOrAid: item.bvid,
                    cid: String(item.cid)
                )
                guard let stream = DashStreamSelector.selectStream(
                    from: queryResult.playURLResponse,
                    qualityCode: item.qualityCode,
                    preferredCodec: AudioVideoSettingsStore.load().preferredCodec
                ) else {
                    throw APIError.noVideoOrAudio
                }

                let directoryURL = try OfflineCacheStorage.itemDirectoryURL(
                    relativeDirectory: item.relativeDirectory
                )
                if FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.removeItem(at: directoryURL)
                }

                await self.updateItem(id) { current in
                    if current.status == .failed {
                        current.totalBytes = 0
                        current.downloadedBytes = 0
                        current.fileSizeBytes = 0
                    }
                    current.speedBytesPerSecond = 0
                    current.status = .queued
                    current.errorMessage = nil
                    current.updatedAt = Date()
                }

                self.startDownload(
                    for: id,
                    queryResult: queryResult,
                    stream: stream
                )
            } catch {
                ErrorLogService.record(error, context: "创建离线缓存")
                await self.markFailed(itemID: id, message: error.localizedDescription)
            }
        }
    }

    func deleteItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        for id in ids {
            pauseRequestedIDs.remove(id)
            runningTasks[id]?.cancel()
            runningTasks[id] = nil
            activeDownloadBridges[id]?.pause()
            activeDownloadBridges[id] = nil
            resumeStates[id] = nil
        }

        let removedItems = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        persistItems()

        for item in removedItems {
            do {
                let directoryURL = try OfflineCacheStorage.itemDirectoryURL(
                    relativeDirectory: item.relativeDirectory
                )
                if FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.removeItem(at: directoryURL)
                }
            } catch {
                ErrorLogService.record(error, context: "删除离线缓存")
                print("删除离线缓存目录失败: \(error)")
            }
        }
    }

    func importCacheArchive(from url: URL) throws -> OfflineCacheItem {
        let importedItem = try OfflineCacheTransferService.importArchive(from: url)

        if let existingIndex = items.firstIndex(where: {
            $0.bvid == importedItem.bvid &&
            $0.cid == importedItem.cid &&
            $0.qualityCode == importedItem.qualityCode
        }) {
            let existing = items.remove(at: existingIndex)
            if existing.relativeDirectory != importedItem.relativeDirectory {
                do {
                    let oldDirectoryURL = try OfflineCacheStorage.itemDirectoryURL(
                        relativeDirectory: existing.relativeDirectory
                    )
                    if FileManager.default.fileExists(atPath: oldDirectoryURL.path) {
                        try FileManager.default.removeItem(at: oldDirectoryURL)
                    }
                } catch {
                    print("删除旧导入缓存失败: \(error)")
                }
            }
        }

        items.append(importedItem)
        persistItems()
        return importedItem
    }

    private func startDownload(
        for itemID: UUID,
        queryResult: OfflineCacheQueryResult,
        stream: DashStream
    ) {
        guard runningTasks[itemID] == nil else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performDownload(
                    itemID: itemID,
                    queryResult: queryResult,
                    stream: stream
                )
            } catch let error as DownloadControlError {
                switch error {
                case let .paused(stage, resumeData):
                    if let resumeData {
                        self.resumeStates[itemID] = DownloadResumeState(stage: stage, resumeData: resumeData)
                    }
                    await self.updateItem(itemID) { item in
                        item.status = .paused
                        item.errorMessage = "下载已暂停，点击继续下载"
                        item.speedBytesPerSecond = 0
                        item.updatedAt = Date()
                    }
                case let .failed(error, stage, resumeData):
                    if let resumeData {
                        self.resumeStates[itemID] = DownloadResumeState(stage: stage, resumeData: resumeData)
                    }
                    await self.markFailed(itemID: itemID, message: error.localizedDescription)
                }
            } catch {
                ErrorLogService.record(error, context: "下载离线缓存")
                await self.markFailed(itemID: itemID, message: error.localizedDescription)
            }
            await self.clearRunningTask(itemID: itemID)
        }
        runningTasks[itemID] = task
    }

    private func clearRunningTask(itemID: UUID) {
        runningTasks[itemID] = nil
        activeDownloadBridges[itemID] = nil
        pauseRequestedIDs.remove(itemID)
    }

    private func performDownload(
        itemID: UUID,
        queryResult: OfflineCacheQueryResult,
        stream: DashStream
    ) async throws {
        let directoryURL = try OfflineCacheStorage.itemDirectoryURL(
            relativeDirectory: OfflineCacheStorage.relativeDirectoryName(
                bvid: queryResult.resolvedBVID,
                cid: queryResult.resolvedCID,
                qualityCode: stream.qualityCode
            )
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let detailData = try JSONEncoder().encode(queryResult.detail)
        try detailData.write(to: directoryURL.appendingPathComponent("detail.json"), options: .atomic)

        await updateItem(itemID) { item in
            item.status = .downloading
            item.errorMessage = nil
            item.updatedAt = Date()
        }

        let videoTargetURL = directoryURL.appendingPathComponent("video.m4s")
        let audioTargetURL = directoryURL.appendingPathComponent("audio.m4s")
        let segmentCount = max(1, Int(ceil(Double(max(queryResult.detail.duration, 1)) / 360.0)))

        let videoLength: Int64
        if FileManager.default.fileExists(atPath: videoTargetURL.path) {
            let values = try videoTargetURL.resourceValues(forKeys: [.fileSizeKey])
            videoLength = Int64(values.fileSize ?? 0)
        } else {
            videoLength = try await downloadFile(
                from: stream.videoURL,
                to: videoTargetURL,
                itemID: itemID,
                stage: .video
            )
        }

        let audioLength: Int64
        if FileManager.default.fileExists(atPath: audioTargetURL.path) {
            let values = try audioTargetURL.resourceValues(forKeys: [.fileSizeKey])
            audioLength = Int64(values.fileSize ?? 0)
        } else {
            audioLength = try await downloadFile(
                from: stream.audioURL,
                to: audioTargetURL,
                itemID: itemID,
                stage: .audio
            )
        }

        for segmentIndex in 1 ... segmentCount {
            let data = try await BiliAPI.shared.fetchDanmakuSegmentData(
                cid: queryResult.resolvedCID,
                segmentIndex: segmentIndex
            )
            try data.write(
                to: directoryURL.appendingPathComponent("danmaku-\(segmentIndex).pb"),
                options: .atomic
            )
        }

        let manifest = OfflineCacheManifest(
            videoFileName: videoTargetURL.lastPathComponent,
            audioFileName: audioTargetURL.lastPathComponent,
            width: stream.width,
            height: stream.height,
            fps: stream.fps,
            videoBitrate: stream.videoBitrate,
            audioBitrate: stream.audioBitrate,
            videoCodec: stream.videoCodec,
            audioCodec: stream.audioCodec
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(
            to: directoryURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let totalSize = videoLength + audioLength + Int64(manifestData.count)
        await updateItem(itemID) { item in
            item.status = .completed
            item.totalBytes = max(item.totalBytes, totalSize)
            item.downloadedBytes = max(item.downloadedBytes, totalSize)
            item.fileSizeBytes = max(item.downloadedBytes, totalSize)
            item.speedBytesPerSecond = 0
            item.errorMessage = nil
            item.updatedAt = Date()
        }
        resumeStates[itemID] = nil
    }

    private func downloadFile(
        from sourceURL: URL,
        to destinationURL: URL,
        itemID: UUID,
        stage: DownloadStage
    ) async throws -> Int64 {
        final class SpeedState {
            var lastSampleAt = Date()
            var lastSampleBytes: Int64 = 0
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        let request = makeMediaRequest(url: sourceURL)
        let downloadedBase = items.first(where: { $0.id == itemID })?.downloadedBytes ?? 0
        let speedState = SpeedState()
        var pendingResumeData = resumeStates[itemID]?.stage == stage ? resumeStates[itemID]?.resumeData : nil
        var attempts = 0
        let maxRetryCount = 3

        while true {
            let bridge = DownloadTaskBridge()
            activeDownloadBridges[itemID] = bridge

            do {
                let (temporaryURL, response) = try await DownloadFileRunner.run(
                    bridge: bridge,
                    source: pendingResumeData.map(DownloadSource.resumeData) ?? .request(request),
                    progress: { [weak self] completed, total in
                        guard let self else { return }
                        Task { @MainActor in
                            let now = Date()
                            let shouldUpdateSpeed = now.timeIntervalSince(speedState.lastSampleAt) >= 0.5
                                || (total > 0 && completed >= total)
                            let deltaBytes = completed - speedState.lastSampleBytes
                            let deltaTime = max(now.timeIntervalSince(speedState.lastSampleAt), 0.001)
                            let sampledSpeed = Double(max(deltaBytes, 0)) / deltaTime

                            await self.updateItem(itemID) { item in
                                if total > 0 {
                                    item.totalBytes = max(item.totalBytes, total)
                                }
                                item.downloadedBytes = max(item.downloadedBytes, downloadedBase + completed)
                                if shouldUpdateSpeed {
                                    item.speedBytesPerSecond = sampledSpeed
                                }
                                item.updatedAt = Date()
                            }

                            if shouldUpdateSpeed {
                                speedState.lastSampleAt = now
                                speedState.lastSampleBytes = completed
                            }
                        }
                    }
                )
                try Task.checkCancellation()

                let expectedLength = response.expectedContentLength
                if expectedLength > 0 {
                    await updateItem(itemID) { item in
                        item.totalBytes = max(item.totalBytes, downloadedBase + expectedLength)
                    }
                }

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

                let values = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = Int64(values.fileSize ?? 0)

                await updateItem(itemID) { item in
                    item.downloadedBytes = max(item.downloadedBytes, downloadedBase + fileSize)
                    item.fileSizeBytes = max(item.fileSizeBytes, item.downloadedBytes)
                    item.updatedAt = Date()
                }

                if resumeStates[itemID]?.stage == stage {
                    resumeStates[itemID] = nil
                }
                activeDownloadBridges[itemID] = nil
                return fileSize
            } catch let error as DownloadTaskBridgeError {
                activeDownloadBridges[itemID] = nil

                if pauseRequestedIDs.contains(itemID) {
                    throw DownloadControlError.paused(stage: stage, resumeData: error.resumeData)
                }

                if let resumeData = error.resumeData, attempts < maxRetryCount {
                    attempts += 1
                    pendingResumeData = resumeData
                    resumeStates[itemID] = DownloadResumeState(stage: stage, resumeData: resumeData)
                    continue
                }

                if pendingResumeData != nil, attempts < maxRetryCount {
                    attempts += 1
                    pendingResumeData = nil
                    continue
                }

                throw DownloadControlError.failed(
                    error: error.underlying ?? APIError.requestFailed,
                    stage: stage,
                    resumeData: error.resumeData
                )
            }
        }
    }

    private func updateItem(
        _ itemID: UUID,
        mutate: (inout OfflineCacheItem) -> Void
    ) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        mutate(&items[index])
        persistItems()
    }

    private func markFailed(itemID: UUID, message: String) async {
        await updateItem(itemID) { item in
            item.status = .failed
            item.errorMessage = message
            item.speedBytesPerSecond = 0
            item.updatedAt = Date()
        }
    }

    private func persistItems() {
        do {
            try OfflineCacheStorage.saveItems(items)
        } catch {
            ErrorLogService.record(error, context: "保存离线缓存索引")
            print("保存离线缓存索引失败: \(error)")
        }
    }

    private func makeMediaRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(LoginSession.shared.cookieString, forHTTPHeaderField: "Cookie")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 BiliIOS/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }
}

enum OfflineCacheError: LocalizedError {
    case invalidIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            return "请输入有效的 BVID 或 AID。"
        }
    }
}

private enum DownloadFileRunner {
    static func run(
        bridge: DownloadTaskBridge,
        source: DownloadSource,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, URLResponse) {
        bridge.setProgressHandler(progress)
        let session = URLSession(
            configuration: .default,
            delegate: bridge,
            delegateQueue: nil
        )
        defer {
            session.invalidateAndCancel()
        }

        return try await withCheckedThrowingContinuation { continuation in
            bridge.attach(continuation: continuation, session: session)
            let task: URLSessionDownloadTask
            switch source {
            case let .request(request):
                task = session.downloadTask(with: request)
            case let .resumeData(data):
                task = session.downloadTask(withResumeData: data)
            }
            bridge.task = task
            task.resume()
        }
    }
}

private enum DownloadSource {
    case request(URLRequest)
    case resumeData(Data)
}

private enum DownloadStage: String {
    case video
    case audio
}

private struct DownloadResumeState {
    let stage: DownloadStage
    let resumeData: Data
}

private enum DownloadControlError: Error {
    case paused(stage: DownloadStage, resumeData: Data?)
    case failed(error: Error, stage: DownloadStage, resumeData: Data?)
}

private struct DownloadTaskBridgeError: Error {
    let underlying: Error?
    let resumeData: Data?
}

private final class DownloadTaskBridge: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    typealias Continuation = CheckedContinuation<(URL, URLResponse), Error>

    private var progressHandler: (@Sendable (Int64, Int64) -> Void)?
    private var continuation: Continuation?
    private weak var session: URLSession?
    weak var task: URLSessionDownloadTask?

    func setProgressHandler(_ handler: @escaping @Sendable (Int64, Int64) -> Void) {
        self.progressHandler = handler
    }

    func attach(continuation: Continuation, session: URLSession) {
        self.continuation = continuation
        self.session = session
    }

    func pause() {
        task?.cancel(byProducingResumeData: { _ in })
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler?(
            max(totalBytesWritten, 0),
            max(totalBytesExpectedToWrite, 0)
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response else {
            continuation?.resume(throwing: APIError.requestFailed)
            continuation = nil
            return
        }
        let preservedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("download")

        do {
            if FileManager.default.fileExists(atPath: preservedURL.path) {
                try FileManager.default.removeItem(at: preservedURL)
            }
            try FileManager.default.moveItem(at: location, to: preservedURL)
            continuation?.resume(returning: (preservedURL, response))
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        continuation?.resume(throwing: DownloadTaskBridgeError(
            underlying: error,
            resumeData: resumeData
        ))
        continuation = nil
    }
}

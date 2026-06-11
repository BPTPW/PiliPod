import Combine
import Foundation
import SwiftProtobuf

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
                qualityCode: item.qualityCode,
                videoCodec: item.videoCodec,
                audioCodec: item.audioCodec,
                width: manifest.width,
                height: manifest.height,
                fps: manifest.fps,
                videoBitrate: manifest.videoBitrate,
                audioBitrate: manifest.audioBitrate
            )
            return OfflineCachePlayableAsset(item: item, detail: detail, stream: stream)
        } catch {
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
    let fps: Int
    let videoBitrate: Int
    let audioBitrate: Int
    let videoCodec: String
    let audioCodec: String
}

@MainActor
final class OfflineCacheManager: ObservableObject {
    static let shared = OfflineCacheManager()

    @Published private(set) var items: [OfflineCacheItem] = []

    private var runningTasks: [UUID: Task<Void, Never>] = [:]

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
        runningTasks[id]?.cancel()
        runningTasks[id] = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updateItem(id) { item in
                item.status = .failed
                item.errorMessage = "下载已停止，点击重新下载"
                item.speedBytesPerSecond = 0
                item.updatedAt = Date()
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
                    current.totalBytes = 0
                    current.downloadedBytes = 0
                    current.fileSizeBytes = 0
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
                await self.markFailed(itemID: id, message: error.localizedDescription)
            }
        }
    }

    func deleteItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        for id in ids {
            runningTasks[id]?.cancel()
            runningTasks[id] = nil
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
                print("删除离线缓存目录失败: \(error)")
            }
        }
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
            } catch {
                await self.markFailed(itemID: itemID, message: error.localizedDescription)
            }
            await self.clearRunningTask(itemID: itemID)
        }
        runningTasks[itemID] = task
    }

    private func clearRunningTask(itemID: UUID) {
        runningTasks[itemID] = nil
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

        let videoLength = try await downloadFile(
            from: stream.videoURL,
            to: videoTargetURL,
            itemID: itemID
        )
        let audioLength = try await downloadFile(
            from: stream.audioURL,
            to: audioTargetURL,
            itemID: itemID
        )

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
            item.updatedAt = Date()
        }
    }

    private func downloadFile(
        from sourceURL: URL,
        to destinationURL: URL,
        itemID: UUID
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

        let (temporaryURL, response) = try await DownloadFileRunner.run(
            request: request,
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
                item.totalBytes += expectedLength
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

        return fileSize
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
        request: URLRequest,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, URLResponse) {
        let delegate = DownloadTaskBridge(progress: progress)
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        defer {
            session.invalidateAndCancel()
        }

        return try await withCheckedThrowingContinuation { continuation in
            delegate.attach(continuation: continuation, session: session)
            let task = session.downloadTask(with: request)
            delegate.task = task
            task.resume()
        }
    }
}

private final class DownloadTaskBridge: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    typealias Continuation = CheckedContinuation<(URL, URLResponse), Error>

    private let progressHandler: @Sendable (Int64, Int64) -> Void
    private var continuation: Continuation?
    private weak var session: URLSession?
    weak var task: URLSessionDownloadTask?

    init(progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.progressHandler = progress
    }

    func attach(continuation: Continuation, session: URLSession) {
        self.continuation = continuation
        self.session = session
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler(
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
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

import Foundation

struct CacheStorageSummary {
    var urlCacheDiskUsage: Int64
    var urlCacheDiskCapacity: Int64
    var cachesDirectorySize: Int64
    var temporaryDirectorySize: Int64

    static let empty = CacheStorageSummary(
        urlCacheDiskUsage: 0,
        urlCacheDiskCapacity: 0,
        cachesDirectorySize: 0,
        temporaryDirectorySize: 0
    )

    var totalCacheSize: Int64 {
        cachesDirectorySize + temporaryDirectorySize
    }
}

enum CacheStorageService {
    private static let sharedURLCacheMemoryCapacity = 32 * 1_024 * 1_024
    private static let sharedURLCacheDiskCapacity = 160 * 1_024 * 1_024
    private static let sharedURLCacheDiskPath = "PiliPodURLCache"

    static func configureSharedURLCacheIfNeeded() {
        let current = URLCache.shared
        if current.memoryCapacity == sharedURLCacheMemoryCapacity,
           current.diskCapacity == sharedURLCacheDiskCapacity {
            return
        }

        URLCache.shared = URLCache(
            memoryCapacity: sharedURLCacheMemoryCapacity,
            diskCapacity: sharedURLCacheDiskCapacity,
            diskPath: sharedURLCacheDiskPath
        )
    }

    static func loadSummary() -> CacheStorageSummary {
        let fileManager = FileManager.default
        let urlCache = URLCache.shared

        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let temporaryDirectory = fileManager.temporaryDirectory

        return CacheStorageSummary(
            urlCacheDiskUsage: Int64(urlCache.currentDiskUsage),
            urlCacheDiskCapacity: Int64(urlCache.diskCapacity),
            cachesDirectorySize: directorySize(at: cachesDirectory),
            temporaryDirectorySize: directorySize(at: temporaryDirectory)
        )
    }

    static func clearCaches() throws {
        URLCache.shared.removeAllCachedResponses()
        try clearDirectoryContents(at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        try clearDirectoryContents(at: FileManager.default.temporaryDirectory)
    }

    static func formattedSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(size, 0))
    }

    private static func directorySize(at url: URL?) -> Int64 {
        guard let url else { return 0 }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                  values.isRegularFile == true
            else {
                continue
            }

            let fileSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += Int64(fileSize)
        }
        return total
    }

    private static func clearDirectoryContents(at url: URL?) throws {
        guard let url else { return }

        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for itemURL in contents {
            try fileManager.removeItem(at: itemURL)
        }
    }

}

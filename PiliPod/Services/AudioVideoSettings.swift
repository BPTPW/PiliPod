import Foundation
import Network

enum PreferredVideoQuality: Int, CaseIterable, Codable, Hashable {
    case ultraHD8K = 127
    case dolbyVision = 126
    case hdrVivid = 129
    case ultraHD4K = 120
    case fullHD60 = 116
    case fullHDPlus = 112
    case fullHD = 80
    case hd720 = 64
    case sd480 = 32
    case sd360 = 16
    case sd240 = 6

    var title: String {
        switch self {
        case .ultraHD8K: "8K超高清"
        case .dolbyVision: "杜比视界"
        case .hdrVivid: "HDR真彩"
        case .ultraHD4K: "4K"
        case .fullHD60: "1080P 60帧"
        case .fullHDPlus: "1080P+"
        case .fullHD: "1080P"
        case .hd720: "720P"
        case .sd480: "480P"
        case .sd360: "360P"
        case .sd240: "240P"
        }
    }
}

enum VideoBufferSizeOption: String, CaseIterable, Codable, Hashable {
    case auto
    case mb64
    case mb32
    case mb16
    case mb8
    case mb4
    case mb2
    case mb1

    var title: String {
        switch self {
        case .auto: "自动"
        case .mb64: "64MB"
        case .mb32: "32MB"
        case .mb16: "16MB"
        case .mb8: "8MB"
        case .mb4: "4MB"
        case .mb2: "2MB"
        case .mb1: "1MB"
        }
    }

    var mpvByteString: String? {
        switch self {
        case .auto: nil
        case .mb64: "64MiB"
        case .mb32: "32MiB"
        case .mb16: "16MiB"
        case .mb8: "8MiB"
        case .mb4: "4MiB"
        case .mb2: "2MiB"
        case .mb1: "1MiB"
        }
    }
}

enum PreferredCodecOption: String, CaseIterable, Codable, Hashable {
    case hevc
    case avc
    case av1

    var title: String {
        switch self {
        case .hevc: "HEVC"
        case .avc: "AVC"
        case .av1: "AV1"
        }
    }
}

enum MPVVideoSyncOption: String, CaseIterable, Codable, Hashable {
    case audio
    case displayResample = "display-resample"
    case displayTempo = "display-tempo"
    case displayTempoOSD = "display-tempo-osd"

    var title: String {
        switch self {
        case .audio: "audio"
        case .displayResample: "display-resample"
        case .displayTempo: "display-tempo"
        case .displayTempoOSD: "display-tempo-osd"
        }
    }
}

struct AudioVideoSettings: Codable, Equatable {
    var hardwareDecodingEnabled = true
    var defaultQuality: PreferredVideoQuality = .ultraHD4K
    var cellularDefaultQuality: PreferredVideoQuality = .ultraHD4K
    var bufferSize: VideoBufferSizeOption = .auto
    var preferredCodec: PreferredCodecOption = .hevc
    var autosync: Int = 0
    var videoSync: MPVVideoSyncOption = .audio

    func clamped() -> AudioVideoSettings {
        var settings = self
        settings.autosync = min(max(settings.autosync, 0), 10000)
        return settings
    }
}

enum AudioVideoSettingsStore {
    private static let key = "pili.settings.audio-video.v1"

    static func load() -> AudioVideoSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AudioVideoSettings.self, from: data)
        else {
            return AudioVideoSettings().clamped()
        }
        return decoded.clamped()
    }

    static func save(_ settings: AudioVideoSettings) {
        let clamped = settings.clamped()
        guard let data = try? JSONEncoder().encode(clamped) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

final class NetworkTypeMonitor {
    static let shared = NetworkTypeMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "pili.network.monitor")

    private(set) var isCellularConnection = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isCellularConnection = path.usesInterfaceType(.cellular)
        }
        monitor.start(queue: queue)
    }
}

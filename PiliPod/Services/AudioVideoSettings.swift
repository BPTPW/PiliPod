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
        case .ultraHD8K: "8K"
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

enum PreferredLiveQuality: Int, CaseIterable, Codable, Hashable {
    case dolby = 30000
    case ultraHD4K = 20000
    case ultraHD2K = 15000
    case original = 10000
    case blueRay = 400
    case ultraClear = 250
    case hd = 150
    case smooth = 80

    var title: String {
        switch self {
        case .dolby: "杜比"
        case .ultraHD4K: "4K"
        case .ultraHD2K: "2K"
        case .original: "原画"
        case .blueRay: "蓝光"
        case .ultraClear: "超清"
        case .hd: "高清"
        case .smooth: "流畅"
        }
    }
}

enum VideoBufferSizeOption: String, CaseIterable, Codable, Hashable {
    case auto
    case huge
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
        case .huge: "超大"
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
        case .huge: "2048MiB"
        case .mb64: "64MiB"
        case .mb32: "32MiB"
        case .mb16: "16MiB"
        case .mb8: "8MiB"
        case .mb4: "4MiB"
        case .mb2: "2MiB"
        case .mb1: "1MiB"
        }
    }

    var avPlayerTitle: String {
        switch self {
        case .auto: "自动"
        case .mb1: "2s"
        case .mb2: "5s"
        case .mb4: "10s"
        case .mb8: "20s"
        case .mb16: "30s"
        case .mb32: "60s"
        case .mb64: "120s"
        case .huge: "超大"
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

enum PlayerCore: String, CaseIterable, Codable, Hashable {
    case mpvKit
    case avPlayer

    var title: String {
        switch self {
        case .mpvKit: "MPVKit"
        case .avPlayer: "AVPlayer (实验性)"
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

enum HDRToneMappingOption: String, CaseIterable, Codable, Hashable {
    case auto
    case bt2390 = "bt.2390"
    case bt2446a = "bt.2446a"
    case spline
    case reinhard
    case mobius
    case hable
    case clip

    var title: String {
        switch self {
        case .auto: "自动"
        case .bt2390: "BT.2390"
        case .bt2446a: "BT.2446-A"
        case .spline: "Spline"
        case .reinhard: "Reinhard"
        case .mobius: "Mobius"
        case .hable: "Hable"
        case .clip: "Clip"
        }
    }
}

struct AudioVideoSettings: Codable, Equatable {
    var playerCore: PlayerCore = .mpvKit
    var hardwareDecodingEnabled = true
    var allowsBackgroundPlayback = false
    var allowsLiveBackgroundPlayback = false
    var defaultQuality: PreferredVideoQuality = .ultraHD4K
    var cellularDefaultQuality: PreferredVideoQuality = .ultraHD4K
    var liveDefaultQuality: PreferredLiveQuality = .original
    var cellularLiveDefaultQuality: PreferredLiveQuality = .blueRay
    var bufferSize: VideoBufferSizeOption = .mb8
    var preferredCodec: PreferredCodecOption = .hevc
    var autosync: Int = 0
    var videoSync: MPVVideoSyncOption = .audio
    var highDynamicRangeEnabled = true
    var prefersEDROutput = true
    var hdrToneMapping: HDRToneMappingOption = .auto

    private enum CodingKeys: String, CodingKey {
        case hardwareDecodingEnabled
        case playerCore
        case allowsBackgroundPlayback
        case allowsLiveBackgroundPlayback
        case defaultQuality
        case cellularDefaultQuality
        case liveDefaultQuality
        case cellularLiveDefaultQuality
        case bufferSize
        case preferredCodec
        case autosync
        case videoSync
        case highDynamicRangeEnabled
        case prefersEDROutput
        case hdrToneMapping
    }

    func clamped() -> AudioVideoSettings {
        var settings = self
        settings.autosync = min(max(settings.autosync, 0), 10000)
        if settings.highDynamicRangeEnabled {
            settings.prefersEDROutput = true
            if settings.hdrToneMapping == .clip {
                settings.hdrToneMapping = .auto
            }
        }
        return settings
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hardwareDecodingEnabled = try container.decodeIfPresent(Bool.self, forKey: .hardwareDecodingEnabled) ?? true
        playerCore = try container.decodeIfPresent(PlayerCore.self, forKey: .playerCore) ?? .mpvKit
        allowsBackgroundPlayback = try container.decodeIfPresent(Bool.self, forKey: .allowsBackgroundPlayback) ?? false
        allowsLiveBackgroundPlayback = try container.decodeIfPresent(Bool.self, forKey: .allowsLiveBackgroundPlayback) ?? false
        defaultQuality = try container.decodeIfPresent(PreferredVideoQuality.self, forKey: .defaultQuality) ?? .ultraHD4K
        cellularDefaultQuality = try container.decodeIfPresent(PreferredVideoQuality.self, forKey: .cellularDefaultQuality) ?? .ultraHD4K
        liveDefaultQuality = try container.decodeIfPresent(PreferredLiveQuality.self, forKey: .liveDefaultQuality) ?? .original
        cellularLiveDefaultQuality = try container.decodeIfPresent(PreferredLiveQuality.self, forKey: .cellularLiveDefaultQuality) ?? .blueRay
        bufferSize = try container.decodeIfPresent(VideoBufferSizeOption.self, forKey: .bufferSize) ?? .mb8
        preferredCodec = try container.decodeIfPresent(PreferredCodecOption.self, forKey: .preferredCodec) ?? .hevc
        autosync = try container.decodeIfPresent(Int.self, forKey: .autosync) ?? 0
        videoSync = try container.decodeIfPresent(MPVVideoSyncOption.self, forKey: .videoSync) ?? .audio
        highDynamicRangeEnabled = try container.decodeIfPresent(Bool.self, forKey: .highDynamicRangeEnabled) ?? true
        prefersEDROutput = try container.decodeIfPresent(Bool.self, forKey: .prefersEDROutput) ?? true
        hdrToneMapping = try container.decodeIfPresent(HDRToneMappingOption.self, forKey: .hdrToneMapping) ?? .auto
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

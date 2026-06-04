//
//  DashStream.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import Foundation

// MARK: - DASH 流信息

struct DashStream {
    let videoURL: URL
    let audioURL: URL
    let qualityCode: Int
    let videoCodec: String
    let audioCodec: String
    let width: Int
    let height: Int
    let fps: Int
    let videoBitrate: Int
    let audioBitrate: Int

    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }
}

struct VideoQualityOption: Identifiable, Equatable {
    let id: Int
    let code: Int
    let label: String
}

// MARK: - 流选择器

class DashStreamSelector {
    enum CodecPriority: Int {
        case hevc = 0 // hev1 / hvc1
        case avc = 1 // avc1
        case av1 = 2 // av01
        case unknown = 999
    }

    // MARK: - 获取编码格式优先级

    static func getCodecPriority(_ codecString: String) -> CodecPriority {
        if codecString.contains("hev1") || codecString.contains("hvc1") {
            return .hevc
        } else if codecString.contains("avc1") {
            return .avc
        } else if codecString.contains("av01") {
            return .av1
        }
        return .unknown
    }

    // MARK: - 选择最优视频流（HEVC 优先 + 最高画质）

    static func selectBestVideoStream(from videos: [DASHVideo]) -> DASHVideo? {
        // 按优先级排序
        let sorted = videos.sorted { video1, video2 in
            let priority1 = getCodecPriority(video1.codecs)
            let priority2 = getCodecPriority(video2.codecs)

            if priority1.rawValue != priority2.rawValue {
                return priority1.rawValue < priority2.rawValue
            }

            // 同编码格式下，按码率降序（更高质量）
            return video1.bandwidth > video2.bandwidth
        }

        return sorted.first
    }

    static func qualityLabel(for code: Int) -> String {
        switch code {
        case 6: return "240P"
        case 16: return "360P"
        case 32: return "480P"
        case 64: return "720P"
        case 80: return "1080P"
        case 100: return "智能修复"
        case 112: return "1080P+"
        case 116: return "1080P60"
        case 120: return "4K"
        case 125: return "HDR"
        case 126: return "杜比视界"
        case 127: return "8K超高清"
        case 129: return "HDR真彩"
        default: return "\(code)P"
        }
    }

    static func resolvePreferredQualityCode(
        from availableCodes: [Int],
        preferred: PreferredVideoQuality
    ) -> Int? {
        let order = PreferredVideoQuality.allCases.map(\.rawValue)
        let available = Set(availableCodes)

        guard let preferredIndex = order.firstIndex(of: preferred.rawValue) else {
            return availableCodes.max()
        }

        for code in order[preferredIndex...] where available.contains(code) {
            return code
        }

        for code in order[..<preferredIndex].reversed() where available.contains(code) {
            return code
        }

        return availableCodes.max()
    }

    private static func codecPriorityOrder(for preferred: PreferredCodecOption) -> [CodecPriority] {
        switch preferred {
        case .hevc:
            return [.hevc, .avc, .av1, .unknown]
        case .avc:
            return [.avc, .hevc, .av1, .unknown]
        case .av1:
            return [.av1, .hevc, .avc, .unknown]
        }
    }

    static func qualityOptions(from data: PlayUrlResponse) -> [VideoQualityOption] {
        let codes = data.data.acceptQuality
        let descriptions = data.data.acceptDescription
        return codes.enumerated().map { _, code in
            // let label = index < descriptions.count ? descriptions[index] : qualityLabel(for: code)
            let label = qualityLabel(for: code)
            return VideoQualityOption(id: code, code: code, label: label)
        }
    }

    static func selectVideoStream(
        from videos: [DASHVideo],
        qualityCode: Int,
        preferredCodec: PreferredCodecOption
    ) -> DASHVideo? {
        let filtered = videos.filter { $0.id == qualityCode }
        guard !filtered.isEmpty else { return nil }
        let codecOrder = codecPriorityOrder(for: preferredCodec)
        let sorted = filtered.sorted { video1, video2 in
            let priority1 = getCodecPriority(video1.codecs)
            let priority2 = getCodecPriority(video2.codecs)
            let order1 = codecOrder.firstIndex(of: priority1) ?? Int.max
            let order2 = codecOrder.firstIndex(of: priority2) ?? Int.max
            if order1 != order2 {
                return order1 < order2
            }
            return video1.bandwidth > video2.bandwidth
        }
        return sorted.first
    }

    // MARK: - 选择最优音频流（最高码率）

    static func selectBestAudioStream(from audios: [DASHAudio]) -> DASHAudio? {
        return audios.max { $0.bandwidth < $1.bandwidth }
    }

    // MARK: - 组合最优 DASH 流

    static func selectOptimalStream(from data: PlayUrlResponse) -> DashStream? {
        guard let video = selectBestVideoStream(from: data.data.dash.video),
              let audio = selectBestAudioStream(from: data.data.dash.audio),
              let videoURL = URL(string: video.baseUrl),
              let audioURL = URL(string: audio.baseUrl)
        else {
            return nil
        }

        let frameRateParts = video.frameRate.split(separator: "/")
        let fps = frameRateParts.count == 2 ?
            Int(frameRateParts[0]) ?? 30 : Int(video.frameRate) ?? 30

        return DashStream(
            videoURL: videoURL,
            audioURL: audioURL,
            qualityCode: video.id,
            videoCodec: video.codecs,
            audioCodec: audio.codecs,
            width: video.width,
            height: video.height,
            fps: fps,
            videoBitrate: video.bandwidth,
            audioBitrate: audio.bandwidth
        )
    }

    static func selectStream(
        from data: PlayUrlResponse,
        qualityCode: Int,
        preferredCodec: PreferredCodecOption = .hevc
    ) -> DashStream? {
        guard let video = selectVideoStream(
            from: data.data.dash.video,
            qualityCode: qualityCode,
            preferredCodec: preferredCodec
        ),
              let audio = selectBestAudioStream(from: data.data.dash.audio),
              let videoURL = URL(string: video.baseUrl),
              let audioURL = URL(string: audio.baseUrl)
        else {
            return nil
        }

        let frameRateParts = video.frameRate.split(separator: "/")
        let fps = frameRateParts.count == 2 ?
            Int(frameRateParts[0]) ?? 30 : Int(video.frameRate) ?? 30

        return DashStream(
            videoURL: videoURL,
            audioURL: audioURL,
            qualityCode: video.id,
            videoCodec: video.codecs,
            audioCodec: audio.codecs,
            width: video.width,
            height: video.height,
            fps: fps,
            videoBitrate: video.bandwidth,
            audioBitrate: audio.bandwidth
        )
    }
}

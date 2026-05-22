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

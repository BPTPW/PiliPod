//
//  VideoItem.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

struct VideoItem: Identifiable, Hashable {
    var id: String { bvid }
    let bvid: String
    let cid: Int?
    let cover: String
    let title: String
    let playCount: String
    let danmakuCount: String
    let uploader: String
    let duration: Int

    var durationFormatted: String {
        let h = duration / 3600
        let m = (duration % 3600) / 60
        let s = duration % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

extension VideoItem {
    init(from video: RecommendVideo) {
        self.bvid = video.bvid

        self.cid = nil

        self.cover = video.pic.replacingOccurrences(
            of: "http://",
            with: "https://"
        )

        self.title = video.title

        self.playCount = Self.formatCount(video.stat.view)

        self.danmakuCount = Self.formatCount(video.stat.danmaku)

        self.uploader = video.owner.name

        self.duration = video.duration
    }

    static func formatCount(_ count: Int) -> String {
        if count >= 10000 {
            return String(
                format: "%.1f万",
                Double(count) / 10000
            )
        }

        return "\(count)"
    }
}

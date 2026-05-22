//
//  VideoItem.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

struct VideoItem: Identifiable {
    let id = UUID()
    let bvid: String
    let cid: Int?
    let cover: String
    let title: String
    let playCount: String
    let danmakuCount: String
    let uploader: String
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

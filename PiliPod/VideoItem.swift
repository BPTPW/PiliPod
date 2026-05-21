//
//  VideoItem.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

struct VideoItem: Identifiable {
    let id = UUID()

    let cover: String
    let title: String
    let playCount: String
    let danmakuCount: String
    let uploader: String
}

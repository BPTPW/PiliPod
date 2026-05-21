//
//  VideoSection.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

struct VideoSection: Identifiable {
    let id = UUID()
    let title: String?
    var videos: [VideoItem]
}

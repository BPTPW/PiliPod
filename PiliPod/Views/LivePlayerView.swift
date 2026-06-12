//
//  LivePlayerView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/8.
//

import SwiftUI

struct LivePlayerView: View {
    let roomId: String
    let streamURL: URL?
    let aspectRatio: CGFloat
    let statusText: String
    let player: MPVKitPlayer

    var body: some View {
        Group {
            if let streamURL {
                MPVKitPlayerView(player: player)
                    .task(id: streamURL.absoluteString) {
                        player.play(videoURL: streamURL)
                    }
            } else {
                ZStack {
                    Color.black
                    VStack(spacing: 8) {
                        Text(statusText)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color.black)
    }
}

#Preview {
    LivePlayerView(
        roomId: "226000",
        streamURL: nil,
        aspectRatio: 16.0 / 9.0,
        statusText: "room id: 226000",
        player: MPVKitPlayer()
    )
}

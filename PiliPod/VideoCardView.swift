//
//  VideoCardView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct VideoCardView: View {
    let video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面
            AsyncImage(url: URL(string: video.cover)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // 标题
            Text(video.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // 播放量 + 弹幕
            HStack(spacing: 10) {
                Label(video.playCount, systemImage: "play.fill")
                Label(video.danmakuCount, systemImage: "text.bubble.fill")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            // UP主
            Text(video.uploader)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VideoCardView(
        video: VideoItem(
            bvid:"BV1234567890",
            cover: "https://picsum.photos/400/250",
            title: "测试视频标题",
            playCount: "12万",
            danmakuCount: "345",
            uploader: "测试UP主"
        )
    )
    .padding()
}

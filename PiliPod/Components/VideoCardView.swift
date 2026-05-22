//
//  VideoCardView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct VideoCardView: View {
    let video: VideoItem
    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented = true }) {
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
                .overlay(alignment: .bottomTrailing) {
                    Text(video.durationFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.65))
                        )
                        .padding(4)
                }

                // 标题
                Text(video.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2 ... 2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

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
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $isPresented) {
            VideoDetailPage(video: video, isPresented: $isPresented)
        }
    }
}

#Preview {
    VideoCardView(
        video: VideoItem(
            bvid: "BV1234567890",
            cid: nil,
            cover: "https://picsum.photos/400/250",
            title: "测试视频标题",
            playCount: "12万",
            danmakuCount: "345",
            uploader: "测试UP主",
            duration: 325
        )
    )
    .padding()
}

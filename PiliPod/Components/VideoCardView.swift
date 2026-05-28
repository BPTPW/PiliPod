//
//  VideoCardView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct VideoCardView: View {
    let video: VideoItem
    let namespace: Namespace.ID
    let thumbnailWidth: CGFloat
    let onTap: () -> Void

    private var heroID: String { "videoHero.\(video.bvid)" }
    private let cornerRadius: CGFloat = 18
    private var thumbnailHeight: CGFloat { thumbnailWidth * 10 / 16 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 封面（用于卡片→详情页的 Hero 动画）
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.cover)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: thumbnailWidth, height: thumbnailHeight)
                    .clipped()

                    Text(video.durationFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .glassEffect(
                            .regular,
                            in: .capsule
                        )
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .heroTransitionSource(id: heroID, in: namespace)

                VStack(alignment: .leading, spacing: 8) {
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

                    HStack(alignment: .center, spacing: 5) {
                        // 推荐理由 （有返回时显示）
                        if let reason = video.bottomRcmdReasonText, !reason.isEmpty {
                            Text(reason)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                                .glassEffect(
                                    .regular.tint(Color("BiliPink")),
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                        }

                        // UP主
                        Text(video.uploader)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    }
                }
                .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
            )
            // iOS26-ish：更柔和的环境阴影 + 更集中的投影
            .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .frame(width: thumbnailWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var ns

        var body: some View {
            VideoCardView(
                video: VideoItem(
                    bvid: "BV1234567890",
                    cid: nil,
                    cover: "https://i2.hdslb.com/bfs/archive/e8eaf7459a5d008e9142e75b5798798f10dfbc16.jpg@672w_378h_1c.webp",
                    title: "测试视频标题",
                    playCount: "12万",
                    danmakuCount: "345",
                    uploader: "测试UP主",
                    duration: 325,
                    publishTimeText: "2026-05-25",
                    bottomRcmdReasonText: "已关注"
                ),
                namespace: ns,
                thumbnailWidth: 180,
                onTap: {}
            )
            .padding()
        }
    }

    return PreviewWrapper()
}

private extension View {
    @ViewBuilder
    func heroTransitionSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

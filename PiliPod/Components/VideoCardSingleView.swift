//
//  VideoCardSingleView.swift
//  PiliPod
//
//  Created by co on 2026/5/25.
//

import SwiftUI

struct VideoCardSingleView: View {
    let video: VideoItem
    let namespace: Namespace.ID
    let onTap: () -> Void

    private var heroID: String { "videoHero.\(video.bvid)" }
    private let cornerRadius: CGFloat = 18
    private var shouldShowStats: Bool {
        !(video.playCount == "--" && video.danmakuCount == "--")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // 左侧封面（用于卡片→详情页的 Hero 动画）
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.cover)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: 140, height: 88)
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .heroTransitionSource(id: heroID, in: namespace)

                VStack(alignment: .leading, spacing: 8) {
                    // 右侧顶部：标题（允许多行）
                    Text(video.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    // 右侧底部：从下往上 = 播放弹幕 / 发布时间 UP主
                    VStack(alignment: .leading, spacing: 4) {
                        if shouldShowStats {
                            HStack(spacing: video.uploader == "" ? 0 : 10) {
                                Text(video.uploader)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

                                Text(video.publishTimeText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if !video.uploader.isEmpty {
                                Text(video.uploader)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if shouldShowStats {
                            HStack(spacing: 10) {
                                Label(video.playCount, systemImage: "play.fill")
                                Label(video.danmakuCount, systemImage: "text.bubble.fill")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        } else {
                            Text(video.publishTimeText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(10)
            .frame(height: 108)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
            )
            .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var ns

        var body: some View {
            VideoCardSingleView(
                video: VideoItem(
                    bvid: "BV1234567890",
                    cid: nil,
                    cover: "https://i2.hdslb.com/bfs/archive/e8eaf7459a5d008e9142e75b5798798f10dfbc16.jpg@672w_378h_1c.webp",
                    title: "测试视频标题测试视频标题测试视频标题测试视频标题",
                    playCount: "12万",
                    danmakuCount: "345",
                    uploader: "测试UP主",
                    duration: 325,
                    publishTimeText: "2026-05-25",
                    bottomRcmdReasonText: nil
                ),
                namespace: ns,
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

//
//  VideoCardSingleView.swift
//  PiliPod
//
//  Created by co on 2026/5/25.
//

import SwiftUI

struct VideoCardSingleView: View {
    let video: VideoItem
    let progress: Int?
    let namespace: Namespace.ID
    let onTap: () -> Void

    @State private var sponsorLabel: SponsorBlockVideoLabel?

    private var heroID: String { "videoHero.\(video.bvid)" }
    private let cornerRadius: CGFloat = 18
    private var shouldShowStats: Bool {
        !(video.playCount == "--" && video.danmakuCount == "--")
    }
    private var progressRatio: CGFloat {
        guard let progress, video.duration > 0 else { return 0 }
        return min(max(CGFloat(progress) / CGFloat(video.duration), 0), 1)
    }
    private var durationBadgeText: String {
        guard let progress else { return video.durationFormatted }
        return "\(Self.formatDuration(progress))/\(video.durationFormatted)"
    }

    init(video: VideoItem, progress: Int? = nil, namespace: Namespace.ID, onTap: @escaping () -> Void) {
        self.video = video
        self.progress = progress
        self.namespace = namespace
        self.onTap = onTap
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

                    Text(durationBadgeText)
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
                .overlay(alignment: .topLeading) {
                    if let sponsorLabel,
                       let tint = sponsorBlockTintColor(for: sponsorLabel.category)
                    {
                        Image("SponsorBlockerStart")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .glassEffect(
                                .regular.tint(tint),
                                in: .circle
                            )
                            .padding(6)
                    }
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
            .overlay(alignment: .bottomLeading) {
                if progress != nil {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color("BiliPink"))
                            .frame(width: proxy.size.width * progressRatio, height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .task(id: video.bvid) {
            sponsorLabel = await SponsorBlockAPI.fetchPrimaryVideoLabelIfAvailable(videoID: video.bvid)
        }
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
                    progressSeconds: 120,
                    publishTimeText: "2026-05-25",
                    bottomRcmdReasonText: nil
                ),
                progress: 120,
                namespace: ns,
                onTap: {}
            )
            .padding()
        }
    }

    return PreviewWrapper()
}

private extension VideoCardSingleView {
    static func formatDuration(_ seconds: Int) -> String {
        let sanitized = max(seconds, 0)
        let h = sanitized / 3600
        let m = (sanitized % 3600) / 60
        let s = sanitized % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
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

private func sponsorBlockTintColor(for category: String) -> Color? {
    SponsorBlockCategory(rawValue: category)?.color
}

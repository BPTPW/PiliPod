//
//  UserLargeCardView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/4.
//

import SwiftUI

struct UserLargeCardView: View {
    let user: SearchUserLargeCardUser
    let videos: [SearchUserLargeCardVideo]
    var onUserTap: () -> Void = {}
    var onVideoTap: (SearchUserLargeCardVideo) -> Void = { _ in }

    private let cardCornerRadius: CGFloat = 22
    private let videoCornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onUserTap) {
                    HStack(alignment: .center, spacing: 12) {
                        avatarView

                        VStack(alignment: .leading, spacing: 6) {
                            Text(user.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(formatCount(user.followerCount))粉丝 · \(formatCount(user.videoCount))视频")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let mid = userMid {
                    UserFollowButton(mid: mid)
                }
            }

            GeometryReader { proxy in
                let totalSpacing: CGFloat = 16
                let itemWidth = (proxy.size.width - totalSpacing) / 3

                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(videos.prefix(3))) { video in
                        videoCard(video, width: itemWidth)
                    }
                }
            }
            .frame(height: 130)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        )
        .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private var userMid: Int? {
        Int(user.id)
    }

    private var avatarView: some View {
        Group {
            if let avatarURL = normalizedHTTPSURL(from: user.avatarURL) {
                CachedAsyncImage(url: avatarURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private func videoCard(_ video: SearchUserLargeCardVideo, width: CGFloat) -> some View {
        Button {
            onVideoTap(video)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CachedAsyncImage(url: normalizedHTTPSURL(from: video.coverURL)) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: videoCornerRadius, style: .continuous)
                            .fill(Color(.systemGray5))
                    }
                }
                .frame(width: width, height: width * 10 / 16)
                .clipShape(RoundedRectangle(cornerRadius: videoCornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2 ... 2)
                        .multilineTextAlignment(.leading)

                    Text(video.publishTimeText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func normalizedHTTPSURL(from urlString: String) -> URL? {
        let normalizedString: String
        if urlString.hasPrefix("http://") {
            normalizedString = "https://" + urlString.dropFirst("http://".count)
        } else {
            normalizedString = urlString
        }
        return URL(string: normalizedString)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000)
        }
        return "\(count)"
    }
}

struct SearchUserLargeCardUser: Identifiable, Hashable {
    let id: String
    let name: String
    let avatarURL: String
    let followerCount: Int
    let videoCount: Int
}

struct SearchUserLargeCardVideo: Identifiable, Hashable {
    let id: String
    let coverURL: String
    let title: String
    let publishTimeText: String
}

#Preview {
    ScrollView {
        UserLargeCardView(
            user: SearchUserLargeCardUser(
                id: "user-1",
                name: "影视飓风",
                avatarURL: "https://i2.hdslb.com/bfs/face/member/noface.jpg",
                followerCount: 8_214_500,
                videoCount: 327
            ),
            videos: [
                SearchUserLargeCardVideo(
                    id: "video-1",
                    coverURL: "https://i2.hdslb.com/bfs/archive/e8eaf7459a5d008e9142e75b5798798f10dfbc16.jpg@672w_378h_1c.webp",
                    title: "我们测试了新相机的极限画质，它到底值不值得买？",
                    publishTimeText: "2026-06-01"
                ),
                SearchUserLargeCardVideo(
                    id: "video-2",
                    coverURL: "https://i2.hdslb.com/bfs/archive/e8eaf7459a5d008e9142e75b5798798f10dfbc16.jpg@672w_378h_1c.webp",
                    title: "用一周时间重拍经典镜头，看看电影感到底从哪里来",
                    publishTimeText: "2026-05-27"
                ),
                SearchUserLargeCardVideo(
                    id: "video-3",
                    coverURL: "https://i2.hdslb.com/bfs/archive/e8eaf7459a5d008e9142e75b5798798f10dfbc16.jpg@672w_378h_1c.webp",
                    title: "一次讲清楚 4K、6K 和 8K 在真实拍摄里的区别",
                    publishTimeText: "2026-05-19"
                )
            ]
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

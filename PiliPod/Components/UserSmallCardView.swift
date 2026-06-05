//
//  UserSmallCardView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/4.
//

import SwiftUI

struct UserSmallCardView: View {
    let user: SearchUserLargeCardUser
    var onTap: () -> Void = {}

    private let cardCornerRadius: CGFloat = 22

    var body: some View {
        Button(action: onTap) {
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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

    private var avatarView: some View {
        Group {
            if let avatarURL = normalizedHTTPSURL(from: user.avatarURL) {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
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

#Preview {
    ScrollView {
        UserSmallCardView(
            user: SearchUserLargeCardUser(
                id: "user-1",
                name: "影视飓风",
                avatarURL: "https://i2.hdslb.com/bfs/face/member/noface.jpg",
                followerCount: 8214500,
                videoCount: 327
            )
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

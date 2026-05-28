//
//  CommentCardView.swift
//  PiliPod
//
//  Created by co on 2026/5/28.
//

import SwiftUI

struct CommentCardView: View {
    let comment: CommentItem

    private let avatarSize: CGFloat = 40
    private let horizontalGap: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: horizontalGap) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.username)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(comment.timeText) · \(comment.ipLocation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            contentColumn
                .padding(.leading, avatarSize + horizontalGap)
        }
        .padding(.vertical, 12)
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(comment.content)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Label("\(comment.likeCount)", systemImage: "hand.thumbsup")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label("\(comment.dislikeCount)", systemImage: "hand.thumbsdown")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .labelStyle(.titleAndIcon)

            if !comment.replies.isEmpty {
                repliesSection
            }
        }
    }

    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(comment.replies) { reply in
                Text("\(reply.username): \(reply.content)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius:12)
        )
    }

    private var avatar: some View {
        Group {
            if let avatarURL = comment.avatarURL,
               let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .padding(6)
            .background(Color.secondary.opacity(0.12))
    }
}

struct CommentItem: Identifiable {
    let id = UUID()
    let avatarURL: String?
    let username: String
    let timeText: String
    let ipLocation: String
    let content: String
    let likeCount: Int
    let dislikeCount: Int
    let replies: [CommentReplyItem]
}

struct CommentReplyItem: Identifiable {
    let id = UUID()
    let username: String
    let content: String
}

#Preview {
    List {
        CommentCardView(
            comment: CommentItem(
                avatarURL: nil,
                username: "PiliUser",
                timeText: "2小时前",
                ipLocation: "广东",
                content: "这期节目观点很有意思，尤其是关于创作流程那一段，反复听了两遍。",
                likeCount: 128,
                dislikeCount: 3,
                replies: [
                    CommentReplyItem(username: "听友A", content: "同感，这段讲得很通透。"),
                    CommentReplyItem(username: "听友B", content: "我更喜欢后半段关于工具的讨论。")
                ]
            )
        )

        CommentCardView(
            comment: CommentItem(
                avatarURL: nil,
                username: "AnotherUser",
                timeText: "昨天",
                ipLocation: "上海",
                content: "期待下一期更新。",
                likeCount: 24,
                dislikeCount: 0,
                replies: []
            )
        )
    }
    .listStyle(.plain)
}

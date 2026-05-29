//
//  CommentCardView.swift
//  PiliPod
//
//  Created by co on 2026/5/28.
//

import SwiftUI

struct CommentCardView: View {
    let comment: CommentItem
    let onTapAvatar: ((Int) -> Void)?
    let onTapReplyUser: ((Int) -> Void)?

    private let avatarSize: CGFloat = 35
    private let horizontalGap: CGFloat = 10

    init(
        comment: CommentItem,
        onTapAvatar: ((Int) -> Void)? = nil,
        onTapReplyUser: ((Int) -> Void)? = nil
    ) {
        self.comment = comment
        self.onTapAvatar = onTapAvatar
        self.onTapReplyUser = onTapReplyUser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: horizontalGap) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.username)
                        .font(.body.weight(.semibold))
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
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(reply.username)
                        .foregroundStyle(Color("BiliPink"))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard let mid = reply.mid, mid > 0 else { return }
                            onTapReplyUser?(mid)
                        }
                    highlightedReplyContentText(reply.content)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
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
        .contentShape(Circle())
        .onTapGesture {
            guard comment.mid > 0 else { return }
            onTapAvatar?(comment.mid)
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .padding(6)
            .background(Color.secondary.opacity(0.12))
    }

    private func highlightedReplyContentText(_ content: String) -> Text {
        Text(": ").foregroundStyle(.primary) + highlightedMentionText(content)
    }

    private func highlightedMentionText(_ content: String) -> Text {
        let pattern = #"\@[^\s@:：]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Text(content).foregroundStyle(.primary)
        }

        let nsContent = content as NSString
        let matches = regex.matches(
            in: content,
            range: NSRange(location: 0, length: nsContent.length)
        )
        guard !matches.isEmpty else {
            return Text(content).foregroundStyle(.primary)
        }

        var result = Text("")
        var currentLocation = 0
        for match in matches {
            if match.range.location > currentLocation {
                let normalPart = nsContent.substring(
                    with: NSRange(
                        location: currentLocation,
                        length: match.range.location - currentLocation
                    )
                )
                result = result + Text(normalPart).foregroundStyle(.primary)
            }

            let mentionPart = nsContent.substring(with: match.range)
            result = result + Text(mentionPart).foregroundStyle(Color("BiliPink"))
            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < nsContent.length {
            let tail = nsContent.substring(
                with: NSRange(
                    location: currentLocation,
                    length: nsContent.length - currentLocation
                )
            )
            result = result + Text(tail).foregroundStyle(.primary)
        }

        return result
    }
}

struct CommentItem: Identifiable {
    let id = UUID()
    let avatarURL: String?
    let mid: Int
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
    let mid: Int?
    let username: String
    let content: String
}

#Preview {
    List {
        CommentCardView(
            comment: CommentItem(
                avatarURL: nil,
                mid: 1,
                username: "PiliUser",
                timeText: "2小时前",
                ipLocation: "广东",
                content: "这期节目观点很有意思，尤其是关于创作流程那一段，反复听了两遍。",
                likeCount: 128,
                dislikeCount: 3,
                replies: [
                    CommentReplyItem(mid: 11, username: "听友A", content: "同感，这段讲得很通透。"),
                    CommentReplyItem(mid: 12, username: "听友B", content: "我更喜欢后半段关于工具的讨论。")
                ]
            )
        )

        CommentCardView(
            comment: CommentItem(
                avatarURL: nil,
                mid: 2,
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

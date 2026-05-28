//
//  VideoCommentsTabView.swift
//  PiliPod
//
//  Created by Codex on 2026/5/28.
//

import SwiftUI

struct VideoCommentsTabView: View {
    let aid: Int

    @State private var isLoading = false
    @State private var errorText: String?
    @State private var comments: [CommentItem] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("评论加载中…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
            } else if let errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text("评论加载失败")
                        .font(.subheadline.weight(.semibold))
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            } else if comments.isEmpty {
                Text("暂无评论")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            } else {
                List(comments) { item in
                    CommentCardView(comment: item)
                }
                .listStyle(.plain)
            }
        }
        .task(id: aid) {
            guard aid > 0, !hasLoaded else { return }
            await loadComments()
        }
    }

    @MainActor
    private func loadComments() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let reply = try await BiliAPI.shared.fetchVideoCommentMainList(aid: Int64(aid))
            comments = reply.replies.map { toCommentItem($0) }
            hasLoaded = true

            if let first = reply.replies.first {
                print("[Comments] first username=\(first.member.name) message=\(first.content.message)")
            } else {
                print("[Comments] no comments returned")
            }
        } catch {
            errorText = error.localizedDescription
            print("[Comments] load failed: \(error.localizedDescription)")
        }
    }

    private func toCommentItem(_ reply: Bilibili_Main_Community_Reply_V1_ReplyInfo) -> CommentItem {
        let childReplies = reply.replies.prefix(2).map { child in
            CommentReplyItem(
                username: child.member.name.isEmpty ? "匿名用户" : child.member.name,
                content: child.content.message
            )
        }

        return CommentItem(
            avatarURL: reply.member.face.isEmpty ? nil : reply.member.face,
            username: reply.member.name.isEmpty ? "匿名用户" : reply.member.name,
            timeText: formatTimestamp(reply.ctime),
            ipLocation: "未知",
            content: reply.content.message,
            likeCount: Int(reply.like),
            dislikeCount: 0,
            replies: Array(childReplies)
        )
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        guard timestamp > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}


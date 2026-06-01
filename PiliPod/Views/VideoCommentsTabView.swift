//
//  VideoCommentsTabView.swift
//  PiliPod
//
//  Created by Codex on 2026/5/28.
//

import SwiftUI

struct VideoCommentsTabView: View {
    let aid: Int
    let onOpenUserSpace: (Int) -> Void

    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var comments: [CommentItem] = []
    @State private var hasLoaded = false
    @State private var nextCursor: Int64 = 0
    @State private var hasMore = true

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
                List {
                    ForEach(comments) { item in
                        CommentCardView(
                            comment: item,
                            onTapAvatar: onOpenUserSpace,
                            onTapReplyUser: onOpenUserSpace
                        )
                    }

                    if hasMore {
                        HStack(spacing: 8) {
                            if isLoadingMore {
                                ProgressView()
                            }
                            Text(isLoadingMore ? "加载更多评论中…" : "上拉加载更多")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .listRowSeparator(.hidden)
                        .onAppear {
                            Task { @MainActor in
                                await loadMoreCommentsIfNeeded()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task(id: aid) {
            guard aid > 0 else { return }
            hasLoaded = false
            hasMore = true
            nextCursor = 0
            comments = []
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
            nextCursor = reply.cursor.next
            hasMore = !reply.cursor.isEnd && !reply.replies.isEmpty
            hasLoaded = true
        } catch {
            errorText = error.localizedDescription
            print("[Comments] load failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func loadMoreCommentsIfNeeded() async {
        guard hasLoaded, hasMore, !isLoadingMore, aid > 0 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let reply = try await BiliAPI.shared.fetchVideoCommentMainList(
                aid: Int64(aid),
                next: nextCursor
            )
            let appended = reply.replies.map { toCommentItem($0) }
            comments.append(contentsOf: appended)
            nextCursor = reply.cursor.next
            hasMore = !reply.cursor.isEnd && !reply.replies.isEmpty
        } catch {
            print("[Comments] load more failed: \(error.localizedDescription)")
        }
    }

    private func toCommentItem(_ reply: Bilibili_Main_Community_Reply_V1_ReplyInfo) -> CommentItem {
        let childReplies = reply.replies.prefix(2).map { child in
            CommentReplyItem(
                mid: child.mid > 0 ? Int(child.mid) : nil,
                username: child.member.name.isEmpty ? "匿名用户" : child.member.name,
                content: child.content.message,
                emotes: child.content.emote.mapValues { emote in
                    CommentEmote(
                        text: emote.text,
                        url: normalizedHTTPSURLString(emote.gifURL.isEmpty ? emote.url : emote.gifURL)
                    )
                }
            )
        }

        return CommentItem(
            avatarURL: reply.member.face.isEmpty ? nil : normalizedHTTPSURLString(reply.member.face),
            mid: Int(reply.mid),
            username: reply.member.name.isEmpty ? "匿名用户" : reply.member.name,
            timeText: formatTimestamp(reply.ctime),
            ipLocation: "未知",
            content: reply.content.message,
            emotes: reply.content.emote.mapValues { emote in
                CommentEmote(
                    text: emote.text,
                    url: normalizedHTTPSURLString(emote.gifURL.isEmpty ? emote.url : emote.gifURL)
                )
            },
            pictures: reply.content.pictures.map { picture in
                CommentPicture(
                    url: normalizedHTTPSURLString(picture.imgSrc),
                    width: picture.imgWidth,
                    height: picture.imgHeight
                )
            },
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

    private func normalizedHTTPSURLString(_ raw: String) -> String {
        raw.replacingOccurrences(of: "http://", with: "https://")
    }
}

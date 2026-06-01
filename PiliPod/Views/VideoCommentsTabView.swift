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
    @State private var detailRootComment: CommentItem?
    @State private var detailReplies: [CommentItem] = []
    @State private var detailIsLoading = false
    @State private var detailErrorText: String?
    @State private var detailNextCursor: Int64 = 0
    @State private var detailHasMore = true
    @State private var detailIsLoadingMore = false
    @State private var showComposer = false
    @State private var composerDetent: PresentationDetent = .fraction(0.5)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
                } else if isInDetailMode, let root = detailRootComment {
                    detailListView(root: root)
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
                                onTapReplyUser: onOpenUserSpace,
                                onTapComment: { tapped in
                                    Task { @MainActor in
                                        await openDetailMode(with: tapped)
                                    }
                                },
                                onTapLike: { tapped in
                                    Task { @MainActor in
                                        await toggleLike(for: tapped)
                                    }
                                },
                                onTapDislike: { tapped in
                                    Task { @MainActor in
                                        await toggleDislike(for: tapped)
                                    }
                                }
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

            if !isInDetailMode {
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.primary)
                        .padding(14)
                        .glassEffect(
                            .regular.interactive(),
                            in: Circle()
                        )
                }
                .tint(.primary)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showComposer) {
            CommentComposerSheet(
                aid: aid,
                onDismiss: { showComposer = false },
                onEmotePanelVisibilityChanged: { shown in
                    composerDetent = shown ? .fraction(0.78) : .fraction(0.5)
                },
                onPosted: {
                    Task { @MainActor in
                        hasLoaded = false
                        hasMore = true
                        nextCursor = 0
                        comments = []
                        await loadComments()
                    }
                }
            )
            .presentationDetents([.fraction(0.5), .fraction(0.78)], selection: $composerDetent)
            .presentationDragIndicator(.visible)
        }
        .task(id: aid) {
            guard aid > 0 else { return }
            hasLoaded = false
            hasMore = true
            nextCursor = 0
            comments = []
            resetDetailMode()
            await loadComments()
        }
    }

    private var isInDetailMode: Bool {
        detailRootComment != nil
    }

    @ViewBuilder
    private func detailListView(root: CommentItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    resetDetailMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if detailIsLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载全部回复…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)
            } else if let detailErrorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text("回复加载失败")
                        .font(.subheadline.weight(.semibold))
                    Text(detailErrorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            } else {
                let rootOnly = CommentItem(
                    avatarURL: root.avatarURL,
                    mid: root.mid,
                    rpid: root.rpid,
                    username: root.username,
                    timeText: root.timeText,
                    ipLocation: root.ipLocation,
                    content: root.content,
                    emotes: root.emotes,
                    pictures: root.pictures,
                    likeCount: root.likeCount,
                    dislikeCount: root.dislikeCount,
                    isLiked: root.isLiked,
                    isDisliked: root.isDisliked,
                    isUpLikedByAuthor: root.isUpLikedByAuthor,
                    replies: []
                )

                List {
                    CommentCardView(
                        comment: rootOnly,
                        onTapAvatar: onOpenUserSpace,
                        onTapReplyUser: onOpenUserSpace,
                        onTapLike: { tapped in
                            Task { @MainActor in
                                await toggleLike(for: tapped)
                            }
                        },
                        onTapDislike: { tapped in
                            Task { @MainActor in
                                await toggleDislike(for: tapped)
                            }
                        }
                    )

                    Text("相关评论")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                        .listRowSeparator(.hidden)

                    ForEach(detailReplies) { reply in
                        CommentCardView(
                            comment: reply,
                            onTapAvatar: onOpenUserSpace,
                            onTapReplyUser: onOpenUserSpace,
                            onTapLike: { tapped in
                                Task { @MainActor in
                                    await toggleLike(for: tapped)
                                }
                            },
                            onTapDislike: { tapped in
                                Task { @MainActor in
                                    await toggleDislike(for: tapped)
                                }
                            }
                        )
                    }

                    if detailHasMore {
                        HStack(spacing: 8) {
                            if detailIsLoadingMore {
                                ProgressView()
                            }
                            Text(detailIsLoadingMore ? "加载更多回复中…" : "上拉加载更多回复")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .listRowSeparator(.hidden)
                        .onAppear {
                            Task { @MainActor in
                                await loadMoreDetailRepliesIfNeeded()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
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

    @MainActor
    private func openDetailMode(with comment: CommentItem) async {
        guard comment.rpid > 0 else { return }
        detailRootComment = comment
        detailReplies = []
        detailErrorText = nil
        detailNextCursor = 0
        detailHasMore = true
        detailIsLoading = true
        defer { detailIsLoading = false }

        do {
            let response = try await BiliAPI.shared.fetchVideoCommentDetailList(
                aid: Int64(aid),
                rootRpid: Int64(comment.rpid),
                next: 0
            )
            detailRootComment = toCommentItem(response.root)
            detailReplies = response.root.replies.map { toCommentItem($0) }
            detailNextCursor = response.cursor.next
            detailHasMore = !response.cursor.isEnd && !response.root.replies.isEmpty
        } catch {
            detailErrorText = error.localizedDescription
        }
    }

    @MainActor
    private func loadMoreDetailRepliesIfNeeded() async {
        guard let root = detailRootComment,
              root.rpid > 0,
              detailHasMore,
              !detailIsLoadingMore,
              aid > 0 else { return }
        detailIsLoadingMore = true
        defer { detailIsLoadingMore = false }

        do {
            let response = try await BiliAPI.shared.fetchVideoCommentDetailList(
                aid: Int64(aid),
                rootRpid: Int64(root.rpid),
                next: detailNextCursor
            )
            let appended = response.root.replies.map { toCommentItem($0) }
            detailReplies.append(contentsOf: appended)
            detailNextCursor = response.cursor.next
            detailHasMore = !response.cursor.isEnd && !response.root.replies.isEmpty
        } catch {
            return
        }
    }

    @MainActor
    private func resetDetailMode() {
        detailRootComment = nil
        detailReplies = []
        detailErrorText = nil
        detailNextCursor = 0
        detailHasMore = true
        detailIsLoadingMore = false
        detailIsLoading = false
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
            rpid: Int(reply.id),
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
            isLiked: reply.replyControl.action == 1,
            isDisliked: reply.replyControl.action == 2,
            isUpLikedByAuthor: reply.replyControl.upLike,
            replies: Array(childReplies)
        )
    }

    @MainActor
    private func toggleLike(for comment: CommentItem) async {
        guard comment.rpid > 0 else { return }
        let willLike = !comment.isLiked
        do {
            try await BiliAPI.shared.likeComment(
                oid: aid,
                rpid: comment.rpid,
                isCancel: !willLike
            )
            applyCommentState(
                rpid: comment.rpid,
                mutate: { item in
                    if willLike {
                        item.isLiked = true
                        item.likeCount += 1
                        if item.isDisliked {
                            item.isDisliked = false
                            item.dislikeCount = max(0, item.dislikeCount - 1)
                        }
                    } else {
                        item.isLiked = false
                        item.likeCount = max(0, item.likeCount - 1)
                    }
                }
            )
        } catch {
            print("[Comments] like failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func toggleDislike(for comment: CommentItem) async {
        guard comment.rpid > 0 else { return }
        let willDislike = !comment.isDisliked
        do {
            try await BiliAPI.shared.hateComment(
                oid: aid,
                rpid: comment.rpid,
                isCancel: !willDislike
            )
            applyCommentState(
                rpid: comment.rpid,
                mutate: { item in
                    if willDislike {
                        item.isDisliked = true
                        item.dislikeCount += 1
                        if item.isLiked {
                            item.isLiked = false
                            item.likeCount = max(0, item.likeCount - 1)
                        }
                    } else {
                        item.isDisliked = false
                        item.dislikeCount = max(0, item.dislikeCount - 1)
                    }
                }
            )
        } catch {
            print("[Comments] dislike failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func applyCommentState(rpid: Int, mutate: (inout CommentItem) -> Void) {
        if let i = comments.firstIndex(where: { $0.rpid == rpid }) {
            mutate(&comments[i])
        }
        if let i = detailReplies.firstIndex(where: { $0.rpid == rpid }) {
            mutate(&detailReplies[i])
        }
        if detailRootComment?.rpid == rpid, var root = detailRootComment {
            mutate(&root)
            detailRootComment = root
        }
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

import SwiftUI

struct MessageFeedView: View {
    enum Category: String, Identifiable {
        case reply, at, like
        var id: Self { self }

        var title: String {
            switch self {
            case .reply: "回复"
            case .at: "@我"
            case .like: "收到喜欢"
            }
        }
    }

    let category: Category
    @State private var replyItems: [ReplyMessageFeedItem] = []
    @State private var atItems: [AtMessageFeedItem] = []
    @State private var likeItems: [LikeMessageFeedItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedVideo: VideoItem?
    @State private var selectedUserMID: Int?
    @Namespace private var videoHeroNamespace

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载消息中…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if let errorMessage, itemsCount == 0 {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else if itemsCount == 0 {
                Text("暂无消息")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        feedRows
                    }
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "pilipod", url.host == "user", let mid = Int(url.pathComponents.dropFirst().first ?? "") else {
                return .systemAction
            }
            selectedUserMID = mid
            return .handled
        })
        .navigationDestination(item: $selectedUserMID) { mid in
            UserSpaceView(mid: mid)
        }
        .navigationDestination(item: $selectedVideo) { video in
            VideoDetailPage(
                video: video,
                namespace: videoHeroNamespace,
                onBack: { selectedVideo = nil }
            )
        }
    }

    @ViewBuilder
    private var feedRows: some View {
        switch category {
        case .reply:
            ForEach(replyItems, id: \.id) { item in
                MessageFeedRow(
                    avatarUsers: [item.user],
                    title: Text(item.user.nickname) + Text(" 回复了你的\(item.item.business)").foregroundStyle(.secondary),
                    content: item.item.sourceContent,
                    timestamp: item.replyTime,
                    item: item.item,
                    onAvatarTap: { selectedUserMID = item.user.mid },
                    onContentTap: { openVideo(item.item) }
                )
            }
        case .at:
            ForEach(atItems, id: \.id) { item in
                MessageFeedRow(
                    avatarUsers: [item.user],
                    title: Text(item.user.nickname) + Text(" 在评论中@了我").foregroundStyle(.secondary),
                    content: item.item.sourceContent,
                    attributedContent: attributedAtContent(item.item),
                    timestamp: item.atTime,
                    item: item.item,
                    onAvatarTap: { selectedUserMID = item.user.mid },
                    onContentTap: { openVideo(item.item) }
                )
            }
        case .like:
            ForEach(likeItems, id: \.id) { item in
                MessageFeedRow(
                    avatarUsers: Array(item.users.prefix(2)),
                    title: likeTitle(item),
                    content: nil,
                    timestamp: item.likeTime,
                    item: item.item,
                    onAvatarTap: { selectedUserMID = item.users.first?.mid },
                    onContentTap: { openVideo(item.item) }
                )
            }
        }
    }

    private var itemsCount: Int {
        switch category {
        case .reply: replyItems.count
        case .at: atItems.count
        case .like: likeItems.count
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            switch category {
            case .reply: replyItems = try await BiliAPI.shared.fetchReplyMessageFeed().items
            case .at: atItems = try await BiliAPI.shared.fetchAtMessageFeed().items
            case .like: likeItems = try await BiliAPI.shared.fetchLikeMessageFeed().total.items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func likeTitle(_ item: LikeMessageFeedItem) -> Text {
        let names = item.users.prefix(2).map(\.nickname).joined(separator: "、")
        let suffix = item.counts >= 2 ? " 等\(item.counts)人赞了我的\(item.item.business)" : " 赞了我的\(item.item.business)"
        return Text(names) + Text(suffix).foregroundStyle(.secondary)
    }

    private func attributedAtContent(_ item: MessageFeedItem) -> AttributedString {
        var result = AttributedString(item.sourceContent)
        for detail in item.atDetails where !detail.nickname.isEmpty {
            let token = "@\(detail.nickname)"
            guard let range = result.range(of: token) else { continue }
            result[range].foregroundColor = .biliPink
            result[range].link = URL(string: "pilipod://user/\(detail.mid)")
        }
        return result
    }

    private func openVideo(_ item: MessageFeedItem) {
        guard let bvid = Self.videoID(from: item.uri) else { return }
        selectedVideo = VideoItem(
            bvid: bvid,
            cid: nil,
            cover: item.image,
            title: item.title.isEmpty ? "视频" : item.title,
            playCount: "--",
            danmakuCount: "--",
            uploader: "",
            duration: 0,
            progressSeconds: nil,
            publishTimeText: "--",
            bottomRcmdReasonText: nil
        )
    }

    private static func videoID(from uri: String) -> String? {
        guard let url = URL(string: uri), let host = url.host, host.contains("bilibili.com") else { return nil }
        let parts = url.path.split(separator: "/")
        guard let value = parts.last else { return nil }
        if value.lowercased().hasPrefix("bv") { return String(value) }
        if value.lowercased().hasPrefix("av"), let aid = Int(value.dropFirst()) {
            return BiliIdConverter.av2bv(aid: Int64(aid))
        }
        return nil
    }
}

private struct MessageFeedRow: View {
    let avatarUsers: [MessageFeedUser]
    let title: Text
    let content: String?
    var attributedContent: AttributedString?
    let timestamp: Int
    let item: MessageFeedItem
    let onAvatarTap: () -> Void
    let onContentTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAvatarTap) {
                AvatarStack(users: avatarUsers)
            }
            .buttonStyle(.plain)

            Button(action: onContentTap) {
                VStack(alignment: .leading, spacing: 4) {
                    title.font(.system(size: 15, weight: .medium)).lineLimit(1)
                    if let attributedContent {
                        Text(attributedContent)
                            .font(.system(size: 14))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else if let content {
                        Text(content)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp))))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Button(action: onContentTap) {
                ZStack(alignment: .bottomLeading) {
                    CachedAsyncImage(url: URL(string: item.image)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.secondary.opacity(0.12)
                        }
                    }
                    if !item.title.isEmpty {
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .padding(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.55))
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 94) }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct AvatarStack: View {
    let users: [MessageFeedUser]

    var body: some View {
        ZStack {
            ForEach(Array(users.enumerated()), id: \.element.mid) { index, user in
                CachedAsyncImage(url: URL(string: user.avatar)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.fill").resizable().scaledToFit().padding(12).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 48, height: 48)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Circle())
                .overlay(Circle().stroke(.background, lineWidth: 2))
                .offset(x: CGFloat(index) * 10, y: CGFloat(index) * 10)
            }
        }
        .frame(width: 58, height: 58)
    }
}

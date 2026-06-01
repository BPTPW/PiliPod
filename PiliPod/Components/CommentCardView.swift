//
//  CommentCardView.swift
//  PiliPod
//
//  Created by co on 2026/5/28.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CommentCardView: View {
    let comment: CommentItem
    let onTapAvatar: ((Int) -> Void)?
    let onTapReplyUser: ((Int) -> Void)?
    let onTapComment: ((CommentItem) -> Void)?
    let onTapLike: ((CommentItem) -> Void)?
    let onTapDislike: ((CommentItem) -> Void)?

    private let avatarSize: CGFloat = 35
    private let horizontalGap: CGFloat = 10
    @State private var selectedPicture: CommentPicture?

    init(
        comment: CommentItem,
        onTapAvatar: ((Int) -> Void)? = nil,
        onTapReplyUser: ((Int) -> Void)? = nil,
        onTapComment: ((CommentItem) -> Void)? = nil,
        onTapLike: ((CommentItem) -> Void)? = nil,
        onTapDislike: ((CommentItem) -> Void)? = nil
    ) {
        self.comment = comment
        self.onTapAvatar = onTapAvatar
        self.onTapReplyUser = onTapReplyUser
        self.onTapComment = onTapComment
        self.onTapLike = onTapLike
        self.onTapDislike = onTapDislike
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
        .contentShape(Rectangle())
        .onTapGesture {
            onTapComment?(comment)
        }
        .fullScreenCover(item: $selectedPicture) { picture in
            FullscreenImageViewer(
                imageURL: picture.url,
                onDismiss: { selectedPicture = nil }
            )
        }
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            commentBodyView

            if !comment.pictures.isEmpty {
                picturesView
            }

            HStack(spacing: 18) {
                if comment.isUpLikedByAuthor {
                    Text("UP主觉得很赞")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // 点赞按钮
                Button {
                    onTapLike?(comment)
                } label: {
                    Label(
                        "\(comment.likeCount)",
                        systemImage: comment.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup"
                    )
                    .font(.subheadline)
                    .foregroundStyle(comment.isLiked ? Color("BiliPink") : .secondary)
                }
                .buttonStyle(.plain)

                // 点踩按钮
                Button {
                    onTapDislike?(comment)
                } label: {
                    Label(
                        "\(comment.dislikeCount)",
                        systemImage: comment.isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown"
                    )
                    .font(.subheadline)
                    .foregroundStyle(comment.isDisliked ? Color("BiliPink") : .secondary)
                }
                .buttonStyle(.plain)
            }
            .labelStyle(.titleAndIcon)

            if !comment.replies.isEmpty {
                repliesSection
            }
        }
    }

    @ViewBuilder
    private var commentBodyView: some View {
        if comment.emotes.isEmpty {
            Text(comment.content)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            EmoteRichTextView(
                text: comment.content,
                emotes: comment.emotes
            )
            .font(.body)
            .foregroundStyle(.primary)
        }
    }

    private var picturesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(comment.pictures) { picture in
                AsyncImage(url: URL(string: picture.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .empty:
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.12))
                            .overlay {
                                ProgressView()
                            }
                    case .failure:
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.12))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(
                    maxHeight: 220,
                    alignment: .leading
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPicture = picture
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(comment.replies) { reply in
                ZStack(alignment: .topLeading) {
                    EmoteRichTextView(
                        text: "\(reply.username): \(reply.content)",
                        emotes: reply.emotes,
                        fontTextStyle: .subheadline,
                        highlightMentions: true,
                        usernamePrefix: reply.username
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(reply.username)
                        .font(.subheadline)
                        .foregroundStyle(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard let mid = reply.mid, mid > 0 else { return }
                            onTapReplyUser?(mid)
                        }
                }
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

}

struct CommentItem: Identifiable {
    let id = UUID()
    let avatarURL: String?
    let mid: Int
    let rpid: Int
    let username: String
    let timeText: String
    let ipLocation: String
    let content: String
    let emotes: [String: CommentEmote]
    let pictures: [CommentPicture]
    var likeCount: Int
    var dislikeCount: Int
    var isLiked: Bool
    var isDisliked: Bool
    var isUpLikedByAuthor: Bool
    let replies: [CommentReplyItem]
}

struct CommentReplyItem: Identifiable {
    let id = UUID()
    let mid: Int?
    let username: String
    let content: String
    let emotes: [String: CommentEmote]
}

struct CommentEmote: Equatable {
    let text: String
    let url: String
}

struct CommentPicture: Identifiable {
    let id = UUID()
    let url: String
    let width: Double
    let height: Double
}

private struct EmoteRichTextView: View {
    let text: String
    let emotes: [String: CommentEmote]
    var fontTextStyle: UIFont.TextStyle = .body
    var highlightMentions: Bool = false
    var usernamePrefix: String? = nil

    var body: some View {
        EmoteTextViewRepresentable(
            text: text,
            emotes: emotes,
            fontTextStyle: fontTextStyle,
            highlightMentions: highlightMentions,
            usernamePrefix: usernamePrefix
        )
            .frame(minHeight: 20)
    }
}

#if canImport(UIKit)
private struct EmoteTextViewRepresentable: UIViewRepresentable {
    let text: String
    let emotes: [String: CommentEmote]
    let fontTextStyle: UIFont.TextStyle
    let highlightMentions: Bool
    let usernamePrefix: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let request = RenderRequest(
            text: text,
            emotes: emotes,
            fontTextStyle: fontTextStyle,
            highlightMentions: highlightMentions,
            usernamePrefix: usernamePrefix
        )
        context.coordinator.render(request: request, on: uiView)
    }

    struct RenderRequest: Equatable {
        let text: String
        let emotes: [String: CommentEmote]
        let fontTextStyle: UIFont.TextStyle
        let highlightMentions: Bool
        let usernamePrefix: String?
    }

    final class Coordinator {
        private var renderID = UUID()
        private var loadingTask: Task<Void, Never>?

        deinit {
            loadingTask?.cancel()
        }

        func render(request: RenderRequest, on textView: UITextView) {
            loadingTask?.cancel()
            let currentID = UUID()
            renderID = currentID

            textView.attributedText = EmoteTextViewRepresentable.makeAttributedText(
                request: request,
                imageLookup: { EmoteImageStore.shared.image(for: $0) }
            )

            let missingURLs = request.emotes.values
                .map(\.url)
                .filter { !$0.isEmpty && EmoteImageStore.shared.image(for: $0) == nil }
            guard !missingURLs.isEmpty else { return }

            loadingTask = Task {
                await EmoteImageStore.shared.prefetch(urlStrings: missingURLs)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.renderID == currentID else { return }
                    textView.attributedText = EmoteTextViewRepresentable.makeAttributedText(
                        request: request,
                        imageLookup: { EmoteImageStore.shared.image(for: $0) }
                    )
                }
            }
        }
    }

    private static func makeAttributedText(
        request: RenderRequest,
        imageLookup: (String) -> UIImage?
    ) -> NSAttributedString {
        let baseFont = UIFont.preferredFont(forTextStyle: request.fontTextStyle)
        let baseColor = UIColor.label
        let mutable = NSMutableAttributedString(
            string: request.text,
            attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ]
        )

        let sortedKeys = request.emotes.keys.sorted { $0.count > $1.count }
        for key in sortedKeys where !key.isEmpty {
            guard let emote = request.emotes[key], !emote.url.isEmpty else { continue }
            let nsText = mutable.string as NSString
            let ranges = nsText.ranges(of: key)
            for range in ranges.reversed() {
                let attachment = NSTextAttachment()
                attachment.bounds = CGRect(x: 0, y: -4, width: 20, height: 20)
                attachment.image = imageLookup(emote.url) ?? placeholderEmoteImage()
                let imgAttr = NSAttributedString(attachment: attachment)
                mutable.replaceCharacters(in: range, with: imgAttr)
            }
        }

        if request.highlightMentions {
            let pattern = #"\@[^\s@:：]+"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let all = NSRange(location: 0, length: (mutable.string as NSString).length)
                let color = UIColor(named: "BiliPink") ?? UIColor.systemPink
                regex.matches(in: mutable.string, range: all).forEach { match in
                    mutable.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }
        }

        if let usernamePrefix = request.usernamePrefix, !usernamePrefix.isEmpty {
            let prefix = "\(usernamePrefix):"
            let ns = mutable.string as NSString
            let range = ns.range(of: prefix)
            if range.location != NSNotFound {
                let color = UIColor(named: "BiliPink") ?? UIColor.systemPink
                mutable.addAttribute(.foregroundColor, value: color, range: range)
            }
        }

        return mutable
    }

    private static func placeholderEmoteImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        return renderer.image { ctx in
            UIColor.systemGray4.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 20, height: 20), cornerRadius: 4).fill()
            UIColor.systemGray2.setStroke()
            UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 18, height: 18), cornerRadius: 4).stroke()
        }
    }
}

private final class EmoteImageStore {
    static let shared = EmoteImageStore()

    private let cache = NSCache<NSString, UIImage>()
    private init() {}

    func image(for urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    func prefetch(urlStrings: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for urlString in Set(urlStrings) {
                group.addTask {
                    await self.fetch(urlString: urlString)
                }
            }
        }
    }

    private func fetch(urlString: String) async {
        if cache.object(forKey: urlString as NSString) != nil { return }
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            cache.setObject(image, forKey: urlString as NSString)
        } catch {
            return
        }
    }
}

private extension NSString {
    func ranges(of substring: String) -> [NSRange] {
        var found: [NSRange] = []
        var searchRange = NSRange(location: 0, length: length)
        while true {
            let range = self.range(of: substring, options: [], range: searchRange)
            if range.location == NSNotFound { break }
            found.append(range)
            let nextLocation = range.location + range.length
            searchRange = NSRange(location: nextLocation, length: length - nextLocation)
        }
        return found
    }
}
#endif

#Preview {
    List {
        CommentCardView(
            comment: CommentItem(
                avatarURL: nil,
                mid: 1,
                rpid: 1001,
                username: "PiliUser",
                timeText: "2小时前",
                ipLocation: "广东",
                content: "这期节目观点很有意思，尤其是关于创作流程那一段，反复听了两遍。",
                emotes: [:],
                pictures: [CommentPicture(url: "https://i2.hdslb.com/bfs/archive/e8eaf7459a5d008e9142e75b5798798f10dfbc16.jpg@672w_378h_1c.webp", width: 672, height: 378)],
                likeCount: 128,
                dislikeCount: 3,
                isLiked: false,
                isDisliked: false,
                isUpLikedByAuthor: true,
                replies: [
                    CommentReplyItem(mid: 11, username: "听友A", content: "同感，这段讲得很通透。", emotes: [:]),
                    CommentReplyItem(mid: 12, username: "听友B", content: "我更喜欢后半段关于工具的讨论。", emotes: [:])
                ]
            )
        )

        CommentCardView(
            comment: CommentItem(
                avatarURL: nil,
                mid: 2,
                rpid: 1002,
                username: "AnotherUser",
                timeText: "昨天",
                ipLocation: "上海",
                content: "期待下一期更新。",
                emotes: [:],
                pictures: [],
                likeCount: 24,
                dislikeCount: 0,
                isLiked: true,
                isDisliked: false,
                isUpLikedByAuthor: false,
                replies: []
            )
        )
    }
    .listStyle(.plain)
}

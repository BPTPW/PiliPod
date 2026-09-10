//
//  MessageConversationView.swift
//  PiliPod
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageConversationView: View {
    let session: PrivateMessageSession

    @State private var messages: [Bilibili_Im_Type_Msg] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var inputText = ""
    @State private var selectedVideo: VideoItem?
    @State private var selectedUserMID: Int?
    @Namespace private var videoHeroNamespace

    private var currentMID: UInt64 {
        UInt64(LoginSession.shared.cookies?.DedeUserID ?? "") ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            messageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            composer
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                conversationHeader
            }
        }
        .navigationDestination(item: $selectedUserMID) { mid in
            UserSpaceView(mid: mid)
        }
        .navigationDestination(item: $selectedVideo) { video in
            if #available(iOS 18.0, *) {
                VideoDetailPage(
                    video: video,
                    namespace: videoHeroNamespace,
                    onBack: { selectedVideo = nil }
                )
                .navigationTransition(
                    .zoom(sourceID: "conversationVideo.\(video.bvid)", in: videoHeroNamespace)
                )
            } else {
                VideoDetailPage(
                    video: video,
                    namespace: videoHeroNamespace,
                    onBack: { selectedVideo = nil }
                )
            }
        }
        .task { await loadMessages() }
    }

    private var conversationHeader: some View {
        Button {
            guard session.sessionType == 1, session.talkerID <= UInt64(Int.max) else { return }
            selectedUserMID = Int(session.talkerID)
        } label: {
            ZStack(alignment: .top) {
                Text(session.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 52)

                CachedAsyncImage(url: MessagePayload.url(from: session.avatarURL)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.14))
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
            }
            .frame(width: 162, height: 72)
            .offset(y: 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(session.sessionType != 1)
    }

    @ViewBuilder
    private var messageContent: some View {
        if isLoading {
            ProgressView("加载消息中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, messages.isEmpty {
            ContentUnavailableView {
                Label("消息加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") { Task { await loadMessages() } }
            }
        } else if messages.isEmpty {
            ContentUnavailableView("暂无消息", systemImage: "bubble.left.and.bubble.right")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.element.msgKey) { index, message in
                            messageRow(message, at: index)
                                .id(message.msgKey)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.msgKey, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: Bilibili_Im_Type_Msg, at index: Int) -> some View {
        let isMine = message.senderUid == currentMID
        let previousSameSender = index > 0 && messages[index - 1].senderUid == message.senderUid
        let nextSameSender = index + 1 < messages.count && messages[index + 1].senderUid == message.senderUid

        if let card = MessageCardPayload(message: message) {
            MessageCardView(
                card: card,
                heroNamespace: videoHeroNamespace,
                onVideoTap: { selectedVideo = card.videoItem },
                isMine: isMine,
                isEmbedded: card.isUserVideoShare
            )
            .padding(.vertical, 14)
        } else {
            MessageBubble(
                text: MessagePayload.text(from: message),
                isMine: isMine,
                isFirstInGroup: !previousSameSender,
                isLastInGroup: !nextSameSender
            )
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button(action: {}) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .glassEffect(.regular.interactive(), in: .circle)

            HStack {
                TextField("消息", text: $inputText, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .font(.body)
                    .padding(.trailing, 38)
                    .overlay(alignment: .bottomTrailing) {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: {}) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(.biliPink, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Button(action: {}) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private func loadMessages() async {
        guard LoginSession.shared.isLogin else {
            isLoading = false
            errorMessage = "请先登录"
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            messages = try await BiliAPI.shared.fetchPrivateMessageMessages(
                talkerID: session.talkerID,
                sessionType: session.sessionType
            )
                .filter { !$0.sysCancel && $0.msgStatus != 2 }
                .sorted { lhs, rhs in
                    if lhs.msgSeqno == rhs.msgSeqno { return lhs.timestamp < rhs.timestamp }
                    return lhs.msgSeqno < rhs.msgSeqno
                }
        } catch {
            errorMessage = error.localizedDescription
            ErrorLogService.record(error, context: "加载私信详情")
        }
        isLoading = false
    }
}

private struct MessagePayload {
    static func dictionary(from raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func url(from raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        return URL(string: value)
    }

    static func text(from message: Bilibili_Im_Type_Msg) -> String {
        let raw = message.content
        guard let dictionary = dictionary(from: raw) else { return raw }

        if message.msgType.rawValue == 18,
           let nestedContent = dictionary["content"] as? String,
           let nestedData = nestedContent.data(using: .utf8),
           let items = try? JSONSerialization.jsonObject(with: nestedData) as? [[String: Any]]
        {
            let text = items.compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            if !text.isEmpty { return text }
        }

        if let value = dictionary["content"] as? String { return value }
        if let value = dictionary["text"] as? String { return value }
        if let value = dictionary["title"] as? String { return value }
        if message.msgType.rawValue == 2 || message.msgType.rawValue == 6 {
            return "[图片]"
        }
        return raw
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String where !value.isEmpty:
            value
        case let value as NSNumber:
            value.stringValue
        default:
            nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            value
        case let value as NSNumber:
            value.intValue
        case let value as String:
            Int(value)
        default:
            nil
        }
    }
}

private struct MessageCardPayload {
    enum Kind { case video, article, other }

    let kind: Kind
    let title: String
    let summary: String
    let coverURL: String
    let bvid: String?
    let duration: Int
    let isUserVideoShare: Bool

    init?(message: Bilibili_Im_Type_Msg) {
        let type = message.msgType.rawValue
        guard type == 7 || type == 11 || type == 12 || type == 14,
              let dictionary = MessagePayload.dictionary(from: message.content)
        else { return nil }

        let source = MessagePayload.int(dictionary["source"])
        isUserVideoShare = type == 7 && source == 5
        if type == 11 || (type == 7 && source == 5) {
            kind = .video
        } else if type == 12 || (type == 7 && source == 6) {
            kind = .article
        } else {
            kind = .other
        }

        title = (dictionary["title"] as? String)
            ?? (dictionary["headline"] as? String)
            ?? (dictionary["desc"] as? String)
            ?? "分享内容"
        summary = (dictionary["summary"] as? String)
            ?? (dictionary["desc"] as? String)
            ?? ""
        coverURL = MessagePayload.string(dictionary["cover"])
            ?? MessagePayload.string(dictionary["thumb"])
            ?? ((dictionary["image_urls"] as? [String])?.first ?? "")
        bvid = MessagePayload.string(dictionary["bvid"])
        duration = MessagePayload.int(dictionary["duration"])
            ?? MessagePayload.int(dictionary["times"])
            ?? 0
    }

    var videoItem: VideoItem? {
        guard kind == .video, let bvid else { return nil }
        return VideoItem(
            bvid: bvid,
            cid: nil,
            cover: coverURL,
            title: title,
            playCount: "--",
            danmakuCount: "--",
            uploader: "",
            duration: duration,
            progressSeconds: nil,
            publishTimeText: "--",
            bottomRcmdReasonText: nil
        )
    }
}

private struct MessageBubble: View {
    let text: String
    let isMine: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 44) }
            Text(text)
                .font(.body)
                .foregroundStyle(isMine ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    isMine
                        ? AnyShapeStyle(Color.biliPink)
                        : AnyShapeStyle(Color(.systemBackground))
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isMine ? Color.clear : Color.primary.opacity(0.08),
                            lineWidth: 0.75
                        )
                }
                .shadow(
                    color: .black.opacity(isMine ? 0.08 : 0.1),
                    radius: 3,
                    y: 1
                )
            if !isMine { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(.top, isFirstInGroup ? 2 : -4)
    }
}

private struct MessageCardCoverView: View {
    let url: URL?

    #if canImport(UIKit)
    @State private var image: UIImage?
    #endif
    @State private var didFail = false

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFail || url == nil {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            #else
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        #if canImport(UIKit)
        image = nil
        #endif
        didFail = false

        guard let url else {
            print("[MessageCardCover] invalid URL")
            didFail = true
            return
        }

        #if canImport(UIKit)
        guard let loadedImage = await SharedRemoteImageStore.shared.image(for: url) else {
            print("[MessageCardCover] load failed: \(url.absoluteString)")
            didFail = true
            return
        }
        image = loadedImage
        #else
        didFail = true
        #endif
    }
}

private struct MessageCardView: View {
    let card: MessageCardPayload
    let heroNamespace: Namespace.ID
    let onVideoTap: () -> Void
    let isMine: Bool
    let isEmbedded: Bool

    var body: some View {
        Button(action: onVideoTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.14))
                        MessageCardCoverView(url: MessagePayload.url(from: card.coverURL))
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    if card.kind == .video, card.duration > 0 {
                        Text(Self.durationText(card.duration))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: Capsule())
                            .padding(8)
                    }
                }

                Text(card.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, card.summary.isEmpty ? 12 : 4)

                if !card.summary.isEmpty {
                    Text(card.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .background(
                isEmbedded
                    ? AnyShapeStyle(isMine ? Color.biliPink : Color(.systemBackground))
                    : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .padding(isEmbedded ? 5 : 0)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: isEmbedded ? 292 : .infinity)
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
        .matchedTransitionSource(id: "conversationVideo.\(card.bvid ?? card.title)", in: heroNamespace)
        .disabled(card.videoItem == nil)
        .opacity(card.videoItem == nil ? 0.9 : 1)
    }

    private static func durationText(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remaining = seconds % 60
        return minutes >= 60
            ? String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, remaining)
            : String(format: "%02d:%02d", minutes, remaining)
    }
}

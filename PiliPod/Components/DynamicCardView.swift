import SwiftUI
import SafariServices

struct DynamicCardView: View {
    let item: UserSpaceDynamicItem
    let onVideoTap: (UserSpaceDynamicItem.Video) -> Void
    let onLiveTap: (UserSpaceDynamicItem.Live) -> Void
    let onAuthorTap: (Int) -> Void
    let onCommentTap: (UserSpaceDynamicItem.CommentTarget) -> Void
    var showsFullTextByDefault = false
    var onTapDetail: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @State private var showsFullText = false
    @State private var showsOriginalFullText = false
    @State private var selectedImageURL: String?
    @State private var selectedWebURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorHeader
            if !item.text.isEmpty { textContent }
            imageGrid
            if let video = item.video { videoPreview(video) }
            if let live = item.live { livePreview(live) }
            if let preview = item.previewCard { genericPreview(preview) }
            if let original = item.original { originalPreview(original) }
            actionBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(cardBackground)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { onTapDetail?() }
        .onAppear { if showsFullTextByDefault { showsFullText = true; showsOriginalFullText = true } }
        .fullScreenCover(isPresented: Binding(get: { selectedImageURL != nil }, set: { if !$0 { selectedImageURL = nil } })) {
            if let url = selectedImageURL {
                FullscreenImageViewer(imageURL: url, onDismiss: { selectedImageURL = nil })
            }
        }
        .sheet(isPresented: Binding(get: { selectedWebURL != nil }, set: { if !$0 { selectedWebURL = nil } })) {
            if let selectedWebURL { SafariView(url: selectedWebURL) }
        }
    }

    private var authorHeader: some View {
        HStack(spacing: 10) {
            Button { if let mid = item.author.mid { onAuthorTap(mid) } } label: {
                CachedAsyncImage(url: item.author.faceURL.flatMap(URL.init(string:))) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                    else { Circle().fill(Color(.systemGray5)).overlay(Image(systemName: "person.fill").foregroundStyle(.secondary)) }
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(item.author.mid == nil)

            VStack(alignment: .leading, spacing: 3) {
                Button(item.author.name.isEmpty ? "用户动态" : item.author.name) { if let mid = item.author.mid { onAuthorTap(mid) } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                    .disabled(item.author.mid == nil)
                Text(item.author.publishTime ?? DynamicCardView.timestampText(item.author.publishTimestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(.tertiary)
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            RichTextFlow(nodes: item.richText, onMention: onAuthorTap, onWeb: { selectedWebURL = $0 })
                .font(.body)
                .frame(maxHeight: showsFullText ? nil : 4 * 24, alignment: .top)
                .clipped()
                .frame(maxWidth: .infinity, alignment: .leading)
            if !showsFullTextByDefault && estimatedLineCount > 4 {
                Button(showsFullText ? "收起" : "展开") { showsFullText.toggle() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.biliPink)
            }
        }
    }

    private var estimatedLineCount: Int {
        estimatedLineCount(for: item.richText)
    }

    private func estimatedLineCount(for nodes: [UserSpaceDynamicItem.RichTextNode]) -> Int {
        let availableCharactersPerLine = 22
        return nodes.reduce(0) { total, node in
            if node.kind == .emoji { return total + 1 }
            let explicitLines = node.text.split(separator: "\n", omittingEmptySubsequences: false)
            return total + explicitLines.reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(availableCharactersPerLine)))) }
        }
    }

    @ViewBuilder private var imageGrid: some View {
        if !item.images.isEmpty {
            let columns = item.images.count == 1 ? [GridItem(.flexible())] : Array(repeating: GridItem(.flexible(), spacing: 4), count: min(3, item.images.count))
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(item.images) { asset in
                    Button { selectedImageURL = asset.url } label: {
                        if item.images.count == 1 {
                            dynamicImage(
                                asset,
                                aspectRatio: min(max((asset.width ?? 1) / (asset.height ?? 1), 0.2), 4.0 / 3.0),
                                cornerRadius: 12
                            )
                        } else {
                            squareDynamicImage(asset, cornerRadius: 12)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func videoPreview(_ video: UserSpaceDynamicItem.Video) -> some View {
        Button { onVideoTap(video) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    CachedAsyncImage(url: video.coverURL.flatMap { URL(string: $0) }) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
                        else { Rectangle().fill(Color(.systemGray5)).overlay(Image(systemName: "play.rectangle.fill").foregroundStyle(.secondary)) }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("视频")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                        .padding(8)
                }
                Text(video.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(VideoItem.formatCount(video.playCount))播放 · \(VideoItem.formatCount(video.danmakuCount))弹幕")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private func livePreview(_ live: UserSpaceDynamicItem.Live) -> some View {
        Button { onLiveTap(live) } label: {
            previewRow(title: live.title, subtitle: [live.onlineCount, live.areaName].filter { !$0.isEmpty }.joined(separator: " · "), cover: live.coverURL, badge: "LIVE")
        }
        .buttonStyle(.plain)
    }

    private func genericPreview(_ preview: UserSpaceDynamicItem.PreviewCard) -> some View {
        Button { if let link = preview.link, let url = URL(string: link) { openURL(url) } } label: {
            previewRow(title: preview.title, subtitle: preview.subtitle ?? "", cover: preview.coverURL, badge: nil)
        }
        .buttonStyle(.plain)
        .disabled(preview.link == nil)
    }

    private func originalPreview(_ original: UserSpaceDynamicItem.Original) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(original.author.name.isEmpty ? "原动态不可用" : "@\(original.author.name)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if let title = original.title, !title.isEmpty {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
            }
            if !original.richText.isEmpty {
                RichTextFlow(nodes: original.richText, onMention: onAuthorTap, onWeb: { selectedWebURL = $0 })
                    .font(.body)
                    .frame(maxHeight: showsOriginalFullText ? nil : 4 * 24, alignment: .top)
                    .clipped()
                if !showsFullTextByDefault && estimatedLineCount(for: original.richText) > 4 {
                    Button(showsOriginalFullText ? "收起" : "展开") { showsOriginalFullText.toggle() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.biliPink)
                }
            }
            if let video = original.video { videoPreview(video) }
            else if let live = original.live { livePreview(live) }
            else if let preview = original.previewCard { genericPreview(preview) }
            else if !original.images.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(3, original.images.count)), spacing: 4) { ForEach(original.images) { asset in
                    Button { selectedImageURL = asset.url } label: {
                        squareDynamicImage(asset, cornerRadius: 9)
                    }.buttonStyle(.plain)
                }}
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGray6)))
    }

    private func previewRow(title: String, subtitle: String, cover: String?, badge: String?) -> some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: cover.flatMap(URL.init(string:))) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color(.systemGray5).overlay(Image(systemName: badge == "LIVE" ? "dot.radiowaves.left.and.right" : "play.rectangle.fill").foregroundStyle(.secondary)) }
            }
            .frame(width: 112, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                if let badge { Text(badge).font(.caption2.weight(.bold)).foregroundStyle(.biliPink) }
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func dynamicImage(
        _ asset: UserSpaceDynamicItem.ImageAsset,
        aspectRatio: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        CachedAsyncImage(url: URL(string: asset.url)) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(.systemGray5))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipped(antialiased: true)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func squareDynamicImage(
        _ asset: UserSpaceDynamicItem.ImageAsset,
        cornerRadius: CGFloat
    ) -> some View {
        Color(.systemGray5)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CachedAsyncImage(url: URL(string: asset.url)) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var actionBar: some View {
        HStack {
            Label(VideoItem.formatCount(item.statistics.forward), systemImage: "arrow.2.squarepath")
            Spacer()
            Button { onCommentTap(item.commentTarget) } label: { Label(VideoItem.formatCount(item.statistics.reply), systemImage: "text.bubble") }
                .buttonStyle(.plain)
            Spacer()
            Label(VideoItem.formatCount(item.statistics.like), systemImage: "hand.thumbsup")
                .foregroundStyle(item.statistics.likeActive ? Color("BiliPink") : .secondary)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }

    private static func timestampText(_ timestamp: Int?) -> String {
        guard let timestamp else { return "" }
        return VideoItem.formatHistoryTimestamp(timestamp)
    }
}

private struct RichTextFlow: View {
    let nodes: [UserSpaceDynamicItem.RichTextNode]
    let onMention: (Int) -> Void
    let onWeb: (URL) -> Void

    var body: some View {
        RichTextWrappingLayout(spacing: 4, lineSpacing: 2) {
            ForEach(nodes) { node in
                nodeView(node)
            }
        }
    }

    @ViewBuilder
    private func nodeView(_ node: UserSpaceDynamicItem.RichTextNode) -> some View {
        switch node.kind {
        case .emoji:
            if let urlString = node.emojiURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        Text(node.text)
                    }
                }
                .frame(height: 21)
                .fixedSize()
                .accessibilityLabel(node.text)
            } else { Text(node.text) }
        case .mention:
            Button {
                if let rid = node.rid { onMention(rid) }
            } label: {
                Text(node.text).foregroundStyle(.biliPink)
            }
            .buttonStyle(.plain)
            .disabled(node.rid == nil)
        case .link:
            Button { if let url = node.url.flatMap(URL.init(string:)) { onWeb(url) } } label: {
                Text(node.text).foregroundStyle(.biliPink)
            }
            .buttonStyle(.plain)
        case .text:
            Text(node.text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutValue(key: RichTextWrappingLayout.WrapTextKey.self, value: true)
        case .topic, .other:
            Text(node.text)
                .foregroundStyle(.biliPink)
                .fixedSize(horizontal: true, vertical: true)
        }
    }
}

private struct RichTextWrappingLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    struct WrapTextKey: LayoutValueKey {
        static let defaultValue = false
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let wraps = subview[WrapTextKey.self]
            var size = subview.sizeThatFits(ProposedViewSize(width: wraps ? max(0, width - x) : nil, height: nil))
            if x > 0 && wraps {
                let intrinsic = subview.sizeThatFits(.unspecified)
                if intrinsic.width > width - x {
                    y += rowHeight + lineSpacing
                    x = 0
                    rowHeight = 0
                    size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                }
            } else if x > 0 && !wraps && x + size.width > width {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
                size = subview.sizeThatFits(ProposedViewSize(width: wraps ? width : nil, height: nil))
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let wraps = subview[WrapTextKey.self]
            var size = subview.sizeThatFits(ProposedViewSize(width: wraps ? max(0, bounds.maxX - x) : nil, height: nil))
            if x > bounds.minX && wraps {
                let intrinsic = subview.sizeThatFits(.unspecified)
                if intrinsic.width > bounds.maxX - x {
                    y += rowHeight + lineSpacing
                    x = bounds.minX
                    rowHeight = 0
                    size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                }
            } else if x > bounds.minX && !wraps && x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
                size = subview.sizeThatFits(ProposedViewSize(width: wraps ? bounds.width : nil, height: nil))
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

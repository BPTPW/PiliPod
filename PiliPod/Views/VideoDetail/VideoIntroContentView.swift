import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IntroTabDisplayModel: Equatable {
    let aid: Int
    let bvid: String
    let ownerMid: Int
    let ownerFace: String
    let ownerName: String
    let ownerFollowerCount: Int?
    let ownerArchiveCount: Int?
    let isOwnerFollowing: Bool
    let isOwnerFollowRequesting: Bool
    let fullSegmentBanner: String?
    let fullSegmentBannerCategoryRawValue: String?
    let title: String
    let viewCount: Int
    let danmakuCount: Int
    let pubdate: Int
    let onlineTotal: String?
    let isExpanded: Bool
    let introDescriptionText: AttributedString
    let isLiked: Bool
    let isDisliked: Bool
    let isCoined: Bool
    let userCoinCount: Int
    let isFavorited: Bool
    let isWatchLater: Bool
    let likeCount: Int
    let coinCount: Int
    let favoriteCount: Int
    let shareCount: Int
    let isLikeRequesting: Bool
    let isDislikeRequesting: Bool
    let isCoinRequesting: Bool
    let isFavoriteRequesting: Bool
    let isWatchLaterRequesting: Bool
    let currentPageCID: Int
    let currentPageTitle: String
    let videoPages: [VideoPageListItem]
    let relatedIsLoading: Bool
    let relatedError: String?
    let relatedVideos: [VideoItem]
}

struct IntroTabContentView: View, Equatable {
    let model: IntroTabDisplayModel
    let namespace: Namespace.ID
    let onOpenOwner: (Int, Int?) -> Void
    let onToggleFollow: () -> Void
    let onToggleExpand: () -> Void
    let onOpenIntroLink: (URL) -> OpenURLAction.Result
    let onToggleLike: () -> Void
    let onTripleLike: () async -> TripleLikeVisualState
    let onToggleDislike: () -> Void
    let onCoin1: () -> Void
    let onCoin2: () -> Void
    let onToggleFavorite: () -> Void
    let onShare: () -> Void
    let onShareWithTime: () -> Void
    let onShareImage: () -> Void
    let onLaterWatch: () -> Void
    let onOpenPageDrawer: () -> Void
    let onSelectPage: (VideoPageListItem) -> Void
    let onPageStripDragStateChange: (Bool) -> Void
    let onOpenRelatedVideo: (VideoItem) -> Void

    static func == (lhs: IntroTabContentView, rhs: IntroTabContentView) -> Bool {
        lhs.model == rhs.model
    }

    private var hasIntroDescription: Bool {
        !model.introDescriptionText.characters.isEmpty
    }

    private var fullSegmentBannerColor: Color {
        guard let rawValue = model.fullSegmentBannerCategoryRawValue,
              let banner = fullSegmentBannerInfo(for: rawValue)
        else {
            return .mint
        }
        return banner.color
    }

    private var showsVideoPages: Bool {
        model.videoPages.count > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: URL(string: model.ownerFace)) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Circle()
                                    .fill(Color.gray)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.ownerName)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            if let follower = model.ownerFollowerCount,
                               let archiveCount = model.ownerArchiveCount
                            {
                                Text("\(VideoItem.formatCount(follower))粉丝  \(archiveCount)视频")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("—粉丝  —视频")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onOpenOwner(model.ownerMid, model.aid)
                    }

                    HStack {
                        ZStack {
                            Capsule(style: .continuous)
                                .fill(model.isOwnerFollowing ? .followedBackground : Color("BiliPink"))
                                .animation(.smooth(duration: 0.1), value: model.isOwnerFollowing)

                            Button(action: onToggleFollow) {
                                Text(model.isOwnerFollowing ? "已关注" : "关注")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(model.isOwnerFollowing ? .followedText : .white)
                            }
                            .frame(width: 65, height: 25)
                        }
                        .glassEffect(
                            .regular.interactive(),
                            in: .capsule
                        )
                        .frame(width: 65, height: 25)
                    }
                }

                if let fullSegmentBanner = model.fullSegmentBanner {
                    Text(fullSegmentBanner)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .glassEffect(
                            .regular.tint(fullSegmentBannerColor),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }

                Text(model.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onToggleExpand()
                    }

                // 播放量/弹幕量/投稿时间/在线人数
                HStack(spacing: 10) {
                    Label(VideoItem.formatCount(model.viewCount), systemImage: "play.fill")
                    Label(VideoItem.formatCount(model.danmakuCount), systemImage: "text.bubble.fill")
                    Text(VideoItem.formatTimestamp(model.pubdate))
                    if let onlineTotal = model.onlineTotal,
                       !onlineTotal.isEmpty,
                       Date().timeIntervalSince1970 >= TimeInterval(model.pubdate)
                    {
                        Label("\(onlineTotal)人在看", systemImage: "person.2.fill")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    onToggleExpand()
                }

                if model.isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.bvid)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onLongPressGesture {
#if canImport(UIKit)
                                UIPasteboard.general.string = model.bvid
#endif
                            }

                        if hasIntroDescription {
                            Text(model.introDescriptionText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .tint(Color("BiliPink"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .environment(\.openURL, OpenURLAction { url in
                                    onOpenIntroLink(url)
                                })
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VideoActionBar(
                    isLiked: model.isLiked,
                    isDisliked: model.isDisliked,
                    isCoined: model.isCoined,
                    userCoinCount: model.userCoinCount,
                    isFavorited: model.isFavorited,
                    isWatchLater: model.isWatchLater,
                    likeCount: model.likeCount,
                    coinCount: model.coinCount,
                    favoriteCount: model.favoriteCount,
                    shareCount: model.shareCount,
                    isLikeRequesting: model.isLikeRequesting,
                    isDislikeRequesting: model.isDislikeRequesting,
                    isCoinRequesting: model.isCoinRequesting,
                    isFavoriteRequesting: model.isFavoriteRequesting,
                    isWatchLaterRequesting: model.isWatchLaterRequesting,
                    onToggleLike: onToggleLike,
                    onTripleLike: onTripleLike,
                    onToggleDislike: onToggleDislike,
                    onCoin1: onCoin1,
                    onCoin2: onCoin2,
                    onToggleFavorite: onToggleFavorite,
                    onShare: onShare,
                    onShareWithTime: onShareWithTime,
                    onShareImage: onShareImage,
                    onLaterWatch: onLaterWatch
                )
                .padding(.top, 4)

                if showsVideoPages {
                    videoPageSection
                }

                if model.relatedIsLoading
                    || model.relatedError != nil
                    || !model.relatedVideos.isEmpty
                {
                    Divider()

                    HStack(spacing: 10) {

                        if model.relatedIsLoading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()
                    }

                    if let error = model.relatedError,
                       !model.relatedIsLoading,
                       model.relatedVideos.isEmpty
                    {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(model.relatedVideos) { item in
                                VideoCardSingleView(
                                    video: item,
                                    namespace: namespace,
                                    onTap: { onOpenRelatedVideo(item) }
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(.systemBackground))
    }

    private var videoPageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("视频选集")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(model.currentPageTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                Button(action: onOpenPageDrawer) {
                    Text("共\(model.videoPages.count)集")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.interactive(),
                    in: .capsule
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.videoPages) { page in
                        let isCurrent = page.cid == model.currentPageCID
                        Button {
                            onSelectPage(page)
                        } label: {
                            Text(page.part)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isCurrent ? Color("BiliPink") : .primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 120, height: 36, alignment: .leading)
                                .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            .regular.interactive(),
                            in: .capsule
                        )
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        onPageStripDragStateChange(true)
                    }
                    .onEnded { _ in
                        onPageStripDragStateChange(false)
                    }
            )
        }
        .padding(.top, 2)
    }
}

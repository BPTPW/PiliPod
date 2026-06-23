import SwiftUI

// 通过扩展 UINavigationController 强制开启侧滑返回手势
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 只有在导航栈内有超过一个视图时才允许滑动返回，防止在根视图滑动导致卡死
        return viewControllers.count > 1
    }
}

struct UserSpaceView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UserSpaceViewModel()
    @State private var selectedTab: UserSpaceTab = .video
    @State private var toastMessage: String?
    @Namespace private var topToolsGlass
    @Namespace private var videoHeroNamespace
    @State private var selectedVideo: VideoItem?
    @State private var selectedLiveRoom: LiveCardModel?

    let mid: Int
    let fromViewAid: Int?
    let onBack: (() -> Void)?

    init(mid: Int, fromViewAid: Int? = nil, onBack: (() -> Void)? = nil) {
        self.mid = mid
        self.fromViewAid = fromViewAid
        self.onBack = onBack
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header(topInset: topInset)
                        profileInfo
                        tabs
                    }
                }
                .background(Color(.systemBackground))
            }
            .overlay(alignment: .top) {
                topBar(topInset: topInset)
            }
            .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toast(message: $toastMessage)
        .navigationDestination(item: $selectedVideo) { video in
            if #available(iOS 18.0, *) {
                VideoDetailPage(
                    video: video,
                    namespace: videoHeroNamespace,
                    onBack: { selectedVideo = nil }
                )
                .navigationTransition(
                    .zoom(sourceID: "videoHero.\(video.bvid)", in: videoHeroNamespace)
                )
            } else {
                VideoDetailPage(
                    video: video,
                    namespace: videoHeroNamespace,
                    onBack: { selectedVideo = nil }
                )
            }
        }
        .navigationDestination(item: $selectedLiveRoom) { room in
            LivePlaybackPage(room: room)
        }
        .task {
            await viewModel.load(mid: mid, fromViewAid: fromViewAid)
        }
    }

    private func header(topInset: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let coverURL = viewModel.coverURL {
                CachedAsyncImage(url: coverURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(height: 80 + topInset)
        .overlay {
            Rectangle().fill(.black.opacity(0.15))
        }
        .clipped()
    }

    private func topBar(topInset: CGFloat) -> some View {
        HStack {
            Button {
                if let onBack {
                    onBack()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
                    // 修复二：增加 contentShape，保证整个 Frame 区域都可点击，防止被透明像素穿透
                    .contentShape(Rectangle())
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.interactive(),
                in: .circle
            )

            Spacer()

            GlassEffectContainer {
                HStack(spacing: 5) {
                    Button {} label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glass)
                    .glassEffectUnion(id: "UserSpaceTopTools", namespace: topToolsGlass)

                    Menu {
                        Button("拉黑") {}
                        Button("举报") {}
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glass)
                    .glassEffectUnion(id: "UserSpaceTopTools", namespace: topToolsGlass)
                }
            }
            .frame(height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset + 10)
    }

    private var profileInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                avatar
                    .offset(y: -40)
                    .padding(.bottom, -28)

                Spacer()

                VStack(spacing: 10) {
                    HStack {
                        stat(viewModel.fansText, "粉丝")
                        Spacer()
                        stat(viewModel.attentionText, "关注")
                        Spacer()
                        stat(viewModel.likesText, "获赞")
                    }

                    ZStack {
                        Capsule(style: .continuous)
                            .fill(viewModel.isFollowed ? .followedBackground : Color("BiliPink"))
                            .animation(.smooth(duration: 0.1), value: viewModel.isFollowed)
                            .frame(height: 32)

                        Button {
                            guard !viewModel.isFollowRequesting else { return }
                            Task {
                                do {
                                    try await viewModel.toggleFollow()
                                } catch {
                                    await MainActor.run {
                                        toastMessage = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Text(viewModel.isFollowed ? "已关注" : "关注")
                                .foregroundStyle(viewModel.isFollowed ? .followedText : .white)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                    }
                    .glassEffect(
                        .regular.interactive(),
                        in: .capsule
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 80)

            Text(viewModel.displayName)
                .font(.title3)
                .fontWeight(.bold)

            Text(viewModel.signature)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("UID: \(viewModel.uidText)  IP属地: \(viewModel.ipLocationText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var avatar: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let avatarURL = viewModel.avatarURL {
                    CachedAsyncImage(url: avatarURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Circle().fill(Color(.systemGray5))
                        }
                    }
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(.white, lineWidth: 3)
            }

            if viewModel.isLiveNow, let room = viewModel.liveRoomModel {
                Button {
                    selectedLiveRoom = room
                } label: {
                    Text("直播中")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                }
                .tint(.primary)
                .glassEffect(
                    .regular.interactive().tint(.biliPink),
                    in: .capsule
                )
                .offset(y: 12)
                .zIndex(1)
            }
        }
        .frame(width: 96, height: 108, alignment: .top)
    }

    private var tabs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("分区", selection: $selectedTab) {
                ForEach(UserSpaceTab.allCases, id: \.self) { tab in
                    Text(L10n.string(tab.rawValue)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if selectedTab == .video {
                postsTabContent
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .frame(height: 320)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var postsTabContent: some View {
        if viewModel.archiveIsLoading && viewModel.archiveVideos.isEmpty {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .frame(height: 200)
                .overlay {
                    ProgressView("加载投稿中…")
                }
        } else if let error = viewModel.archiveErrorMessage, viewModel.archiveVideos.isEmpty {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .frame(height: 200)
                .overlay {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                }
        } else if viewModel.archiveVideos.isEmpty {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .frame(height: 200)
                .overlay {
                    Text("还没有投稿内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.archiveVideos) { video in
                    VideoCardSingleView(
                        video: video,
                        namespace: videoHeroNamespace,
                        onTap: { selectedVideo = video }
                    )
                    .onAppear {
                        Task { await viewModel.loadMoreArchiveIfNeeded(current: video) }
                    }
                }

                if viewModel.archiveIsLoading && !viewModel.archiveVideos.isEmpty {
                    ProgressView()
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private func stat(_ value: String, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 54)
    }
}

private enum UserSpaceTab: String, CaseIterable {
    case home = "userSpace.home"
    case posts = "userSpace.posts"
    case video = "userSpaces.video"
}

#Preview {
    NavigationStack {
        UserSpaceView(mid: 2)
    }
}

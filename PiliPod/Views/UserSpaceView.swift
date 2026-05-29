import SwiftUI

struct UserSpaceView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UserSpaceViewModel()
    @State private var selectedTab: UserSpaceTab = .posts
    @Namespace private var topToolsGlass

    let mid: Int
    let fromViewAid: Int?

    init(mid: Int, fromViewAid: Int? = nil) {
        self.mid = mid
        self.fromViewAid = fromViewAid
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

                topBar(topInset: topInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
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
                AsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
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
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.interactive(),
                in: .circle
            )

            Spacer()

            GlassEffectContainer {
                HStack(spacing: 0) {
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
            .frame(height: 34)
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
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(viewModel.isFollowed ? .gray : Color("BiliPink"))
                            .animation(.smooth(duration: 0.1), value: viewModel.isFollowed)
                            .frame(height: 32)

                        Button {} label: {
                            Text(viewModel.isFollowed ? "已关注" : "关注")
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .buttonStyle(.plain)
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

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var avatar: some View {
        Group {
            if let avatarURL = viewModel.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle().fill(Color(.systemGray5))
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
    }

    private var tabs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("分区", selection: $selectedTab) {
                ForEach(UserSpaceTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 320)
                .overlay {
                    Text("\(selectedTab.rawValue)内容暂时留空")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    private func stat(_ value: String, _ title: String) -> some View {
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
    case home = "主页"
    case dynamic = "动态"
    case posts = "投稿"
}

#Preview {
    NavigationStack {
        UserSpaceView(mid: 2)
    }
}

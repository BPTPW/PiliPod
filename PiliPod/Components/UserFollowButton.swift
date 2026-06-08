import SwiftUI

struct UserFollowButton: View {
    let mid: Int
    var initialIsFollowing: Bool? = nil
    var shouldAutoLoadState = true

    @State private var isFollowing = false
    @State private var isStateLoading = true
    @State private var isRequesting = false
    @State private var toastMessage: String?

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(isFollowing ? .followedBackground : Color("BiliPink"))
                .animation(.smooth(duration: 0.1), value: isFollowing)

            Button {
                guard !isRequesting else { return }
                Task { await toggleFollow() }
            } label: {
                Group {
                    if isStateLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(isFollowing ? .followedText : .white)
                    } else {
                        Text(isFollowing ? "已关注" : "关注")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isFollowing ? .followedText : .white)
                    }
                }
                .frame(width: 65, height: 25)
            }
            .disabled(isRequesting || isStateLoading)
        }
        .glassEffect(
            .regular.interactive(),
            in: .capsule
        )
        .frame(width: 65, height: 25)
        .onAppear {
            if let initialIsFollowing {
                isFollowing = initialIsFollowing
            }
            if !shouldAutoLoadState {
                isStateLoading = false
            }
        }
        .task(id: mid) {
            guard shouldAutoLoadState else { return }
            await loadFollowState()
        }
        .toast(message: $toastMessage)
    }

    @MainActor
    private func loadFollowState() async {
        isStateLoading = true
        defer { isStateLoading = false }

        do {
            let stats = try await BiliAPI.shared.fetchUserCardStats(mid: mid)
            isFollowing = stats.following
        } catch {
            print("获取用户关注状态失败: \(error)")
        }
    }

    @MainActor
    private func toggleFollow() async {
        let wasFollowing = isFollowing
        let act = wasFollowing ? 2 : 1

        isRequesting = true
        isFollowing.toggle()

        do {
            try await BiliAPI.shared.modifyUserRelation(fid: mid, act: act)
        } catch {
            isFollowing = wasFollowing
            toastMessage = error.localizedDescription
        }

        isRequesting = false
    }
}

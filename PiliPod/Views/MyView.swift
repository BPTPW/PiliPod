//
//  MyView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct MyView: View {
    @StateObject private var viewModel = MyViewModel()
    @ObservedObject private var loginSession = LoginSession.shared
    @State private var showLoginSheet = false
    @State private var showHistory = false
    @State private var showWatchLater = false
    @State private var showOfflineCache = false
    @State private var followingRoute: MyFollowingRoute?

    var body: some View {
        NavigationStack {
            List {
                headerView
                quickActionRow
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                    } label: {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
            .task {
                await viewModel.loadUser()
            }
            .fullScreenCover(isPresented: $showLoginSheet) {
                LoginPageView()
            }
            .onReceive(loginSession.$isLogin) { isLogin in
                if isLogin {
                    Task {
                        await viewModel.loadUser()
                    }
                } else {
                    viewModel.user = nil
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
            .navigationDestination(isPresented: $showOfflineCache) {
                OfflineCacheView(initialPrefill: nil)
            }
            .navigationDestination(isPresented: $showWatchLater) {
                WatchLaterView()
            }
            .navigationDestination(item: $followingRoute) { route in
                FollowingListView(mid: route.mid)
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        Section {
            if let user = viewModel.user {
                NavigationLink {
                    UserSpaceView(mid: Int(user.mid))
                } label: {
                    HStack(spacing: 14) {
                        CachedAsyncImage(url: URL(string: user.face)) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(user.name)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Image(levelIconName(for: user))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 14)
                            }

                            Text("硬币 \(formattedMoney(user.money))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                ProgressView(value: experienceProgress(for: user))
                                    .tint(Color("BiliPink"))
                                    .progressViewStyle(.linear)

                                Text("\(user.levelInfo.currentExp)/\(maxExperienceText(for: user))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            } else {
                Group {
                    if loginSession.isLogin {
                        loggedOutHeader
                    } else {
                        Button {
                            showLoginSheet = true
                        } label: {
                            loggedOutHeader
                        }
                        .buttonStyle(.plain)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
            VStack {
                if let stat = viewModel.stat {
                    HStack {
                        Spacer()
                        statItem(value: stat.dynamicCount, title: L10n.string("my.posts"))
                        Spacer()
                        if let user = viewModel.user {
                            Button {
                                followingRoute = MyFollowingRoute(mid: user.mid)
                            } label: {
                                statItem(value: stat.following, title: L10n.string("my.following"))
                            }
                            .buttonStyle(.plain)
                        } else {
                            statItem(value: stat.following, title: L10n.string("my.following"))
                        }
                        Spacer()
                        statItem(value: stat.follower, title:  L10n.string("my.followers"))
                        Spacer()
                    }
                    .padding(.top, 2)
                } else {
                    HStack {
                        Spacer()
                        statItem(value: 0, title: L10n.string("my.posts"))
                        Spacer()
                        statItem(value: 0, title: L10n.string("my.following"))
                        Spacer()
                        statItem(value: 0, title: L10n.string("my.followers"))
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var loggedOutHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color(.systemGray3))
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(loginSession.isLogin ? "正在加载个人信息…" : "点击登录")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if !loginSession.isLogin {
                    Text("登录哔哩哔哩账号")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if !loginSession.isLogin {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var quickActionRow: some View {
        Section {
            HStack(spacing: 4) {
                quickActionButton(
                    title: L10n.string("离线缓存"),
                    systemImage: "square.and.arrow.down",
                    action: { showOfflineCache = true }
                )
                
                quickActionButton(
                    title: L10n.string("观看记录"),
                    systemImage: "memories",
                    action: { showHistory = true }
                )
                
                quickActionButton(
                    title: L10n.string("收藏"),
                    systemImage: "star",
                    action: { /* TODO */ }
                )

                quickActionButton(
                    title: L10n.string("稍后再看"),
                    systemImage: "clock.badge",
                    action: { showWatchLater = true }
                )
            }
        }
    }

    private func levelIconName(for user: UserCard) -> String {
        let level = min(max(user.levelInfo.currentLevel, 0), 6)
        if level == 6, user.isSeniorMember == 1 {
            return "LV6_Lightning"
        }
        return "LV\(level)"
    }

    private func maxExperienceText(for user: UserCard) -> String {
        if user.levelInfo.nextExp == "--" {
            return "--"
        }
        return user.levelInfo.nextExp
    }

    private func experienceProgress(for user: UserCard) -> Double {
        if user.levelInfo.nextExp == "--" {
            return 1
        }

        guard let nextExp = Double(user.levelInfo.nextExp) else {
            return 0
        }

        let minExp = Double(user.levelInfo.currentMin)
        let currentExp = Double(user.levelInfo.currentExp)
        let range = max(nextExp - minExp, 1)
        let progress = (currentExp - minExp) / range
        return min(max(progress, 0), 1)
    }

    private func formattedMoney(_ money: Double) -> String {
        if money.rounded() == money {
            return String(Int(money))
        }
        return money.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private func statItem(value: Int, title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
    }

    private func quickActionButton(title: String, systemImage: String) -> some View {
        quickActionButton(title: title, systemImage: systemImage, action: {})
    }

    private func quickActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MyView()
}

private struct MyFollowingRoute: Identifiable, Hashable {
    let mid: Int

    var id: Int { mid }
}

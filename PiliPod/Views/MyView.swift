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

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 顶部按钮
                HStack {
                    Spacer()
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .frame(width: 20, height: 20)
                            .padding(10)
                    }
                    .tint(.primary)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 30)
                .padding(.top, 10)

                headerView
                    .padding(.horizontal, 30)

                quickActionRow
                    .padding(.horizontal, 30)

                Spacer()

                VStack(spacing: 12) {
                    if loginSession.isLogin {
                        Button("退出登录") {
                            LoginImportService.clearLoginState()
                            viewModel.user = nil
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button("登录") {
                            showLoginSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
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
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
            .navigationDestination(isPresented: $showWatchLater) {
                WatchLaterView()
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if let user = viewModel.user {
            NavigationLink {
                UserSpaceView(mid: Int(user.mid))
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    AsyncImage(url: URL(string: user.face)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        Text(user.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        HStack(spacing: 12) {
                            Text("硬币 \(formattedMoney(user.money))")
                            Text("经验 \(user.levelInfo.currentExp)/\(maxExperienceText(for: user))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ProgressView(value: experienceProgress(for: user))
                            .tint(Color("BiliPink"))
                            .progressViewStyle(.linear)
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(loginSession.isLogin ? "正在加载个人信息…" : "当前未登录")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("导入登录 JSON 后即可同步账号状态。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        if let stat = viewModel.stat {
            HStack {
                Spacer()
                statItem(value: stat.dynamicCount, title: "动态")
                Spacer()
                statItem(value: stat.following, title: "关注")
                Spacer()
                statItem(value: stat.follower, title: "粉丝")
                Spacer()
            }
            .padding(.top, 2)
        } else {
            HStack {
                Spacer()
                statItem(value: 0, title: "动态")
                Spacer()
                statItem(value: 0, title: "关注")
                Spacer()
                statItem(value: 0, title: "粉丝")
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private var quickActionRow: some View {
        HStack(spacing: 12) {
            quickActionButton(
                title: "离线缓存",
                systemImage: "square.and.arrow.down"
            )

            quickActionButton(
                title: "观看记录",
                systemImage: "memories",
                action: { showHistory = true }
            )

            quickActionButton(
                title: "稍后再看",
                systemImage: "clock.badge",
                action: { showWatchLater = true }
            )
        }
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
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    MyView()
}

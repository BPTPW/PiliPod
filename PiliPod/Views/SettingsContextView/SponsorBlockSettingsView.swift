import SwiftUI

struct SponsorBlockSettingsContainerView: View {
    @State private var settings = SponsorBlockSettingsStore.load()

    var body: some View {
        SponsorBlockSettingsView(settings: $settings)
            .onAppear {
                var latest = SponsorBlockSettingsStore.load()
                SponsorBlockSettingsStore.ensureUserIDIfNeeded(for: &latest)
                settings = latest
            }
            .onChange(of: settings) { _, newValue in
                var updated = newValue.clamped()
                SponsorBlockSettingsStore.ensureUserIDIfNeeded(for: &updated)
                settings = updated
                SponsorBlockSettingsStore.save(updated)
            }
    }
}

private struct SponsorBlockSettingsView: View {
    @Binding var settings: SponsorBlockSettings

    @Environment(\.openURL) private var openURL

    @State private var serverStatus: SponsorBlockServerStatus = .idle
    @State private var userInfo: SponsorBlockUserInfo?
    @State private var isLoadingUserInfo = false
    @State private var userInfoErrorText: String?
    @State private var isEditingUserID = false
    @State private var draftUserID = ""

    private let footerText = "此功能追踪您跳过了哪些片段，让用户知道他们提交的片段帮助了多少人。同时点赞会作为依据，确保垃圾信息不会污染数据库。在您每次跳过片段时，我们都会向服务器发送一条消息。希望大家开启此项设置，以便得到更准确的统计数据。:)"

    var body: some View {
        Form {
            Section("服务器") {
                Button {
                    Task { await refreshServerStatus() }
                } label: {
                    HStack {
                        Text("服务器状态")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(serverStatus.text)
                            .foregroundStyle(serverStatus.color)
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                Toggle("跳过次数统计跟踪", isOn: $settings.shouldTrackSkipCount)
                    .tint(Color("BiliPink"))
            } footer: {
                Text(footerText)
            }

            Section("您的数据") {
                if isLoadingUserInfo {
                    HStack {
                        ProgressView()
                        Text("正在加载")
                            .foregroundStyle(.secondary)
                    }
                } else if let userInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("您提交了 \(userInfo.segmentCount) 片段")
                        Text("为大家节省了 \(formatCount(userInfo.viewCount)) 片段")
                        Text("(\(formatLifeTime(userInfo.minutesSaved)) 的生命)")
                            .foregroundStyle(.secondary)
                    }
                } else if let userInfoErrorText {
                    Text(userInfoErrorText)
                        .foregroundStyle(.secondary)
                } else {
                    Text("暂无数据")
                        .foregroundStyle(.secondary)
                }
            }

            Section("片段处理方式") {
                ForEach(SponsorBlockCategory.allCases) { category in
                    SponsorBlockCategoryBehaviorRow(
                        category: category,
                        behavior: behaviorBinding(for: category)
                    )
                }
            }

            Section {
                Button {
                    draftUserID = settings.userID ?? SponsorBlockSettingsStore.generateUserID()
                    isEditingUserID = true
                } label: {
                    HStack {
                        Text("用户ID")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(settings.userID ?? "未生成")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("用户")
            } footer: {
                VStack{
                    Text("私人ID可以自行设置，要求至少为30个字符长度的纯字符串，首次启动时会生成随机字符串。")
                    Text("私人ID应该被保密。如果他人获得了你的私人ID，他就可以冒充您。服务器不会保存任何私人ID，如果你不幸弄丢了私人ID，那就再也没办法找回了。")
                }
            }

            Section {
                Button {
                    guard let url = URL(string: "https://github.com/hanydd/BilibiliSponsorBlock") else { return }
                    openURL(url)
                } label: {
                    Text("关于空降助手")
                }
            }
        }
        .navigationTitle("空降助手设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshServerStatus()
            await refreshUserInfoIfNeeded()
        }
        .onChange(of: settings.userID) { _, _ in
            Task { await refreshUserInfoIfNeeded() }
        }
        .sheet(isPresented: $isEditingUserID) {
            NavigationStack {
                Form {
                    Section {
                        TextField("用户ID", text: $draftUserID)
                            .textInputAutocapitalization(.never)
#if canImport(UIKit)
                            .autocorrectionDisabled()
#endif
                    } footer: {
                        VStack{
                            Text("私人ID可以自行设置，要求至少为30个字符长度的纯字符串。")
                            Text("私人ID应该被保密。如果他人获得了你的私人ID，他就可以冒充您。服务器不会保存任何私人ID，如果你不幸弄丢了私人ID，那就再也没办法找回了。")
                        }
                    }
                }
                .navigationTitle("编辑用户ID")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") {
                            isEditingUserID = false
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("随机") {
                            draftUserID = SponsorBlockSettingsStore.generateUserID()
                        }
                        Button("保存") {
                            let filtered = draftUserID.filter { character in
                                character.isASCII && (character.isLetter || character.isNumber)
                            }
                            let trimmed = String(filtered.prefix(36))
                            guard !trimmed.isEmpty else { return }
                            settings.userID = trimmed
                            isEditingUserID = false
                        }
                    }
                }
            }
        }
    }

    private func behaviorBinding(for category: SponsorBlockCategory) -> Binding<SponsorBlockSegmentBehavior> {
        Binding(
            get: { settings.behavior(for: category) },
            set: { settings.setBehavior($0, for: category) }
        )
    }

    @MainActor
    private func refreshServerStatus() async {
        serverStatus = .loading
        serverStatus = await SponsorBlockAPI.fetchStatus()
    }

    @MainActor
    private func refreshUserInfoIfNeeded() async {
        guard let userID = settings.userID, !userID.isEmpty else {
            userInfo = nil
            userInfoErrorText = "暂无用户ID"
            return
        }

        isLoadingUserInfo = true
        userInfoErrorText = nil

        do {
            userInfo = try await SponsorBlockAPI.fetchUserInfo(userID: userID)
        } catch {
            userInfo = nil
            userInfoErrorText = "加载失败"
        }

        isLoadingUserInfo = false
    }

    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formatLifeTime(_ minutes: Double) -> String {
        let totalMinutes = max(0, Int(minutes.rounded()))
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        return "\(hours)小时\(remainingMinutes)分钟"
    }
}

private struct SponsorBlockCategoryBehaviorRow: View {
    let category: SponsorBlockCategory
    @Binding var behavior: SponsorBlockSegmentBehavior

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(category.color)
                .frame(width: 18, height: 18)

            Text(category.title)
                .foregroundStyle(.primary)

            Spacer()

            Picker(category.title, selection: $behavior) {
                ForEach(SponsorBlockSegmentBehavior.allCases, id: \.self) { option in
                    Text(option.title)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

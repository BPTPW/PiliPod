import SwiftUI

struct SettingsView: View {
    @ObservedObject private var loginSession = LoginSession.shared

    @State private var accountError: String?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AccountSettingsView()
                } label: {
                    SettingsCategoryRow(title: "账号与隐私", systemImage: "person.2.fill", tint: .purple)
                }
            }
            Section {
                NavigationLink {
                    RecommendSettingsView()
                } label: {
                    SettingsCategoryRow(
                        title: "推荐流",
                        systemImage: "square.stack.3d.up.fill",
                        tint: .pink
                    )
                }

                NavigationLink {
                    AudioVideoSettingsContainerView()
                } label: {
                    SettingsCategoryRow(
                        title: "音视频",
                        systemImage: "speaker.wave.2.fill",
                        tint: .orange
                    )
                }

                NavigationLink {
                    PlayerSettingsContainerView()
                } label: {
                    SettingsCategoryRow(
                        title: "播放器",
                        systemImage: "play.rectangle.fill",
                        tint: .blue
                    )
                }

                NavigationLink {
                    AppDanmakuSettingsContainerView()
                } label: {
                    SettingsCategoryRow(
                        title: "弹幕",
                        imageName: "DanmakuSetting",
                        tint: .green
                    )
                }

                NavigationLink {
                    CacheManagementView()
                } label: {
                    SettingsCategoryRow(
                        title: "缓存管理",
                        systemImage: "internaldrive.fill",
                        tint: .brown
                    )
                }

                NavigationLink {
                    OtherSettingsView()
                } label: {
                    SettingsCategoryRow(
                        title: "其他设置",
                        systemImage: "ellipsis.circle.fill",
                        tint: .teal
                    )
                }

                NavigationLink {
                    AboutView()
                } label: {
                    SettingsCategoryRow(
                        title: "关于",
                        systemImage: "info.circle.fill",
                        tint: .gray
                    )
                }
            }

            Section {
                Button {
                    do { try LoginImportService.clearLoginState() }
                    catch { accountError = error.localizedDescription }
                } label: {
                    SettingsCategoryRow(
                        title: "退出登录",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        tint: .red
                    )
                }
                .tint(.red)
                .disabled(!loginSession.isLogin)
            }
        }
        .alert("操作失败", isPresented: Binding(get: { accountError != nil }, set: { if !$0 { accountError = nil } })) {
            Button("确定") { accountError = nil }
        } message: { Text(accountError ?? "") }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
}

#Preview {
    SettingsView()
}

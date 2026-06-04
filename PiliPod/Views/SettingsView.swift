import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
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
                    SettingsPlaceholderView(title: "播放器", systemImage: "play.rectangle.fill")
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
                        systemImage: "text.bubble.fill",
                        tint: .green
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
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
}

#Preview {
    SettingsView()
}

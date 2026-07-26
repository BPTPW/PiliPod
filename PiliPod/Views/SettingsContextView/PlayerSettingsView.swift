import SwiftUI

struct PlayerSettingsContainerView: View {
    @State private var settings = AudioVideoSettingsStore.load()

    var body: some View {
        PlayerSettingsView(settings: $settings)
            .onAppear {
                settings = AudioVideoSettingsStore.load()
            }
            .onChange(of: settings) { _, newValue in
                let clamped = newValue.clamped()
                settings = clamped
                AudioVideoSettingsStore.save(clamped)
            }
    }
}

private struct PlayerSettingsView: View {
    @Binding var settings: AudioVideoSettings
    private let defaultSettings = AudioVideoSettings()

    var body: some View {
        Form {
            Section("播放器内核") {
                Picker("播放器内核", selection: $settings.playerCore) {
                    ForEach(PlayerCore.allCases, id: \.self) { core in
                        Text(core.title).tag(core)
                    }
                }
            }
            Section {
                Toggle("视频后台播放", isOn: $settings.allowsBackgroundPlayback)
                    .tint(Color("BiliPink"))
                Toggle("直播后台播放", isOn: $settings.allowsLiveBackgroundPlayback)
                    .tint(Color("BiliPink"))
            } header: {
                Text("后台播放")
            }
        }
        .navigationTitle("播放器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    settings.playerCore = defaultSettings.playerCore
                    settings.allowsBackgroundPlayback = defaultSettings.allowsBackgroundPlayback
                    settings.allowsLiveBackgroundPlayback = defaultSettings.allowsLiveBackgroundPlayback
                }
            }
        }
    }
}

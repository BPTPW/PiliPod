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
            Section {
                Toggle("视频后台播放", isOn: $settings.allowsBackgroundPlayback)
                    .tint(Color("BiliPink"))
            } footer: {
                Text("开启后切到后台时继续播放。关闭后会在进入后台时暂停，并在回到前台后仅恢复这次因切后台而自动暂停的播放。")
            }
        }
        .navigationTitle("播放器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    settings.allowsBackgroundPlayback = defaultSettings.allowsBackgroundPlayback
                }
            }
        }
    }
}

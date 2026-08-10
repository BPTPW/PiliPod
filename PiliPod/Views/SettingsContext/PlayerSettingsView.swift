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
    private var supportsPictureInPicture: Bool { settings.playerCore == .avPlayer }
    private var supportsAmbientMode: Bool { settings.playerCore == .avPlayer }

    var body: some View {
        Form {
            Section {
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
            Section {
                Toggle("视频小窗播放", isOn: $settings.allowsVideoPictureInPicture)
                    .tint(Color("BiliPink"))
                    .disabled(!supportsPictureInPicture)
                Toggle("直播小窗播放", isOn: $settings.allowsLivePictureInPicture)
                    .tint(Color("BiliPink"))
                    .disabled(!supportsPictureInPicture)
            } header: {
                Text("画中画")
            } footer: {
                if !supportsPictureInPicture {
                    Text("画中画仅支持 AVPlayer 内核。")
                }
            }
            Section {
                Toggle("氛围模式", isOn: $settings.ambientModeEnabled)
                    .tint(Color("BiliPink"))
                    .disabled(!supportsAmbientMode)
                Picker("每秒采样频率", selection: $settings.ambientSamplingRate) {
                    ForEach(AmbientSamplingRate.allCases, id: \.self) { rate in
                        Text(rate.title).tag(rate)
                    }
                }
                .disabled(!supportsAmbientMode || !settings.ambientModeEnabled)
                Picker("渐变速度", selection: $settings.ambientGradientSpeed) {
                    ForEach(AmbientGradientSpeed.allCases, id: \.self) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                .disabled(!supportsAmbientMode || !settings.ambientModeEnabled)
            } header: {
                Text("显示效果")
            } footer: {
                if supportsAmbientMode {
                    Text("全屏播放时，根据视频画面颜色动态填充视频周围空白区域，带来沉浸式体验。较高的采样率可能会导致更多的性能开销。")
                } else {
                    Text("氛围模式仅支持 AVPlayer 内核。")
                }
            }
            Section {
                Picker("进度条样式", selection: $settings.videoProgressBarStyle) {
                    ForEach(VideoProgressBarStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
            }
            Section {
                Picker("观看记录上报间隔", selection: $settings.historyReportInterval) {
                    ForEach(AudioVideoSettings.supportedHistoryReportIntervals, id: \.self) { interval in
                        Text("\(interval)s").tag(interval)
                    }
                }
            }
        }
        .navigationTitle("播放器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    settings.playerCore = defaultSettings.playerCore
                    settings.historyReportInterval = defaultSettings.historyReportInterval
                    settings.allowsBackgroundPlayback = defaultSettings.allowsBackgroundPlayback
                    settings.allowsLiveBackgroundPlayback = defaultSettings.allowsLiveBackgroundPlayback
                    settings.allowsVideoPictureInPicture = defaultSettings.allowsVideoPictureInPicture
                    settings.allowsLivePictureInPicture = defaultSettings.allowsLivePictureInPicture
                    settings.ambientModeEnabled = defaultSettings.ambientModeEnabled
                    settings.ambientSamplingRate = defaultSettings.ambientSamplingRate
                    settings.ambientGradientSpeed = defaultSettings.ambientGradientSpeed
                    settings.videoProgressBarStyle = defaultSettings.videoProgressBarStyle
                }
            }
        }
    }
}

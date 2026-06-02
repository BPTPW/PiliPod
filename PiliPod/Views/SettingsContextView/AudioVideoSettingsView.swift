import SwiftUI

struct AudioVideoSettingsContainerView: View {
    @State private var settings = AudioVideoSettingsStore.load()
    @State private var autosyncText = String(AudioVideoSettingsStore.load().autosync)

    var body: some View {
        AudioVideoSettingsView(settings: $settings, autosyncText: $autosyncText)
            .onAppear {
                let latest = AudioVideoSettingsStore.load()
                settings = latest
                autosyncText = String(latest.autosync)
            }
            .onChange(of: settings) { _, newValue in
                let clamped = newValue.clamped()
                settings = clamped
                autosyncText = String(clamped.autosync)
                AudioVideoSettingsStore.save(clamped)
            }
    }
}

private struct AudioVideoSettingsView: View {
    @Binding var settings: AudioVideoSettings
    @Binding var autosyncText: String

    private let defaultSettings = AudioVideoSettings()

    var body: some View {
        Form {
            Section {
                Toggle("硬件解码", isOn: $settings.hardwareDecodingEnabled)
                    .tint(Color("BiliPink"))
            } header: {
                Text("解码")
            } footer: {
                Text("如果遇到播放异常请关闭。")
            }

            Section("画质") {
                NavigationLink {
                    ChoiceListView(
                        title: "默认画质",
                        options: PreferredVideoQuality.allCases,
                        selection: $settings.defaultQuality,
                        titleFor: \.title
                    )
                } label: {
                    selectionRow(title: "默认画质", value: settings.defaultQuality.title)
                }

                NavigationLink {
                    ChoiceListView(
                        title: "移动网络默认画质",
                        options: PreferredVideoQuality.allCases,
                        selection: $settings.cellularDefaultQuality,
                        titleFor: \.title
                    )
                } label: {
                    selectionRow(title: "移动网络默认画质", value: settings.cellularDefaultQuality.title)
                }
            }

            Section {
                NavigationLink {
                    ChoiceListView(
                        title: "缓冲大小",
                        options: VideoBufferSizeOption.allCases,
                        selection: $settings.bufferSize,
                        titleFor: \.title
                    )
                } label: {
                    selectionRow(title: "缓冲大小", value: settings.bufferSize.title)
                }
            } header: {
                Text("缓存")
            } footer: {
                Text("非自动模式下会同时调整 demuxer-max-bytes 和 demuxer-max-back-bytes。")
            }

            Section {
                NavigationLink {
                    ChoiceListView(
                        title: "首选编码格式",
                        options: PreferredCodecOption.allCases,
                        selection: $settings.preferredCodec,
                        titleFor: \.title
                    )
                } label: {
                    selectionRow(title: "首选编码格式", value: settings.preferredCodec.title)
                }
            } header: {
                Text("编码")
            } footer: {
                Text("所选编码不可用时会自动回退到其他可用编码。")
            }

            Section {
                HStack {
                    Text("自动同步")
                    Spacer()
                    TextField("0", text: $autosyncText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 120)
                        .onChange(of: autosyncText) { _, newValue in
                            let digits = newValue.filter(\.isNumber)
                            if digits != newValue {
                                autosyncText = digits
                                return
                            }

                            settings.autosync = Int(digits) ?? 0
                        }
                }

                NavigationLink {
                    ChoiceListView(
                        title: "视频同步",
                        options: MPVVideoSyncOption.allCases,
                        selection: $settings.videoSync,
                        titleFor: \.title
                    )
                } label: {
                    selectionRow(title: "视频同步", value: settings.videoSync.title)
                }
            } header: {
                Text("同步")
            } footer: {
                VStack(alignment: .leading){
                    Text("• 自动同步: mpv的--autosync")
                    Text("• 视频同步: mpv的--video-sync")
                }
            }
        }
        .navigationTitle("音视频")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    settings = defaultSettings
                    autosyncText = String(defaultSettings.autosync)
                }
            }
        }
    }

    private func selectionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

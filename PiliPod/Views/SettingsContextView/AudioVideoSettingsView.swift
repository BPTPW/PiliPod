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
    private let hugeBufferWarningText = "设置为超大后会显著增大播放器缓存上限，并尽量预取更多视频内容来尽可能保持播放流畅度，这将造成较多的网络和存储消耗。只建议在网络环境不稳定时使用。"

    private var usesAVPlayer: Bool { settings.playerCore == .avPlayer }
    private var bufferWarningText: String {
        usesAVPlayer
            ? "超大将请求以前向缓冲覆盖点播视频总时长；系统仍可能因内存压力缩短实际缓存。"
            : hugeBufferWarningText
    }

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

            Section("视频画质") {
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

            Section("直播画质") {
                NavigationLink {
                    ChoiceListView(
                        title: "直播默认画质",
                        options: PreferredLiveQuality.allCases,
                        selection: $settings.liveDefaultQuality,
                        titleFor: \.title
                    )
                } label: {
                    selectionRow(title: "直播默认画质", value: settings.liveDefaultQuality.title)
                }

                NavigationLink {
                    ChoiceListView(
                        title: "移动网络默认画质",
                        options: PreferredLiveQuality.allCases,
                        selection: $settings.cellularLiveDefaultQuality,
                        titleFor: \.title
                    )
                } label: {
                    selectionRow(title: "移动网络默认画质", value: settings.cellularLiveDefaultQuality.title)
                }
            }

            Section {
                NavigationLink {
                    BufferSizeChoiceListView(
                        selection: $settings.bufferSize,
                        warningText: bufferWarningText,
                        usesAVPlayer: usesAVPlayer
                    )
                } label: {
                    selectionRow(
                        title: "缓冲大小",
                        value: usesAVPlayer ? settings.bufferSize.avPlayerTitle : settings.bufferSize.title
                    )
                }
            } header: {
                Text("缓存")
            } footer: {
                if settings.bufferSize == .huge {
                    Text(bufferWarningText)
                        .foregroundStyle(.red)
                }
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
                Toggle("增强 HDR 视频显示", isOn: $settings.highDynamicRangeEnabled)
                    .tint(Color("BiliPink"))
                    .disabled(usesAVPlayer)
                    .onChange(of: settings.highDynamicRangeEnabled) { _, isEnabled in
                        if isEnabled {
                            settings.prefersEDROutput = true
                            if settings.hdrToneMapping == .clip {
                                settings.hdrToneMapping = .auto
                            }
                        }
                    }
            } header: {
                Text("高动态范围")
            } footer: {
                if usesAVPlayer {
                    Text("仅在MPVKit内核下支持设置。AVPlayer支持HDR与杜比视界。")
                } else {
                    Text("在支持的设备上，为 HDR、杜比视界等高动态视频启用更明亮的高光和更宽的色域。关闭后会按普通SDR视频方式显示。")
                }
            }

            Section {
                Group {
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
                }
                .disabled(usesAVPlayer)
            }
            header: {
                Text("同步")
            } footer: {
                if usesAVPlayer {
                    Text("仅在MPVKit内核下支持设置。")
                } else {
                    VStack(alignment: .leading) {
                        Text("• 自动同步: mpv的--autosync")
                        Text("• 视频同步: mpv的--video-sync")
                    }
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

private struct BufferSizeChoiceListView: View {
    @Binding var selection: VideoBufferSizeOption

    let warningText: String
    let usesAVPlayer: Bool

    @State private var pendingSelection: VideoBufferSizeOption?
    @State private var previousSelection: VideoBufferSizeOption?
    @State private var showsHugeConfirmation = false

    var body: some View {
        List {
            ForEach(VideoBufferSizeOption.allCases, id: \.self) { option in
                Button {
                    handleSelection(option)
                } label: {
                    HStack {
                        Text(usesAVPlayer ? option.avPlayerTitle : option.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color("BiliPink"))
                        }
                    }
                }
                .tint(.primary)
            }
        }
        .navigationTitle("缓冲大小")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认使用超大缓冲", isPresented: $showsHugeConfirmation) {
            Button("继续使用") {
                selection = .huge
                pendingSelection = nil
                previousSelection = nil
            }
            Button("取消", role: .cancel) {
                if let previousSelection {
                    selection = previousSelection
                }
                pendingSelection = nil
                previousSelection = nil
            }
        } message: {
            Text(warningText)
        }
    }

    private func handleSelection(_ option: VideoBufferSizeOption) {
        guard option == .huge else {
            pendingSelection = nil
            previousSelection = nil
            showsHugeConfirmation = false
            selection = option
            return
        }

        guard selection != .huge else { return }
        previousSelection = selection
        pendingSelection = option
        showsHugeConfirmation = true
    }
}

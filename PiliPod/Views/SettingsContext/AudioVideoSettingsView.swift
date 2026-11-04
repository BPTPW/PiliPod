import SwiftUI

struct AudioVideoSettingsContainerView: View {
    @State private var settings = AudioVideoSettingsStore.load()

    var body: some View {
        AudioVideoSettingsView(settings: $settings)
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

private struct AudioVideoSettingsView: View {
    @Binding var settings: AudioVideoSettings

    private let defaultSettings = AudioVideoSettings()

    var body: some View {
        Form {
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

            Section("音频") {
                Toggle("默认打开杜比全景声", isOn: $settings.defaultDolbyAudioEnabled)
                    .tint(Color("BiliPink"))
            }

            Section {
                NavigationLink {
                    BufferSizeChoiceListView(
                        selection: $settings.bufferSize,
                        warningText: "超大将请求以前向缓冲覆盖点播视频总时长；系统仍可能因内存压力缩短实际缓存。"
                    )
                } label: {
                    selectionRow(title: "缓冲大小", value: settings.bufferSize.avPlayerTitle)
                }
            } footer: {
                if settings.bufferSize == .huge {
                    Text("超大将请求以前向缓冲覆盖点播视频总时长；系统仍可能因内存压力缩短实际缓存。")
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
            } footer: {
                Text("所选编码不可用时会自动回退到其他可用编码。")
            }

            Section {
                NavigationLink {
                    PlaybackCDNRouteSettingsView(
                        selection: $settings.playbackCDNRoute,
                        testValidity: $settings.cdnConnectivityTestValidity
                    )
                } label: {
                    selectionRow(title: "CDN 线路", value: settings.playbackCDNRoute.title)
                }
            }

            Section {
                Toggle("增强 HDR 视频显示", isOn: $settings.highDynamicRangeEnabled)
                    .tint(Color("BiliPink"))
                    .onChange(of: settings.highDynamicRangeEnabled) { _, isEnabled in
                        if isEnabled {
                            settings.prefersEDROutput = true
                            if settings.hdrToneMapping == .clip {
                                settings.hdrToneMapping = .auto
                            }
                        }
                    }
            } footer: {
                Text("在支持的设备上，为 HDR、杜比视界等高动态视频启用更明亮的高光和更宽的色域。关闭后会按普通SDR视频方式显示。")
            }
        }
        .navigationTitle("音视频")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    settings = defaultSettings
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
                        Text(option.avPlayerTitle)
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

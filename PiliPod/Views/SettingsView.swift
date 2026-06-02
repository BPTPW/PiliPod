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

private struct AudioVideoSettingsContainerView: View {
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
            Section("解码") {
                Toggle("开启硬件解码", isOn: $settings.hardwareDecodingEnabled)
                    .tint(Color("BiliPink"))
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
                Text("默认优先 HEVC；所选编码不可用时会自动回退到其他可用编码。")
            }

            Section("同步") {
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

private struct RecommendSettingsView: View {
    @State private var selectedSource = RecommendSettingsStore.loadSource()

    var body: some View {
        Form {
            Section {
                Picker("推荐来源", selection: $selectedSource) {
                    ForEach(RecommendAPIMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text("修改后会在下次手动刷新首页推荐流或重新启动应用后生效。")
            }
        }
        .navigationTitle("推荐流")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedSource = RecommendSettingsStore.loadSource()
        }
        .onChange(of: selectedSource) { _, newValue in
            RecommendSettingsStore.saveSource(newValue)
        }
    }
}

struct AppDanmakuSettingsContainerView: View {
    @State private var config = DanmakuConfigStore.load()

    var body: some View {
        AppDanmakuSettingsView(config: $config)
            .onAppear {
                config = DanmakuConfigStore.load()
            }
            .onChange(of: config) { _, newValue in
                config = newValue.clamped()
                DanmakuConfigStore.save(config)
            }
    }
}

private struct AppDanmakuSettingsView: View {
    @Binding var config: DanmakuEngineConfig

    private let defaultConfig = DanmakuEngineConfig()

    var body: some View {
        Form {
            Section("开关") {
                Toggle("显示弹幕", isOn: $config.isEnabled)
                    .tint(Color("BiliPink"))
            }

            Section("屏蔽") {
                settingStepperRow(
                    title: "屏蔽等级",
                    valueText: "\(config.blockLevel)",
                    onReset: { config.blockLevel = defaultConfig.blockLevel }
                ) {
                    Stepper(
                        value: Binding(
                            get: { config.blockLevel },
                            set: { config.blockLevel = $0 }
                        ),
                        in: 0 ... 10
                    ) {
                        EmptyView()
                    }
                    .labelsHidden()
                }

                Toggle("屏蔽滚动弹幕", isOn: $config.blockScroll)
                    .tint(Color("BiliPink"))
                Toggle("屏蔽顶部弹幕", isOn: $config.blockTop)
                    .tint(Color("BiliPink"))
                Toggle("屏蔽底部弹幕", isOn: $config.blockBottom)
                    .tint(Color("BiliPink"))
                Toggle("屏蔽彩色弹幕", isOn: $config.blockColorful)
                    .tint(Color("BiliPink"))
            }

            Section("显示") {
                percentageSliderRow(
                    title: "显示区域",
                    value: Binding(
                        get: { config.topRegionRatio },
                        set: {
                            config.topRegionRatio = $0
                            config.bottomRegionRatio = $0
                        }
                    ),
                    range: 0.1 ... 1.0,
                    step: 0.1,
                    onReset: {
                        config.topRegionRatio = defaultConfig.topRegionRatio
                        config.bottomRegionRatio = defaultConfig.bottomRegionRatio
                    }
                )

                percentageSliderRow(
                    title: "不透明度",
                    value: $config.opacity,
                    range: 0 ... 1,
                    step: 0.1,
                    onReset: { config.opacity = defaultConfig.opacity }
                )

                percentageSliderRow(
                    title: "字体大小",
                    value: $config.fontScale,
                    range: 0.5 ... 2.5,
                    step: 0.1,
                    onReset: { config.fontScale = defaultConfig.fontScale }
                )

                percentageSliderRow(
                    title: "全屏字体大小",
                    value: $config.fullscreenFontScale,
                    range: 0.5 ... 2.5,
                    step: 0.1,
                    onReset: { config.fullscreenFontScale = defaultConfig.fullscreenFontScale }
                )

                settingSliderRow(
                    title: "字体粗细",
                    valueText: "\(config.fontWeightValue)",
                    onReset: { config.fontWeightValue = defaultConfig.fontWeightValue }
                ) {
                    Slider(
                        value: Binding(
                            get: { Double(config.fontWeightValue) },
                            set: { config.fontWeightValue = Int($0.rounded()) }
                        ),
                        in: 1 ... 9,
                        step: 1
                    )
                    .tint(Color("BiliPink"))
                }

                settingSliderRow(
                    title: "描边粗细",
                    valueText: String(format: "%.1f", config.strokeWidth),
                    onReset: { config.strokeWidth = defaultConfig.strokeWidth }
                ) {
                    Slider(value: $config.strokeWidth, in: 0 ... 2, step: 0.1)
                        .tint(Color("BiliPink"))
                }

                settingSliderRow(
                    title: "弹幕行高",
                    valueText: String(format: "%.1f", config.lineHeightMultiplier),
                    onReset: { config.lineHeightMultiplier = defaultConfig.lineHeightMultiplier }
                ) {
                    Slider(value: $config.lineHeightMultiplier, in: 1 ... 3, step: 0.1)
                        .tint(Color("BiliPink"))
                }
            }

            Section("行为") {
                Toggle("海量弹幕允许重叠", isOn: $config.allowOverlapWhenMassive)
                    .tint(Color("BiliPink"))
                Toggle("全部按滚动弹幕显示", isOn: $config.forceAllScroll)
                    .tint(Color("BiliPink"))

                settingSliderRow(
                    title: "滚动弹幕时长",
                    valueText: "\(Int(config.scrollDuration.rounded())) 秒",
                    onReset: { config.scrollDuration = defaultConfig.scrollDuration }
                ) {
                    Slider(value: $config.scrollDuration, in: 1 ... 30, step: 1)
                        .tint(Color("BiliPink"))
                }

                settingSliderRow(
                    title: "静态弹幕时长",
                    valueText: "\(Int(config.staticDuration.rounded())) 秒",
                    onReset: { config.staticDuration = defaultConfig.staticDuration }
                ) {
                    Slider(value: $config.staticDuration, in: 1 ... 30, step: 1)
                        .tint(Color("BiliPink"))
                }
            }
        }
        .navigationTitle("弹幕")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    config = defaultConfig
                }
            }
        }
    }

    private func percentageSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        onReset: @escaping () -> Void
    ) -> some View {
        settingSliderRow(
            title: title,
            valueText: "\(Int((value.wrappedValue * 100).rounded()))%",
            onReset: onReset
        ) {
            Slider(value: value, in: range, step: step)
                .tint(Color("BiliPink"))
        }
    }

    private func settingStepperRow(
        title: String,
        valueText: String,
        onReset: @escaping () -> Void,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            control()

            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func settingSliderRow(
        title: String,
        valueText: String,
        onReset: @escaping () -> Void,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(valueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            control()
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsCategoryRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 28, height: 28)

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct SettingsPlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("敬请期待")
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChoiceListView<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let titleFor: KeyPath<Option, String>

    var body: some View {
        List {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack {
                        Text(option[keyPath: titleFor])
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

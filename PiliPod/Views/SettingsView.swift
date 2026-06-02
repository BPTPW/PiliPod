import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsPlaceholderView(title: "推荐流", systemImage: "square.stack.3d.up.fill")
                } label: {
                    SettingsCategoryRow(
                        title: "推荐流",
                        systemImage: "square.stack.3d.up.fill",
                        tint: .pink
                    )
                }

                NavigationLink {
                    SettingsPlaceholderView(title: "音视频", systemImage: "speaker.wave.2.fill")
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
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
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

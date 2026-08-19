import SwiftUI

struct SubtitleSettingsContainerView: View {
    @State private var settings = SubtitleSettingsStore.load()

    var body: some View {
        SubtitleSettingsView(settings: $settings)
            .onAppear { settings = SubtitleSettingsStore.load() }
            .onChange(of: settings) { _, newValue in
                let value = newValue.clamped()
                settings = value
                SubtitleSettingsStore.save(value)
            }
    }
}

private struct SubtitleSettingsView: View {
    @Binding var settings: SubtitleSettings
    private let defaultSettings = SubtitleSettings()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Form {
                    Section {
                        Toggle("默认显示字幕", isOn: $settings.defaultShowSubtitles)
                            .tint(Color("BiliPink"))
                    } footer: {
                        Text("在打开视频时自动显示第一个非AI生成的字幕（若有）")
                    }

                    Section("样式") {
                        Picker("文本颜色", selection: $settings.textColor) {
                            ForEach(SubtitleColorOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .disabled(settings.usesGlassStyle)

                        Picker("背景颜色", selection: $settings.backgroundColor) {
                            ForEach(SubtitleColorOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .disabled(settings.usesGlassStyle)

                        VStack(alignment: .leading) {
                            HStack {
                                Text("背景透明度")
                                Spacer()
                                Text("\(Int((settings.backgroundOpacity * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.backgroundOpacity, in: 0 ... 1, step: 0.01)
                                .disabled(settings.usesGlassStyle)
                        }

                        VStack(alignment: .leading) {
                            HStack {
                                Text("背景圆角大小")
                                Spacer()
                                Text("\(Int(settings.cornerRadius.rounded()))")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.cornerRadius, in: 0 ... 20, step: 1)
                        }

                        Toggle("使用玻璃样式", isOn: $settings.usesGlassStyle)
                            .tint(Color("BiliPink"))
                    }
                }
                .frame(height: 530)
                .scrollDisabled(true)

                VStack(spacing: 12) {
                SubtitlePreviewImage(name: "PreviewImageLight", settings: settings)
                SubtitlePreviewImage(name: "PreviewImageDark", settings: settings)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationTitle("字幕设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") { settings = defaultSettings }
            }
        }
    }
}

private struct SubtitlePreviewImage: View {
    let name: String
    let settings: SubtitleSettings

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(name)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("字幕显示效果")
                .font(.system(size: 15, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(settings.usesGlassStyle ? .primary : settings.textColor.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .modifier(SubtitleBackgroundModifier(settings: settings))
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SubtitleBackgroundModifier: ViewModifier {
    let settings: SubtitleSettings

    func body(content: Content) -> some View {
        if settings.usesGlassStyle {
            content.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
            )
        } else {
            content.background(
                RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
                    .fill(settings.backgroundColor.color.opacity(settings.backgroundOpacity))
            )
        }
    }
}

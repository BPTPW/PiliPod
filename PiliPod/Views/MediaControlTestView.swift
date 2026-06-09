//
//  MediaControlTestView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/9.
//

import SwiftUI

struct MediaControlTestView: View {
    @StateObject private var manager = MediaControlTestManager()

    var body: some View {
        Form {
            Section("媒体内容") {
                TextField("Title", text: $manager.title)
                    .textInputAutocapitalization(.never)
                TextField("Artist", text: $manager.artist)
                    .textInputAutocapitalization(.never)

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Progress") {
                        Text(timeText(manager.progress))
                            .monospacedDigit()
                    }

                    Slider(
                        value: $manager.progress,
                        in: 0...max(manager.duration, 1),
                        step: 1
                    )

                    HStack {
                        Text("0:00")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(timeText(manager.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                HStack {
                    Text("Duration")
                    Spacer()
                    TextField("秒数", value: $manager.duration, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                HStack {
                    Text("Rate")
                    Spacer()
                    TextField("倍速", value: $manager.rate, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            Section("控制") {
                Button("启动媒体控制") {
                    manager.startSession()
                }
                .disabled(manager.isSessionActive)

                Button("更新内容") {
                    manager.applyNowPlayingUpdate()
                }
                .disabled(!manager.isSessionActive)

                Button("关闭媒体控制", role: .destructive) {
                    manager.stopSession()
                }
                .disabled(!manager.isSessionActive)
            }

            Section("状态") {
                LabeledContent("Session") {
                    Text(manager.isSessionActive ? "Active" : "Inactive")
                        .foregroundStyle(manager.isSessionActive ? .green : .secondary)
                }
                LabeledContent("Playback") {
                    Text(manager.isPlaying ? "Playing" : "Paused")
                        .foregroundStyle(manager.isPlaying ? .green : .secondary)
                }
            }

            Section {
                if manager.eventLogs.isEmpty {
                    Text("媒体控制面板上的播放、暂停、上下首、拖动进度事件会显示在这里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.eventLogs, id: \.self) { log in
                        Text(log)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } header: {
                HStack {
                    Text("事件日志")
                    Spacer()
                    Button("清空") {
                        manager.clearLogs()
                    }
                    .font(.footnote)
                }
            }
        }
        .navigationTitle("媒体控制测试")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeText(_ time: Double) -> String {
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        MediaControlTestView()
    }
}

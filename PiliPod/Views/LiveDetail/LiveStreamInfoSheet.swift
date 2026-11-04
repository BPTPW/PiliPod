//
//  LiveStreamInfoSheet.swift
//  PiliPod
//

import SwiftUI

/// Live counterpart of `DashStreamInfoSheet`: stream facts plus the live
/// progress-sync state used to tune `LiveLatencySyncController`.
struct LiveStreamInfoSheet: View {
    let streamURL: URL?
    let qualityLabel: String
    let playerSnapshot: PlayerUIPlaybackSnapshot
    let playbackRate: Double
    let streamDiagnostics: LiveStreamDiagnostics?
    let latencySync: LiveLatencySyncController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    videoSection
                    Divider()
                    bitrateSection
                    Divider()
                    syncSection
                    Divider()
                    playerSection
                    Divider()
                    playlistSection
                    Divider()
                    urlSection
                }
                .padding(16)
            }
            .navigationTitle("直播流信息")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var videoSection: some View {
        let size = streamDiagnostics?.presentationSize ?? .zero
        return section("视频参数") {
            LiveInfoRow("画质", qualityLabel.isEmpty ? "—" : qualityLabel)
            LiveInfoRow("分辨率", size.width > 0 ? "\(Int(size.width))×\(Int(size.height))" : "—")
            LiveInfoRow("帧率", positive(streamDiagnostics?.frameRate, format: "%.1f fps"))
        }
    }

    private var bitrateSection: some View {
        section("码率") {
            LiveInfoRow("声明码率", bitrate(streamDiagnostics?.indicatedBitrate))
            LiveInfoRow("实测码率", bitrate(streamDiagnostics?.observedBitrate))
            LiveInfoRow("视频平均码率", bitrate(streamDiagnostics?.averageVideoBitrate))
            LiveInfoRow("音频平均码率", bitrate(streamDiagnostics?.averageAudioBitrate))
            LiveInfoRow("下载速度", bytesPerSecond(playerSnapshot.loadingSpeedBytesPerSecond))
        }
    }

    private var syncSection: some View {
        let sync = latencySync.diagnostics
        return section("进度同步") {
            LiveInfoRow("同步状态", phaseLabel(sync.phase))
            LiveInfoRow("当前倍速", String(format: "%.2fx", playbackRate))
            LiveInfoRow("目标倍速", String(format: "%.2fx", sync.targetRate))
            LiveInfoRow("缓冲余量 ahead", seconds(playerSnapshot.bufferedUntil - playerSnapshot.currentTime))
            LiveInfoRow("平滑余量", sync.smoothedAhead.map(seconds) ?? "—")
            LiveInfoRow("倍速调整次数", "\(sync.rateChangeCount)")
            LiveInfoRow("安全回退次数", "\(sync.safetyResetCount)")
            LiveInfoRow(
                "距上次调整",
                sync.lastRateChangeUptime.map { seconds(ProcessInfo.processInfo.systemUptime - $0) } ?? "—"
            )
        }
    }

    private var playerSection: some View {
        section("播放器状态") {
            LiveInfoRow("播放状态", playerSnapshot.isPlaying ? String(localized: "播放中") : String(localized: "已暂停"))
            LiveInfoRow("缓冲中", playerSnapshot.isBuffering ? String(localized: "是") : String(localized: "否"))
            LiveInfoRow("当前时间 currentTime", seconds(playerSnapshot.currentTime))
            LiveInfoRow("缓冲末端 bufferedUntil", seconds(playerSnapshot.bufferedUntil))
            LiveInfoRow("可跳转窗口余量", streamDiagnostics?.seekableAhead.map(seconds) ?? "—")
            LiveInfoRow("距最新切片起点", streamDiagnostics?.behindNewestSegmentStart.map(seconds) ?? "—")
            LiveInfoRow("卡顿次数", "\(streamDiagnostics?.stallCount ?? 0)")
            LiveInfoRow("丢帧数", "\(streamDiagnostics?.droppedVideoFrames ?? 0)")
        }
    }

    private var playlistSection: some View {
        section("播放列表") {
            LiveInfoRow("MEDIA-SEQUENCE", streamDiagnostics?.playlistMediaSequence.map(String.init) ?? "—")
            LiveInfoRow("TARGETDURATION", streamDiagnostics?.playlistTargetDuration.map(seconds) ?? "—")
            LiveInfoRow("窗口切片数", streamDiagnostics.map { "\($0.playlistSegmentCount)" } ?? "—")
            LiveInfoRow("最新切片时长", streamDiagnostics?.playlistLastSegmentDuration.map(seconds) ?? "—")
            if let uri = streamDiagnostics?.lastSegmentURI, !uri.isEmpty {
                LiveURLRow("最近请求切片", uri)
            }
        }
    }

    private var urlSection: some View {
        section("流地址") {
            LiveURLRow("直播流", streamURL?.absoluteString ?? "—")
        }
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            content()
        }
    }

    private func phaseLabel(_ phase: LiveLatencySyncDiagnostics.Phase) -> String {
        switch phase {
        case .inactive: String(localized: "未运行")
        case .warmingUp: String(localized: "预热中")
        case .steady: String(localized: "正常")
        case .catchingUp: String(localized: "追赶中")
        case .safetyHold: String(localized: "安全保持")
        }
    }

    private func seconds(_ value: TimeInterval) -> String {
        String(format: "%.2f s", value)
    }

    private func positive(_ value: Double?, format: String) -> String {
        guard let value, value > 0 else { return "—" }
        return String(format: format, value)
    }

    private func bitrate(_ bitsPerSecond: Double?) -> String {
        guard let bitsPerSecond, bitsPerSecond > 0 else { return "—" }
        return String(format: "%.0f Kbps", bitsPerSecond / 1000)
    }

    private func bytesPerSecond(_ speed: Double) -> String {
        let kilobytes = max(speed, 0) / 1024
        if kilobytes < 1024 { return String(format: "%.2f KB/s", kilobytes) }
        return String(format: "%.2f MB/s", kilobytes / 1024)
    }
}

private struct LiveInfoRow: View {
    let label: LocalizedStringKey
    let value: String

    init(_ label: LocalizedStringKey, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

private struct LiveURLRow: View {
    let label: LocalizedStringKey
    let url: String

    init(_ label: LocalizedStringKey, _ url: String) {
        self.label = label
        self.url = url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(url)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}

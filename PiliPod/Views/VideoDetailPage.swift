//
//  VideoDetailPage.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI
import AVFoundation
import AVKit
import Observation

struct VideoDetailPage: View {
    @Environment(\.dismiss) var dismiss
    @State var viewModel: VideoDetailViewModel
    @State private var player: AVPlayer?
    @State private var showDebugPanel = false
    @State private var playerTimeObserver: Any?
    @Binding var isPresented: Bool

    let video: VideoItem

    init(video: VideoItem, isPresented: Binding<Bool>) {
        self.video = video
        self._isPresented = isPresented
        _viewModel = State(initialValue: VideoDetailViewModel(
            bvid: video.bvid,
            cid: video.cid ?? 0,
            title: video.title,
            cover: video.cover
        ))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 播放器
                if let source = viewModel.videoSource, let player = player {
                    ZStack(alignment: .topLeading) {
                        // AVPlayer 容器
                        VideoPlayerContainer(player: player)
                            .aspectRatio(source.aspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .topLeading) {
                                // 顶部控制按钮
                                HStack(spacing: 12) {
                                    // 返回按钮
                                    Button(action: { isPresented = false }) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Color.black.opacity(0.4))
                                            .clipShape(Circle())
                                            .backdrop()
                                    }

                                    Spacer()

                                    // 流详情按钮
                                    Button(action: { showDebugPanel.toggle() }) {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Color.black.opacity(0.4))
                                            .clipShape(Circle())
                                            .backdrop()
                                    }
                                }
                                .padding(12)
                            }
                    }
                } else {
                    // 加载状态
                    VStack(spacing: 12) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else if let error = viewModel.error {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                                Text("加载失败")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }

                // 视频信息
                VStack(alignment: .leading, spacing: 12) {
                    Text(video.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    if let detail = viewModel.videoDetail {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: detail.owner.face)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color.gray)
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.owner.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(formatDuration(detail.duration))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
            }

            // 调试信息面板
            if showDebugPanel, let source = viewModel.videoSource {
                DebugInfoPanel(
                    source: source,
                    onDismiss: { showDebugPanel = false }
                )
            }
        }
        .task {
            await viewModel.loadVideoData()
        }
        .onChange(of: viewModel.videoSource) { oldValue, newValue in
            if oldValue != newValue && newValue != nil {
                setupPlayer()
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func setupPlayer() {
        guard let source = viewModel.videoSource else { return }

        // 配置视频请求头（B站需要 Referer 和 Cookie）
        let videoHeaders: [String: String] = [
            "Cookie": LoginSession.shared.cookieString,
            "User-Agent": "Mozilla/5.0 BiliIOS/1.0",
            "Referer": "https://www.bilibili.com/"
        ]

        let audioHeaders: [String: String] = [
            "Cookie": LoginSession.shared.cookieString,
            "User-Agent": "Mozilla/5.0 BiliIOS/1.0",
            "Referer": "https://www.bilibili.com/"
        ]

        // 使用带 HTTP 头的方式创建 AVURLAsset
        let videoAsset = AVURLAsset(
            url: source.videoURL,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": videoHeaders
            ]
        )
        let audioAsset = AVURLAsset(
            url: source.audioURL,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": audioHeaders
            ]
        )

        // 创建 composition
        let composition = AVMutableComposition()

        Task {
            do {
                // 获取 video track
                let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
                if let videoTrack = videoTracks.first,
                   let compositionVideoTrack = composition.addMutableTrack(
                       withMediaType: .video,
                       preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    let timeRange = CMTimeRange(
                        start: .zero,
                        duration: videoAsset.duration
                    )
                    try compositionVideoTrack.insertTimeRange(
                        timeRange,
                        of: videoTrack,
                        at: .zero
                    )
                    // 设置偏好变换以保持宽高比
                    compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
                }

                // 获取 audio track
                let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                if let audioTrack = audioTracks.first,
                   let compositionAudioTrack = composition.addMutableTrack(
                       withMediaType: .audio,
                       preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    let timeRange = CMTimeRange(
                        start: .zero,
                        duration: audioAsset.duration
                    )
                    try compositionAudioTrack.insertTimeRange(
                        timeRange,
                        of: audioTrack,
                        at: .zero
                    )
                }

                // 创建 playerItem 和 player
                let playerItem = AVPlayerItem(asset: composition)
                let newPlayer = AVPlayer(playerItem: playerItem)

                await MainActor.run {
                    self.player = newPlayer
                    // 开始播放
                    newPlayer.play()
                    // 启动历史上报
                    viewModel.startHistoryReporting(with: newPlayer)
                }
            } catch {
                print("Failed to setup player: \(error)")
            }
        }
    }

    private func cleanupPlayer() {
        if let player = player {
            player.pause()
            viewModel.stopHistoryReporting(with: player)
            player.replaceCurrentItem(with: nil)
        }
        if let observer = playerTimeObserver {
            player?.removeTimeObserver(observer)
        }
        player = nil
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - VideoPlayerContainer

struct VideoPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

// MARK: - Debug Info Panel

struct DebugInfoPanel: View {
    let source: BiliVideoSource
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("流详情")
                        .font(.headline)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow("视频分辨率", "\(source.width)×\(source.height)")
                        InfoRow("视频编码", source.videoCodecs)
                        InfoRow("音频编码", source.audioCodecs)
                        InfoRow("帧率", "\(source.fps) fps")
                        InfoRow("视频码率", formatBitrate(source.videoBandwidth))
                        InfoRow("音频码率", formatBitrate(source.audioBandwidth))
                        InfoRow("宽高比", String(format: "%.2f:1", source.aspectRatio))
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(16)
        }
    }

    private func formatBitrate(_ bitrate: Int) -> String {
        let mbps = Double(bitrate) / 1_000_000
        return String(format: "%.2f Mbps", mbps)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Backdrop Extension

extension View {
    func backdrop() -> some View {
        self.background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

#Preview {
    @Previewable @State var isPresented = true
    
    VideoDetailPage(
        video: VideoItem(
            bvid: "BV1234567890",
            cid: nil,
            cover: "https://picsum.photos/400/250",
            title: "测试视频标题测试视频标题",
            playCount: "12万",
            danmakuCount: "345",
            uploader: "测试UP主"
        ),
        isPresented: $isPresented
    )
}

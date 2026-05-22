//
//  VideoDetailPage.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI
import Observation

struct VideoDetailPage: View {
    @State var viewModel: VideoDetailViewModel
    @State private var showDebugPanel = false
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
                // DASH 播放器
                if let stream = viewModel.dashStream, let player = viewModel.player {
                    ZStack(alignment: .topLeading) {
                        // DASH 播放器容器
                        MPVKitPlayerView(player: player)
                            .aspectRatio(stream.aspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
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
            if showDebugPanel, let stream = viewModel.dashStream {
                DashStreamDebugPanel(
                    stream: stream,
                    player: viewModel.player,
                    onDismiss: { showDebugPanel = false }
                )
            }
        }
        .task {
            await viewModel.loadVideoData()
            
            // 加载完成后启动历史上报
            if viewModel.dashStream != nil {
                viewModel.startHistoryReporting()
            }
        }
        .onDisappear {
            if let player = viewModel.player {
                player.pause()
                viewModel.stopHistoryReporting(with: player)
            }
        }
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

// MARK: - Debug Info Panel for DASH Stream

struct DashStreamDebugPanel: View {
    let stream: DashStream
    let player: MPVKitPlayer?
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
                    Text("DASH 流详情")
                        .font(.headline)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("视频参数").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow("分辨率", "\(stream.width)×\(stream.height)")
                            InfoRow("宽高比", String(format: "%.2f:1", stream.aspectRatio))
                            InfoRow("帧率", "\(stream.fps) fps")
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("编码信息").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow("视频编码", stream.videoCodec)
                            InfoRow("音频编码", stream.audioCodec)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("码率").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow("视频码率", formatBitrate(stream.videoBitrate))
                            InfoRow("音频码率", formatBitrate(stream.audioBitrate))
                        }
                        
                        if let player = player {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("播放器状态").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                                InfoRow("播放状态", player.isPlaying ? "播放中" : "已暂停")
                                InfoRow("当前时间", formatTime(player.currentTime))
                                InfoRow("总时长", formatTime(player.duration))
                            }
                        }
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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
                .frame(maxWidth: .infinity, alignment: .leading)
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

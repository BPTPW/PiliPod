//
//  LivePlaybackPage.swift
//  PiliPod
//
//  Created by Codex on 2026/6/8.
//

import SwiftUI
import Observation

struct LivePlaybackPage: View {
    let room: LiveCardModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LivePlaybackViewModel

    init(room: LiveCardModel) {
        self.room = room
        _viewModel = State(initialValue: LivePlaybackViewModel(room: room))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                headerBar(topInset: geo.safeAreaInsets.top)

                LivePlayerView(
                    roomId: room.roomId,
                    streamURL: viewModel.streamURL,
                    aspectRatio: viewModel.aspectRatio,
                    statusText: viewModel.playerStatusText
                )
                .frame(width: geo.size.width)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(room.title.isEmpty ? "直播间" : room.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            if !room.onlineCount.isEmpty {
                                Label(room.onlineCount, systemImage: "eye.fill")
                            }

                            Text("房间号 \(room.roomId)")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.systemGray6))
                            .frame(height: 480)
                            .overlay(alignment: .topLeading) {
                                Text("聊天栏区域预留")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(16)
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemBackground))
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadPlaybackIfNeeded()
        }
    }

    private func headerBar(topInset: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            CachedAsyncImage(url: URL(string: room.faceURL)) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(room.anchorName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                if !room.areaName.isEmpty {
                    Text(room.areaName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, max(topInset, 10))
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }
}

@Observable
@MainActor
private final class LivePlaybackViewModel {
    let room: LiveCardModel

    var streamURL: URL?
    var aspectRatio: CGFloat = 16.0 / 9.0
    var isLoading = false
    var errorMessage: String?
    private var hasLoaded = false

    init(room: LiveCardModel) {
        self.room = room
    }

    var playerStatusText: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if isLoading {
            return "正在获取直播流..."
        }
        return "room id: \(room.roomId)"
    }

    func loadPlaybackIfNeeded() async {
        guard !hasLoaded else { return }
        await loadPlayback()
        hasLoaded = true
    }

    private func loadPlayback() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let playback = try await BiliAPI.shared.fetchLivePlaybackInfo(roomID: room.roomId)
            streamURL = playback.streamURL
            aspectRatio = playback.aspectRatio
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LivePlaybackPage(
        room: LiveCardModel(
            roomId: "226000",
            title: "实时直播间标题示例",
            coverURL: "https://picsum.photos/400/250",
            onlineCount: "1.2万人气",
            anchorName: "主播昵称",
            faceURL: "https://picsum.photos/80",
            areaName: "手游 · 王者荣耀",
            badgeText: "已关注",
            link: nil
        )
    )
}

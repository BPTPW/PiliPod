//
//  LivePlaybackPage.swift
//  PiliPod
//
//  Created by Codex on 2026/6/8.
//

import SwiftUI

struct LivePlaybackPage: View {
    let room: LiveCardModel
    @Environment(\.dismiss) private var dismiss
    private let playerAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        LivePlayerView(
                            roomId: room.roomId,
                            streamURL: nil,
                            aspectRatio: playerAspectRatio
                        )
                        .frame(width: geo.size.width)

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)
                        .padding(.top, max(geo.safeAreaInsets.top, 12))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(room.title.isEmpty ? "直播间" : room.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 10) {
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
                        }

                        HStack(spacing: 8) {
                            if !room.onlineCount.isEmpty {
                                Label(room.onlineCount, systemImage: "eye.fill")
                            }

                            Text("房间号 \(room.roomId)")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemBackground))
        }
        .toolbar(.hidden, for: .navigationBar)
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

//
//  HomeView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct HomeView: View {
    @State private var selectedTab: String = "推荐"

    let tabs = ["直播", "推荐", "热门", "分区"]

    let videos: [VideoItem] = [
        VideoItem(
            cover: "https://picsum.photos/400/250?1",
            title: "iOS 26 LiquidGlass 动效实战",
            playCount: "12.3万",
            danmakuCount: "2456",
            uploader: "PiliPod"
        ),
        VideoItem(
            cover: "https://picsum.photos/400/250?2",
            title: "SwiftUI 高性能信息流实现",
            playCount: "8.8万",
            danmakuCount: "1145",
            uploader: "SwiftCat"
        ),
        VideoItem(
            cover: "https://picsum.photos/400/250?3",
            title: "Bilibili 第三方客户端开发记录",
            playCount: "6.4万",
            danmakuCount: "876",
            uploader: "OpenSource"
        ),
        VideoItem(
            cover: "https://picsum.photos/400/250?4",
            title: "Apple Design Award UI 分析",
            playCount: "4.2万",
            danmakuCount: "567",
            uploader: "DesignLab"
        )
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部区域
                VStack(spacing: 14) {
                    // 第一行
                    HStack(spacing: 12) {
                        // 搜索框
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)

                            Text("搜索视频")
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22)
                                        .stroke(
                                            Color.white.opacity(0.18),
                                            lineWidth: 1
                                        )
                                }
                        )
                        .shadow(
                            color: .black.opacity(0.06),
                            radius: 10,
                            y: 4
                        )

                        // 消息按钮
                        Button {} label: {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.black.opacity(0.8))
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            Circle()
                                                .stroke(
                                                    Color.white.opacity(0.18),
                                                    lineWidth: 1
                                                )
                                        }
                                )
                                .shadow(
                                    color: .black.opacity(0.06),
                                    radius: 8,
                                    y: 4
                                )
                        }

                        // 用户头像
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.18),
                                        lineWidth: 1
                                    )
                            }
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.black.opacity(0.8))
                            }
                            .shadow(
                                color: .black.opacity(0.06),
                                radius: 8,
                                y: 4
                            )
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.black.opacity(0.8))
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // 分类栏
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(tabs, id: \.self) { tab in
                                VStack(spacing: 6) {
                                    Text(tab)
                                        .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                                    Capsule()
                                        .fill(selectedTab == tab ? Color.pink : Color.clear)
                                        .frame(height: 3)
                                }
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedTab = tab
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 10)
                .background(.regularMaterial)

                Divider()

                // 视频流
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(videos) { video in
                            VideoCardView(video: video)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    HomeView()
}

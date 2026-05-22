//
//  LiveCardView.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import SwiftUI

struct LiveCardView: View {
    let model: LiveCardModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面
            AsyncImage(url: URL(string: model.coverURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                // 左上角 LIVE 角标 + 呼吸动画
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.pink)
                    )
                    .scaleEffect(isAnimating ? 1.08 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                // 左下角在线人数
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 9))
                    Text(model.onlineCount)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.6))
                )
                .padding(6)
            }

            // 直播间标题
            Text(model.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2 ... 2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            // 主播名
            HStack(spacing: 4) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 11))
                Text(model.anchorName)
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }
}

#Preview {
    LiveCardView(
        model: LiveCardModel(
            roomId: "226000",
            title: "实时直播间标题示例",
            coverURL: "https://picsum.photos/400/250",
            onlineCount: "1.2万",
            anchorName: "主播昵称"
        )
    )
    .padding()
}

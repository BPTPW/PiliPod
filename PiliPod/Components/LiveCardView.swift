//
//  LiveCardView.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import SwiftUI

struct LiveCardView: View {
    let model: LiveCardModel
    let cardWidth: CGFloat?

    init(model: LiveCardModel, cardWidth: CGFloat? = nil) {
        self.model = model
        self.cardWidth = cardWidth
    }

    private let cornerRadius: CGFloat = 18
    private var thumbnailHeight: CGFloat {
        guard let cardWidth else { return 110 }
        return cardWidth * 10 / 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: URL(string: model.coverURL)) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                    }
                }
                .frame(width: cardWidth, height: thumbnailHeight)
                .clipped()

                Text(model.onlineCount)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .glassEffect(
                        .regular,
                        in: .capsule
                    )
                    .padding(6)
            }
            .overlay(alignment: .topLeading) {
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .glassEffect(
                        .regular.tint(.biliPink),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(model.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2 ... 2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)

                if let badgeText = model.badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .glassEffect(
                            .regular.tint(Color("BiliPink")),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }

                HStack(alignment: .center, spacing: 8) {
                    CachedAsyncImage(url: URL(string: model.faceURL)) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Circle()
                                .fill(Color(.systemGray5))
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.anchorName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !model.areaName.isEmpty {
                            Text(model.areaName)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        )
        .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .frame(width: cardWidth, alignment: .leading)
    }
}

#Preview {
    LiveCardView(
        model: LiveCardModel(
            roomId: "226000",
            uid: 123456,
            title: "实时直播间标题示例",
            coverURL: "https://picsum.photos/400/250",
            onlineCount: "1.2万",
            anchorName: "主播昵称",
            faceURL: "https://picsum.photos/80",
            areaName: "手游 · 王者荣耀",
            badgeText: "已关注",
            link: "https://live.bilibili.com/226000"
        )
    )
    .padding()
}

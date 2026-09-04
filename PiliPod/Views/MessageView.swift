//
//  MessageView.swift
//  PiliPod
//

import SwiftUI

struct MessageView: View {
    @Bindable var viewModel: HomeViewModel
    @State private var selectedCategory: MessageFeedView.Category?

    private struct MessageCategory: Identifiable {
        let id: String
        let title: String
        let icon: String
        let count: Int
    }

    private var categories: [MessageCategory] {
        [
            MessageCategory(id: "reply", title: "回复", icon: "message", count: viewModel.unreadReplyCount),
            MessageCategory(id: "at", title: "@我", icon: "at", count: viewModel.unreadAtCount),
            MessageCategory(id: "like", title: "收到喜欢", icon: "hand.thumbsup", count: viewModel.unreadLikeCount)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(categories) { category in
                        Button { selectedCategory = category.id == "reply" ? .reply : category.id == "at" ? .at : .like } label: {
                        VStack(spacing: 7) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 20, weight: .medium))
                                    .frame(height: 24)

                                if category.count > 0 {
                                    Text(category.count > 99 ? "99+" : String(category.count))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 15, minHeight: 15)
                                        .background(.red, in: Capsule())
                                        .overlay { Capsule().stroke(.regularMaterial, lineWidth: 1) }
                                        .offset(x: 10, y: -8)
                                }
                            }
                            Text(category.title)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 0) {
                Text("暂无私信")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedCategory) { category in
            MessageFeedView(category: category)
        }
        .task {
            await viewModel.loadUnreadMessageCount(force: true)
        }
    }
}

#Preview {
    MessageView(viewModel: HomeViewModel())
}

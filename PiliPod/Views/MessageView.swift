//
//  MessageView.swift
//  PiliPod
//

import SwiftUI

struct MessageView: View {
    @Bindable var viewModel: HomeViewModel
    @State private var selectedCategory: MessageFeedView.Category?
    @State private var privateSessions: [PrivateMessageSession] = []
    @State private var isLoadingPrivateSessions = false
    @State private var privateSessionError: String?

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
        List {
            Section {
                HStack(spacing: 10) {
                    ForEach(categories) { category in
                        Button {
                            selectedCategory = category.id == "reply" ? .reply : category.id == "at" ? .at : .like
                        } label: {
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
                .padding(.vertical, 4)
                .messageListRow()
            }

            Section("私信") {
                if isLoadingPrivateSessions && privateSessions.isEmpty {
                    ProgressView("加载私信中…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .messageListRow()
                } else if let privateSessionError, privateSessions.isEmpty {
                    ContentUnavailableView {
                        Label("私信加载失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(privateSessionError)
                    } actions: {
                        Button("重试") { Task { await loadPrivateSessions() } }
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .messageListRow()
                } else if privateSessions.isEmpty {
                    ContentUnavailableView("暂无私信", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .messageListRow()
                } else {
                    ForEach(privateSessions) { session in
                        PrivateMessageSessionRow(session: session)
                            .messageListRow()
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await loadPrivateSessions()
            await viewModel.loadUnreadMessageCount(force: true)
        }
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedCategory) { category in
            MessageFeedView(category: category)
        }
        .task {
            await viewModel.loadUnreadMessageCount(force: true)
            await loadPrivateSessions()
        }
    }

    private func loadPrivateSessions() async {
        guard LoginSession.shared.isLogin else {
            privateSessions = []
            privateSessionError = nil
            return
        }

        isLoadingPrivateSessions = true
        privateSessionError = nil
        defer { isLoadingPrivateSessions = false }

        do {
            privateSessions = try await BiliAPI.shared.fetchPrivateMessageSessions()
        } catch {
            privateSessionError = error.localizedDescription
            ErrorLogService.record(error, context: "加载私信会话列表")
        }
    }
}

private struct PrivateMessageSessionRow: View {
    let session: PrivateMessageSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CachedAsyncImage(url: URL(string: session.avatarURL)) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.12))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(session.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(session.messagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)

            VStack(alignment: .trailing, spacing: 7) {
                Text(Self.relativeTime(for: session.lastMessageTimestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if session.unreadCount > 0 {
                    Text(String(session.unreadCount))
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.red, in: Capsule())
                }
            }
            .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private static func relativeTime(for timestamp: UInt64) -> String {
        guard timestamp > 0 else { return "" }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 * 60 {
            return "\(max(1, Int(elapsed / 60)))分钟前"
        }
        if elapsed < 24 * 60 * 60 {
            return "\(Int(elapsed / (60 * 60)))小时前"
        }
        if elapsed < 2 * 24 * 60 * 60 {
            return "昨天"
        }
        if elapsed < 5 * 24 * 60 * 60 {
            return "\(Int(elapsed / (24 * 60 * 60)))天前"
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        if components.year == calendar.component(.year, from: Date()) {
            return "\(components.month ?? 1)月\(components.day ?? 1)日"
        }
        return "\(components.year ?? 0)年\(components.month ?? 1)月\(components.day ?? 1)日"
    }
}

private extension View {
    func messageListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

#Preview {
    MessageView(viewModel: HomeViewModel())
}

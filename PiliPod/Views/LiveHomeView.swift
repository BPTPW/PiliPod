//
//  LiveHomeView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/8.
//

import Observation
import SwiftUI

struct LiveHomeView: View {
    let cardWidth: CGFloat

    @Bindable var viewModel: LiveHomeViewModel
    @State private var selectedRoom: LiveCardModel?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    private let horizontalPadding: CGFloat = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading && viewModel.rooms.isEmpty && viewModel.followingItems.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else if let errorMessage = viewModel.errorMessage,
                          viewModel.rooms.isEmpty,
                          viewModel.followingItems.isEmpty
                {
                    ContentUnavailableView(
                        "直播加载失败",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text(errorMessage)
                    )
                    .padding(.top, 48)
                } else {
                    if !viewModel.followingItems.isEmpty {
                        sectionTitle("我的关注")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(viewModel.followingItems) { item in
                                    Button {
                                        selectedRoom = viewModel.roomModel(for: item)
                                    } label: {
                                        VStack(spacing: 8) {
                                            CachedAsyncImage(url: URL(string: item.faceURL)) { phase in
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
                                            .frame(width: 62, height: 62)
                                            .clipShape(Circle())
                                            .overlay {
                                                Circle()
                                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                            }

                                            Text(item.name)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .frame(width: 68)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                        }
                    }

                    if !viewModel.areaTabs.isEmpty {
                        sectionTitle("分区")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewModel.areaTabs) { tab in
                                    Text(tab.title)
                                        .font(.system(size: 14, weight: tab.id == viewModel.selectedAreaID ? .semibold : .regular))
                                        .foregroundStyle(tab.id == viewModel.selectedAreaID ? .primary : .secondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .glassEffect(
                                            tab.id == viewModel.selectedAreaID ? .regular.tint(.biliPink.opacity(0.18)) : .regular,
                                            in: .capsule
                                        )
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(viewModel.rooms) { room in
                            Button {
                                selectedRoom = room
                            } label: {
                                LiveCardView(model: room, cardWidth: cardWidth)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .navigationDestination(item: $selectedRoom) { room in
            LivePlaybackPage(room: room)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, horizontalPadding)
    }
}

@Observable
@MainActor
final class LiveHomeViewModel {
    var followingItems: [LiveFollowingItem] = []
    var areaTabs: [LiveAreaTab] = []
    var selectedAreaID: String = "recommend"
    var rooms: [LiveCardModel] = []
    var isLoading = false
    var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await fetchData()
        hasLoaded = true
    }

    func refresh() async {
        await fetchData()
        hasLoaded = true
    }

    func roomModel(for item: LiveFollowingItem) -> LiveCardModel {
        if let existing = rooms.first(where: { $0.roomId == item.roomId }) {
            return existing
        }

        return LiveCardModel(
            roomId: item.roomId,
            uid: item.uid,
            title: item.name,
            coverURL: "",
            onlineCount: "",
            anchorName: item.name,
            faceURL: item.faceURL,
            areaName: "",
            badgeText: "我的关注",
            link: item.link
        )
    }

    private func fetchData() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let payload = try await BiliAPI.shared.fetchLiveHomeFeed()
            followingItems = payload.followingItems
            areaTabs = payload.areaTabs
            selectedAreaID = areaTabs.first?.id ?? "recommend"
            rooms = payload.rooms
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LiveHomeView(cardWidth: 180, viewModel: LiveHomeViewModel())
}

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
                                    Button {
                                        Task {
                                            await viewModel.selectArea(tab)
                                        }
                                    } label: {
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
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                        }
                    }

                    if viewModel.isLoading && viewModel.rooms.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if let errorMessage = viewModel.errorMessage, viewModel.rooms.isEmpty {
                        ContentUnavailableView(
                            "直播加载失败",
                            systemImage: "dot.radiowaves.left.and.right",
                            description: Text(errorMessage)
                        )
                        .padding(.top, 24)
                    } else {
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
    private var activeLoadToken = UUID()

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await fetchData()
        hasLoaded = true
    }

    func refresh() async {
        await fetchHomeData(preservingSelectionID: selectedAreaID)
        hasLoaded = true
    }

    func selectArea(_ tab: LiveAreaTab) async {
        guard tab.id != selectedAreaID || rooms.isEmpty else { return }

        selectedAreaID = tab.id
        rooms = []
        errorMessage = nil

        if tab.isRecommend {
            await fetchHomeData(preservingSelectionID: tab.id)
        } else {
            await fetchAreaRooms(for: tab)
        }
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
        await fetchHomeData(preservingSelectionID: selectedAreaID)
    }

    private func fetchHomeData(preservingSelectionID selectionID: String?) async {
        guard !isLoading else { return }

        let loadToken = UUID()
        activeLoadToken = loadToken
        isLoading = true
        errorMessage = nil
        defer {
            if activeLoadToken == loadToken {
                isLoading = false
            }
        }

        do {
            let payload = try await BiliAPI.shared.fetchLiveHomeFeed()
            guard activeLoadToken == loadToken else { return }

            followingItems = payload.followingItems
            areaTabs = payload.areaTabs

            let selectedTab = payload.areaTabs.first(where: { $0.id == selectionID }) ?? payload.areaTabs.first ?? .recommend
            selectedAreaID = selectedTab.id

            if selectedTab.isRecommend {
                rooms = payload.rooms
            } else {
                rooms = []
                try await fetchAreaRooms(for: selectedTab, loadToken: loadToken)
            }
        } catch {
            guard activeLoadToken == loadToken else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func fetchAreaRooms(for tab: LiveAreaTab, loadToken: UUID? = nil) async {
        if loadToken == nil {
            guard !isLoading else { return }
            let newLoadToken = UUID()
            activeLoadToken = newLoadToken
            isLoading = true
            errorMessage = nil
            defer {
                if activeLoadToken == newLoadToken {
                    isLoading = false
                }
            }
            do {
                try await loadAreaRooms(for: tab, loadToken: newLoadToken)
            } catch {
                guard activeLoadToken == newLoadToken else { return }
                errorMessage = error.localizedDescription
            }
            return
        }

        guard let loadToken else { return }

        do {
            try await loadAreaRooms(for: tab, loadToken: loadToken)
        } catch {
            guard activeLoadToken == loadToken else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadAreaRooms(for tab: LiveAreaTab, loadToken: UUID) async throws {
        guard let areaID = tab.areaID, let parentAreaID = tab.parentAreaID else {
            return
        }

        let areaRooms = try await BiliAPI.shared.fetchLiveAreaFeed(areaID: areaID, parentAreaID: parentAreaID)
        guard activeLoadToken == loadToken, selectedAreaID == tab.id else { return }
        rooms = areaRooms
    }
}

#Preview {
    LiveHomeView(cardWidth: 180, viewModel: LiveHomeViewModel())
}

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
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewModel.areaTabs) { tab in
                                    Button {
                                        Task {
                                            await viewModel.selectArea(tab)
                                        }
                                    } label: {
                                        ZStack{
                                            Capsule()
                                                .fill(tab.id == viewModel.selectedAreaID ?
                                                        .biliPink :
                                                        .clear
                                                )
                                            Text(tab.title)
                                                .font(.system(size: 14, weight: tab.id == viewModel.selectedAreaID ? .semibold : .regular))
                                                .foregroundStyle(tab.id == viewModel.selectedAreaID ? .white : .secondary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                        }
                                    }
                                    .tint(.primary)
                                    .glassEffect(
                                        .regular.interactive(),
                                        in: .capsule
                                    )
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, 12)
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

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
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
    private var recommendedRooms: [LiveCardModel] = []
    private var areaRoomsByID: [String: [LiveCardModel]] = [:]

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await fetchHomeData()
        hasLoaded = true
    }

    func refresh() async {
        if selectedAreaID == LiveAreaTab.recommend.id {
            await fetchHomeData()
        } else if let selectedTab = areaTabs.first(where: { $0.id == selectedAreaID }) {
            await fetchAreaRooms(for: selectedTab, forceRefresh: true)
        }
        hasLoaded = true
    }

    func selectArea(_ tab: LiveAreaTab) async {
        guard tab.id != selectedAreaID else { return }

        selectedAreaID = tab.id
        errorMessage = nil

        if tab.isRecommend {
            if !recommendedRooms.isEmpty {
                rooms = recommendedRooms
            } else {
                rooms = []
                await fetchHomeData()
            }
        } else {
            if let cachedRooms = areaRoomsByID[tab.id] {
                rooms = cachedRooms
            } else {
                rooms = []
                await fetchAreaRooms(for: tab, forceRefresh: true)
            }
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

    private func fetchHomeData() async {
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
            recommendedRooms = payload.rooms

            if selectedAreaID == LiveAreaTab.recommend.id {
                rooms = payload.rooms
            }
        } catch {
            guard activeLoadToken == loadToken else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func fetchAreaRooms(for tab: LiveAreaTab, forceRefresh: Bool = false, loadToken: UUID? = nil) async {
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
                try await loadAreaRooms(for: tab, loadToken: newLoadToken, forceRefresh: forceRefresh)
            } catch {
                guard activeLoadToken == newLoadToken else { return }
                errorMessage = error.localizedDescription
            }
            return
        }

        guard let loadToken else { return }

        do {
            try await loadAreaRooms(for: tab, loadToken: loadToken, forceRefresh: forceRefresh)
        } catch {
            guard activeLoadToken == loadToken else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadAreaRooms(for tab: LiveAreaTab, loadToken: UUID, forceRefresh: Bool) async throws {
        guard let areaID = tab.areaID, let parentAreaID = tab.parentAreaID else {
            return
        }

        let areaRooms: [LiveCardModel]
        if !forceRefresh, let cachedRooms = areaRoomsByID[tab.id] {
            areaRooms = cachedRooms
        } else {
            areaRooms = try await BiliAPI.shared.fetchLiveAreaFeed(areaID: areaID, parentAreaID: parentAreaID)
            areaRoomsByID[tab.id] = areaRooms
        }

        guard activeLoadToken == loadToken, selectedAreaID == tab.id else { return }
        rooms = areaRooms
    }
}

#Preview {
    LiveHomeView(cardWidth: 180, viewModel: LiveHomeViewModel())
}

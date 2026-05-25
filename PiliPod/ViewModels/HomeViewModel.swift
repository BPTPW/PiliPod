//
//  HomeViewModel.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation
import Observation

/// 推荐 API 模式（后续通过设置动态切换，当前固定为 App 版）
enum RecommendAPIMode {
    case web
    case app
}

@Observable
@MainActor
class HomeViewModel {
    var sections: [VideoSection] = []
    var feedCards: [FeedCardItem] = []
    var isLoading = false
    var userFace: String?
    private var hasLoaded = false

    /// 下拉刷新时，新内容插入顶部后，此值标记了新卡片数量；
    /// HomeView 据此在"新 / 旧"内容之间绘制 DividerWithText
    var refreshMarkerIndex: Int?

    /// 当前使用的推荐 API 模式（后续由设置控制，现固定为 App 版）
    private var apiMode: RecommendAPIMode = .app

    // Web 推荐流状态
    private var freshIdx: Int = 1
    private var brush: Int = 0

    // App 推荐流状态
    private var appNextIdx: Int = 0

    func loadUserIfNeeded() async {
        guard LoginSession.shared.isLogin else { return }

        do {
            let user = try await BiliAPI.shared.fetchMyInfo()
            userFace = user.face
        } catch {
            print(error)
        }
    }

    // MARK: - 统一推荐入口

    func loadInitialVideos() async {
        if isLoading || hasLoaded { return }

        isLoading = true
        defer { isLoading = false }

        switch apiMode {
        case .web:
            freshIdx = 1
            brush = 0
            do {
                let videos = try await BiliAPI.shared.fetchRecommendVideos(
                    freshIdx: freshIdx, freshType: 4, brush: brush
                )
                sections = [VideoSection(title: nil, videos: videos)]
                hasLoaded = true
            } catch { print(error) }

        case .app:
            appNextIdx = 0
            do {
                let (cards, nextIdx) = try await BiliAPI.shared.fetchAppRecommendFeed(
                    idx: 0, flush: 1
                )
                feedCards = cards
                appNextIdx = nextIdx
                hasLoaded = true
            } catch { print(error) }
        }
    }

    func refreshVideos() async {
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        switch apiMode {
        case .web:
            freshIdx += 1
            brush += 1
            do {
                let newVideos = try await BiliAPI.shared.fetchRecommendVideos(
                    freshIdx: freshIdx, freshType: 3, brush: brush
                )
                // 下拉刷新：将新视频作为独立 section 插入顶部，旧内容放在下方
                let newSection = VideoSection(title: "上次看到这", videos: newVideos)
                sections.insert(newSection, at: 0)
            } catch { print(error) }

        case .app:
            do {
                let (cards, nextIdx) = try await BiliAPI.shared.fetchAppRecommendFeed(
                    idx: 0, flush: 1
                )
                // 下拉刷新：新内容插入到已有列表顶部
                feedCards.insert(contentsOf: cards, at: 0)
                refreshMarkerIndex = cards.count
                appNextIdx = nextIdx
            } catch { print(error) }
        }
    }

    func loadMoreVideos() async {
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        // 加载更多时清除刷新分隔标记
        refreshMarkerIndex = nil

        switch apiMode {
        case .web:
            freshIdx += 1
            do {
                let moreVideos = try await BiliAPI.shared.fetchRecommendVideos(
                    freshIdx: freshIdx, freshType: 4, brush: brush
                )
                if let lastIndex = sections.indices.last {
                    sections[lastIndex].videos.append(contentsOf: moreVideos)
                }
            } catch { print(error) }

        case .app:
            do {
                let (cards, nextIdx) = try await BiliAPI.shared.fetchAppRecommendFeed(
                    idx: appNextIdx, flush: 0
                )
                feedCards.append(contentsOf: cards)
                appNextIdx = nextIdx
            } catch { print(error) }
        }
    }
}

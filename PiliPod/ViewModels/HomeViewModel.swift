//
//  HomeViewModel.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation
import Observation

@Observable
@MainActor
class HomeViewModel {
    var sections: [VideoSection] = []
    var isLoading = false
    private var hasLoaded = false
    // 推荐流状态
    private var freshIdx: Int = 1
    private var brush: Int = 0

    func loadInitialVideos() async {
        if isLoading || hasLoaded {
            return
        }

        isLoading = true
        defer { isLoading = false }

        freshIdx = 1
        brush = 0

        do {
            let videos = try await BiliAPI.shared.fetchRecommendVideos(
                freshIdx: freshIdx,
                freshType: 4,
                brush: brush
            )

            sections = [
                VideoSection(
                    title: nil,
                    videos: videos
                )
            ]
            hasLoaded = true

        } catch {
            print(error)
        }
    }

    func refreshVideos() async {
        if isLoading {
            return
        }

        isLoading = true
        defer { isLoading = false }

        freshIdx += 1
        brush += 1

        do {
            let newVideos = try await BiliAPI.shared.fetchRecommendVideos(
                freshIdx: freshIdx,
                freshType: 3,
                brush: brush
            )

            // 下拉刷新：直接替换当前列表
            sections = [
                VideoSection(
                    title: nil,
                    videos: newVideos
                )
            ]

        } catch {
            print(error)
        }
    }

    func loadMoreVideos() async {
        if isLoading {
            return
        }

        isLoading = true
        defer { isLoading = false }

        freshIdx += 1

        do {
            let moreVideos = try await BiliAPI.shared.fetchRecommendVideos(
                freshIdx: freshIdx,
                freshType: 4,
                brush: brush
            )

            if let lastIndex = sections.indices.last {
                sections[lastIndex].videos.append(contentsOf: moreVideos)
            }

        } catch {
            print(error)
        }
    }
}

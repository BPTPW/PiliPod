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

    var videos: [VideoItem] = []

    var isLoading = false

    func loadVideos() async {

        isLoading = true

        do {

            videos = try await BiliAPI.shared.fetchRecommendVideos()

        } catch {

            print(error)
        }

        isLoading = false
    }
    func loadInitialVideos() async {
        do {
            let videos = try await BiliAPI.shared.fetchRecommendVideos()

            sections = [
                VideoSection(
                    title: nil,
                    videos: videos
                )
            ]

        } catch {

            print(error)
        }
    }
    func refreshVideos() async {
        do {
            let newVideos = try await BiliAPI.shared.fetchRecommendVideos()

            sections.insert(
                VideoSection(
                    title: "刚刚更新",
                    videos: newVideos
                ),
                at: 0
            )

            // 防止无限增长
            if sections.count > 5 {

                sections.removeLast()
            }

        } catch {

            print(error)
        }
    }
    func loadMoreVideos() async {

        do {

            let moreVideos = try await BiliAPI.shared.fetchRecommendVideos()

            if let lastIndex = sections.indices.last {

                sections[lastIndex].videos.append(contentsOf: moreVideos)
            }

        } catch {

            print(error)
        }
    }
}

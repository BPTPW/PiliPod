//
//  VideoDetailViewModel.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation
import Observation

@Observable
class VideoDetailViewModel {
    var videoDetail: VideoDetailData?
    var dashStream: DashStream?
    var player: MPVKitPlayer?
    var isLoading = false
    var error: String?

    var ownerFollowerCount: Int?
    var ownerArchiveCount: Int?

    var isLiked = false
    var isDisliked = false
    var isCoined = false
    var isFavorited = false

    let bvid: String
    var aid: Int = 0
    var cid: Int = 0
    let title: String
    let cover: String

    private var historyReportTimer: Timer?
    private var lastReportedProgress = 0

    init(
        bvid: String,
        cid: Int = 0,
        title: String,
        cover: String
    ) {
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.cover = cover
        self.player = MPVKitPlayer()
    }

    // MARK: - Load Video Data

    func loadVideoData() async {
        isLoading = true
        error = nil
        ownerFollowerCount = nil
        ownerArchiveCount = nil
        isLiked = false
        isDisliked = false
        isCoined = false
        isFavorited = false

        do {
            // 获取视频详情
            let detail = try await BiliAPI.shared.fetchVideoDetail(bvid: bvid)
            print(detail)
            await MainActor.run {
                self.videoDetail = detail
                self.aid = detail.aid
                self.cid = detail.cid
            }

            // 获取用户对该视频的操作状态（点赞/点踩/投币/收藏）
            Task {
                do {
                    let relation = try await BiliAPI.shared.fetchArchiveRelation(bvid: bvid)
                    await MainActor.run {
                        self.isLiked = relation.like
                        self.isDisliked = relation.dislike
                        self.isCoined = relation.coin > 0
                        self.isFavorited = relation.favorite
                    }
                } catch {
                    // 可能未登录/风控等；不影响播放与详情展示
                    print("获取视频关系失败: \(error)")
                }
            }

            // 获取 UP 主粉丝/视频数（用于详情页展示；后续主页复用）
            Task {
                do {
                    let stats = try await BiliAPI.shared.fetchUserCardStats(mid: detail.owner.mid)
                    await MainActor.run {
                        self.ownerFollowerCount = stats.follower
                        self.ownerArchiveCount = stats.archiveCount
                    }
                } catch {
                    // 忽略错误，避免影响播放；UI 保留占位
                    print("获取 UP 主信息失败: \(error)")
                }
            }

            // 获取播放地址
            let playUrlResponse = try await BiliAPI.shared.fetchPlayUrl(
                bvid: bvid,
                cid: detail.cid
            )

            // 选择最优 DASH 流（HEVC 优先）
            guard let stream = DashStreamSelector.selectOptimalStream(from: playUrlResponse) else {
                throw APIError.noVideoOrAudio
            }

            await MainActor.run {
                self.dashStream = stream
                self.isLoading = false

                // 加载到播放器
                if let player = self.player {
                    player.play(stream: stream)
                }
            }

            // 上报播放历史（进入时）
            Task {
                try? await BiliAPI.shared.reportHistory(
                    aid: detail.aid,
                    cid: detail.cid,
                    progress: 0
                )
            }
        } catch {
            print("视频加载出现错误: ")
            print(error)
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Actions (UI Only)

    func toggleLike() {
        if isLiked {
            isLiked = false
        } else {
            isLiked = true
            isDisliked = false
        }
    }

    func toggleDislike() {
        if isDisliked {
            isDisliked = false
        } else {
            isDisliked = true
            isLiked = false
        }
    }

    func toggleCoin() {
        isCoined.toggle()
    }

    func toggleFavorite() {
        isFavorited.toggle()
    }

    // MARK: - History Report

    func startHistoryReporting() {
        guard let player = player else { return }

        // 先上报一次
        reportHistoryIfNeeded(with: player)

        // 设置定时器，每 15 秒上报一次
        historyReportTimer = Timer.scheduledTimer(
            withTimeInterval: 15,
            repeats: true
        ) { [weak self] _ in
            self?.reportHistoryIfNeeded(with: player)
        }
    }

    private func reportHistoryIfNeeded(with player: MPVKitPlayer) {
        let currentProgress = Int(player.currentTime)

        // 如果进度有改变，才上报
        if currentProgress != lastReportedProgress {
            lastReportedProgress = currentProgress

            Task {
                try? await BiliAPI.shared.reportHistory(
                    aid: aid,
                    cid: cid,
                    progress: currentProgress
                )
            }
        }
    }

    func stopHistoryReporting(with player: MPVKitPlayer) {
        historyReportTimer?.invalidate()
        historyReportTimer = nil

        // 退出时最后上报一次
        let finalProgress = Int(player.currentTime)

        Task {
            try? await BiliAPI.shared.reportHistory(
                aid: aid,
                cid: cid,
                progress: finalProgress
            )
        }
    }

    // MARK: - Cleanup

    deinit {
        historyReportTimer?.invalidate()
        player?.stop()
    }
}

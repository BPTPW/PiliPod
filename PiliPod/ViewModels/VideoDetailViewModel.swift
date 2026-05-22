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

        do {
            // 获取视频详情
            let detail = try await BiliAPI.shared.fetchVideoDetail(bvid: bvid)
            await MainActor.run {
                self.videoDetail = detail
                self.aid = detail.aid
                self.cid = detail.cid
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
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
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

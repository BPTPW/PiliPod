//
//  VideoDetailViewModel.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation
import Observation
import AVFoundation

@Observable
class VideoDetailViewModel {
    var videoDetail: VideoDetailData?
    var videoSource: BiliVideoSource?
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
    }

    // MARK: - Load Video Data

    func loadVideoData() async {
        isLoading = true
        error = nil

        do {
            // 获取视频详情（包含 cid 和 aid）
            let detail = try await BiliAPI.shared.fetchVideoDetail(bvid: bvid)
            await MainActor.run {
                self.videoDetail = detail
                self.aid = detail.aid
                self.cid = detail.cid
            }

            // 获取播放地址
            let source = try await BiliAPI.shared.fetchPlayUrl(bvid: bvid, cid: detail.cid)
            await MainActor.run {
                self.videoSource = source
                self.isLoading = false
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

    func startHistoryReporting(with player: AVPlayer) {
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

    private func reportHistoryIfNeeded(with player: AVPlayer) {
        guard let item = player.currentItem else { return }

        let currentProgress = Int(item.currentTime().seconds)

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

    func stopHistoryReporting(with player: AVPlayer) {
        historyReportTimer?.invalidate()
        historyReportTimer = nil

        // 退出时最后上报一次
        guard let item = player.currentItem else { return }
        let finalProgress = Int(item.currentTime().seconds)

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
    }
}

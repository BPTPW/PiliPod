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

    var likeCount = 0
    var coinCount = 0
    var favoriteCount = 0

    var isLikeRequesting = false
    var isDislikeRequesting = false
    var isCoinRequesting = false
    var isFavoriteRequesting = false

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
        likeCount = 0
        coinCount = 0
        favoriteCount = 0

        do {
            // 获取视频详情
            let detail = try await BiliAPI.shared.fetchVideoDetail(bvid: bvid)
            print(detail)
            await MainActor.run {
                self.videoDetail = detail
                self.aid = detail.aid
                self.cid = detail.cid
                self.likeCount = detail.stat.like
                self.coinCount = detail.stat.coin
                self.favoriteCount = detail.stat.favorite
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
        Task { await toggleLikeAsync() }
    }

    func toggleDislike() {
        Task { await toggleDislikeAsync() }
    }

    func toggleCoin() {
        // coin 的具体投币数量由 UI 选择，这里不做 toggle
    }

    func toggleFavorite() {
        // 收藏需要弹出收藏夹选择 UI，这里不做 toggle
    }

    @MainActor
    private func toggleLikeAsync() async {
        guard !isLikeRequesting else { return }
        guard aid != 0 else { return }

        isLikeRequesting = true
        let wasLiked = isLiked

        do {
            try await BiliAPI.shared.likeVideo(
                aid: aid,
                isCancel: wasLiked
            )
            if wasLiked {
                isLiked = false
                if likeCount > 0 { likeCount -= 1 }
            } else {
                isLiked = true
                isDisliked = false
                likeCount += 1
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLikeRequesting = false
    }

    @MainActor
    private func toggleDislikeAsync() async {
        guard !isDislikeRequesting else { return }
        guard aid != 0 else { return }

        isDislikeRequesting = true
        let wasDisliked = isDisliked

        do {
            try await BiliAPI.shared.dislikeVideo(
                aid: aid,
                isCancel: wasDisliked
            )
            if wasDisliked {
                isDisliked = false
            } else {
                isDisliked = true
                isLiked = false
            }
        } catch {
            self.error = error.localizedDescription
        }

        isDislikeRequesting = false
    }

    @MainActor
    func coin(multiply: Int) async {
        guard !isCoinRequesting else { return }
        guard aid != 0 else { return }
        guard multiply == 1 || multiply == 2 else { return }
        guard !isCoined else { return }

        isCoinRequesting = true
        do {
            try await BiliAPI.shared.coinVideo(
                aid: aid,
                multiply: multiply
            )
            isCoined = true
            coinCount += multiply
        } catch {
            self.error = error.localizedDescription
        }
        isCoinRequesting = false
    }

    func fetchFavoriteFoldersForCurrentUser() async throws -> [FavoriteFolderItem] {
        guard let uidString = LoginSession.shared.cookies?.DedeUserID,
              let uid = Int64(uidString)
        else {
            throw APIError.responseError(-101)
        }
        guard aid != 0 else { return [] }

        return try await BiliAPI.shared.fetchCreatedFavoriteFolders(
            upMid: uid,
            rid: Int64(aid)
        )
    }

    @MainActor
    func applyFavoriteSelection(
        addMediaIds: [Int64],
        delMediaIds: [Int64],
        finalSelectedIds: Set<Int64>
    ) async {
        guard !isFavoriteRequesting else { return }
        guard aid != 0 else { return }

        isFavoriteRequesting = true
        let wasFavorited = isFavorited
        do {
            try await BiliAPI.shared.dealFavoriteResource(
                rid: Int64(aid),
                addMediaIds: addMediaIds,
                delMediaIds: delMediaIds
            )
            let nowFavorited = !finalSelectedIds.isEmpty
            isFavorited = nowFavorited
            if !wasFavorited, nowFavorited {
                favoriteCount += 1
            } else if wasFavorited, !nowFavorited {
                if favoriteCount > 0 { favoriteCount -= 1 }
            }
        } catch {
            self.error = error.localizedDescription
        }
        isFavoriteRequesting = false
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

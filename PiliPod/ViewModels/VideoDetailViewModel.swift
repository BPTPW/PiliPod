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
    var playerInfo: PlayerWbiV2Data?
    var playUrlData: PlayUrlResponse?
    var qualityOptions: [VideoQualityOption] = []
    var selectedQualityCode: Int?
    var selectedPlaybackRate: Double = 1.0
    var videoShotMetadata: VideoShotPreviewMetadata?
    var videoShotIsLoading = false
    var videoPages: [VideoPageListItem] = []
    var videoPagesIsLoading = false
    var isPlayingOfflineCache = false

    var relatedVideos: [VideoItem] = []
    var relatedIsLoading = false
    var relatedError: String?

    var ownerFollowerCount: Int?
    var ownerArchiveCount: Int?
    var isOwnerFollowing = false
    var isOwnerFollowRequesting = false
    var danmakuSegmentIndex = 1
    var danmakuElements: [Bilibili_Community_Service_Dm_V1_DanmakuElem] = []
    var danmakuIsLoading = false
    var danmakuError: String?
    var skipSegments: [SkipSegment] = []
    var skipSegmentsIsLoading = false
    var skipSegmentsError: String?
    var progressSkipSegments: [SkipSegment] {
        skipSegments.filter { $0.actionType == "skip" }
    }

    var fullSegments: [SkipSegment] {
        skipSegments.filter { $0.actionType == "full" }
    }

    private var loadedDanmakuSegments: Set<Int> = []
    private var loadingDanmakuSegments: Set<Int> = []
    private var danmakuSegments: [Int: [Bilibili_Community_Service_Dm_V1_DanmakuElem]] = [:]
    private var danmakuRenderCenter = 1
    private var danmakuCID: Int = 0
    private var skipSegmentsCID: Int = 0
    private var videoShotCID: Int = 0

    var isLiked = false
    var isDisliked = false
    var isCoined = false
    var isFavorited = false
    var isWatchLater = false

    var likeCount = 0
    var coinCount = 0
    var favoriteCount = 0

    var isLikeRequesting = false
    var isDislikeRequesting = false
    var isCoinRequesting = false
    var isFavoriteRequesting = false
    var isWatchLaterRequesting = false

    let bvid: String
    var aid: Int = 0
    var cid: Int = 0
    var title: String
    let cover: String
    var initialSeekTime: Double?
    private let requestedInitialSeekTime: Double?

    private var historyReportTimer: Timer?
    private var historyReportStartTask: Task<Void, Never>?
    private var videoShotWarmTask: Task<Void, Never>?
    private var lastReportedProgress = 0
    private var playerRebuildToken = UUID()
    private var isRebuildingPlayer = false
    private var isReloadingCurrentVideo = false

    var currentPlayerViewID: String {
        playerRebuildToken.uuidString
    }

    init(
        bvid: String,
        cid: Int = 0,
        title: String,
        cover: String,
        initialSeekTime: Double? = nil
    ) {
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.cover = cover
        self.requestedInitialSeekTime = initialSeekTime
        self.player = MPVKitPlayer()
    }

    // MARK: - Load Video Data

    func loadVideoData() async {
        isLoading = true
        error = nil
        playerInfo = nil
        initialSeekTime = requestedInitialSeekTime
        relatedVideos = []
        relatedIsLoading = false
        relatedError = nil
        videoPages = []
        videoPagesIsLoading = false
        ownerFollowerCount = nil
        ownerArchiveCount = nil
        isOwnerFollowing = false
        isOwnerFollowRequesting = false
        danmakuSegmentIndex = 1
        danmakuElements = []
        danmakuIsLoading = false
        danmakuError = nil
        skipSegments = []
        skipSegmentsIsLoading = false
        skipSegmentsError = nil
        loadedDanmakuSegments = []
        loadingDanmakuSegments = []
        danmakuSegments = [:]
        danmakuRenderCenter = 1
        danmakuCID = 0
        skipSegmentsCID = 0
        videoShotCID = 0
        isLiked = false
        isDisliked = false
        isCoined = false
        isFavorited = false
        isWatchLater = false
        likeCount = 0
        coinCount = 0
        favoriteCount = 0
        lastReportedProgress = 0
        videoShotMetadata = nil
        videoShotIsLoading = false
        isPlayingOfflineCache = false
        videoShotWarmTask?.cancel()
        videoShotWarmTask = nil

        let preferredCachedAsset = OfflineCacheStorage.loadPlayableAsset(
            bvid: bvid,
            cid: cid > 0 ? cid : nil
        )

        do {
            // 获取视频详情
            let detail: VideoDetailData
            if let preferredCachedAsset {
                detail = preferredCachedAsset.detail
            } else {
                detail = try await BiliAPI.shared.fetchVideoDetail(bvid: bvid)
            }
            await MainActor.run {
                self.videoDetail = detail
                self.aid = detail.aid
                if self.cid <= 0 {
                    self.cid = detail.cid
                }
                self.title = detail.title
                self.likeCount = detail.stat.like
                self.coinCount = detail.stat.coin
                self.favoriteCount = detail.stat.favorite
                self.videoPages = detail.pages.map {
                    VideoPageListItem(
                        cid: $0.cid,
                        page: $0.page,
                        part: $0.part,
                        duration: $0.duration,
                        firstFrame: nil
                    )
                }
            }

            Task {
                await loadVideoPages()
            }

            // 获取播放器信息（用于历史记录跳转播放/在线人数等；失败不阻塞播放）
            let currentCID = await MainActor.run { self.cid }
            var playbackCid = currentCID > 0 ? currentCID : detail.cid
            var playerInitialSeekTime: Double?
            if preferredCachedAsset == nil {
                do {
                    let playerInfoResponse = try await BiliAPI.shared.fetchPlayerWbiV2(
                        bvid: bvid,
                        cid: detail.cid
                    )
                    let playerInfoData = playerInfoResponse.data
                    let lastPlayCID = playerInfoData?.lastPlayCid
                    let lastPlayTimeMilliseconds = playerInfoData?.lastPlayTime
                    let resolvedInitialSeekTime: Double?
                    if let lastPlayTimeMilliseconds, lastPlayTimeMilliseconds > 0 {
                        let rawTime = Double(lastPlayTimeMilliseconds)
                        // Bilibili returns seconds on some player endpoints and
                        // milliseconds on others. Treat values beyond duration as ms.
                        resolvedInitialSeekTime = rawTime <= Double(detail.duration + 1)
                            ? rawTime
                            : rawTime / 1000.0
                    } else {
                        resolvedInitialSeekTime = nil
                    }

                    await MainActor.run {
                        self.playerInfo = playerInfoData
                    }

                    if currentCID <= 0, let lastPlayCID, lastPlayCID > 0 {
                        playbackCid = lastPlayCID
                    }
                    playerInitialSeekTime = resolvedInitialSeekTime
                } catch {
                    print("获取播放器信息失败: \(error)")
                }
            }

            let resolvedPlaybackCID = playbackCid
            let resolvedInitialSeekTime = requestedInitialSeekTime ?? playerInitialSeekTime

            await MainActor.run {
                self.cid = resolvedPlaybackCID
                self.initialSeekTime = resolvedInitialSeekTime
            }

            if SponsorBlockSettingsStore.load().isEnabled {
                let skipSegmentsCID = resolvedPlaybackCID
                Task {
                    await loadSkipSegments(cid: skipSegmentsCID)
                }
            }

            if let cachedAsset = OfflineCacheStorage.loadPlayableAsset(bvid: bvid, cid: resolvedPlaybackCID) ?? preferredCachedAsset {
                await MainActor.run {
                    self.danmakuElements = OfflineCacheStorage.loadDanmakuElements(
                        bvid: bvid,
                        cid: cachedAsset.item.cid
                    )
                    self.loadedDanmakuSegments = Set(1 ... max(1, Int(ceil(Double(max(cachedAsset.item.duration, 1)) / 360.0))))
                }
            } else {
                // 先加载第一包弹幕，供后续渲染层接入
                let firstDanmakuCID = resolvedPlaybackCID
                Task {
                    await loadDanmakuSegment(cid: firstDanmakuCID, segmentIndex: 1)
                }
            }

            let videoShotCID = resolvedPlaybackCID
            Task {
                await loadVideoShotMetadata(cid: videoShotCID)
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

            // 获取相关推荐（最多 40 条；失败不影响播放）
            Task {
                await loadRelatedVideos()
            }

            // 获取 UP 主粉丝/视频数（用于详情页展示；后续主页复用）
            Task {
                do {
                    let stats = try await BiliAPI.shared.fetchUserCardStats(mid: detail.owner.mid)
                    await MainActor.run {
                        self.ownerFollowerCount = stats.follower
                        self.ownerArchiveCount = stats.archiveCount
                        self.isOwnerFollowing = stats.following
                    }
                } catch {
                    // 忽略错误，避免影响播放；UI 保留占位
                    print("获取 UP 主信息失败: \(error)")
                }
            }

            if let cachedAsset = OfflineCacheStorage.loadPlayableAsset(bvid: bvid, cid: playbackCid) ?? preferredCachedAsset {
                await MainActor.run {
                    self.playUrlData = nil
                    self.qualityOptions = [
                        VideoQualityOption(
                            id: cachedAsset.item.qualityCode,
                            code: cachedAsset.item.qualityCode,
                            label: cachedAsset.item.qualityLabel
                        )
                    ]
                    self.selectedQualityCode = cachedAsset.item.qualityCode
                    self.dashStream = cachedAsset.stream
                    self.isPlayingOfflineCache = true
                    self.isLoading = false

                    if let player = self.player {
                        player.play(stream: cachedAsset.stream)
                        player.setPlaybackRate(self.selectedPlaybackRate)
                    }
                }
            } else {
                // 获取播放地址
                let playUrlResponse = try await BiliAPI.shared.fetchPlayUrl(
                    bvid: bvid,
                    cid: resolvedPlaybackCID
                )
                let options = DashStreamSelector.qualityOptions(from: playUrlResponse)
                let availableQualityCodes = options.map(\.code)
                let playbackSettings = AudioVideoSettingsStore.load()
                let preferredQuality = preferredQuality(for: playbackSettings)
                let defaultQuality = DashStreamSelector.resolvePreferredQualityCode(
                    from: availableQualityCodes,
                    preferred: preferredQuality
                )

                // 选择最优 DASH 流（按设置的默认画质和编码优先级）
                guard let quality = defaultQuality,
                      let stream = DashStreamSelector.selectStream(
                          from: playUrlResponse,
                          qualityCode: quality,
                          preferredCodec: playbackSettings.preferredCodec
                      )
                else {
                    throw APIError.noVideoOrAudio
                }

                await MainActor.run {
                    self.playUrlData = playUrlResponse
                    self.qualityOptions = options
                    self.selectedQualityCode = quality
                    self.dashStream = stream
                    self.isPlayingOfflineCache = false
                    self.isLoading = false

                    if let player = self.player {
                        player.play(stream: stream)
                        player.setPlaybackRate(self.selectedPlaybackRate)
                    }
                }
            }

            let (seekTime, activePlayer, resumeRate) = await MainActor.run {
                (self.initialSeekTime, self.player, self.selectedPlaybackRate)
            }

            // 历史记录跳转播放：等待播放器状态开始更新后再恢复，避免 load 后被底层 0 位置覆盖。
            if let seekTo = seekTime, seekTo > 0, let activePlayer {
                await restorePlaybackState(
                    on: activePlayer,
                    time: seekTo,
                    rate: resumeRate,
                    shouldResume: true
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

    @MainActor
    func switchQuality(to code: Int) async {
        guard selectedQualityCode != code,
              let playUrlData,
              let stream = DashStreamSelector.selectStream(
                  from: playUrlData,
                  qualityCode: code,
                  preferredCodec: AudioVideoSettingsStore.load().preferredCodec
              ),
              let player
        else { return }

        let resumeTime = player.currentTime
        let resumeRate = selectedPlaybackRate
        let shouldResume = player.isPlaying

        selectedQualityCode = code
        dashStream = stream
        player.play(stream: stream)
        player.setPlaybackRate(resumeRate)

        await restorePlaybackState(
            on: player,
            time: resumeTime,
            rate: resumeRate,
            shouldResume: shouldResume
        )
    }

    @MainActor
    func reloadCurrentVideoPreservingPlaybackState() async throws {
        guard !isReloadingCurrentVideo else { return }

        let targetCID = cid > 0 ? cid : (videoDetail?.cid ?? 0)
        guard targetCID > 0 else {
            throw NSError(
                domain: "VideoDetailViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无效的视频分P"]
            )
        }

        let currentPlayer = player
        let resumeTime = currentPlayer?.currentTime ?? 0
        let resumeRate = selectedPlaybackRate
        let shouldResume = currentPlayer?.isPlaying ?? true
        let preferredQualityCode = selectedQualityCode
        let playbackSettings = AudioVideoSettingsStore.load()
        let preferredCodec = playbackSettings.preferredCodec

        isReloadingCurrentVideo = true
        defer { isReloadingCurrentVideo = false }

        let playUrlResponse = try await BiliAPI.shared.fetchPlayUrl(
            bvid: bvid,
            cid: targetCID
        )
        let options = DashStreamSelector.qualityOptions(from: playUrlResponse)
        let availableQualityCodes = options.map(\.code)
        let fallbackQuality =
            DashStreamSelector.resolvePreferredQualityCode(
                from: availableQualityCodes,
                preferred: preferredQuality(for: playbackSettings)
            ) ?? availableQualityCodes.max()
        let targetQuality = preferredQualityCode.flatMap { code in
            availableQualityCodes.contains(code) ? code : nil
        } ?? fallbackQuality

        guard let resolvedQuality = targetQuality,
              let stream = DashStreamSelector.selectStream(
                  from: playUrlResponse,
                  qualityCode: resolvedQuality,
                  preferredCodec: preferredCodec
              )
        else {
            throw APIError.noVideoOrAudio
        }

        playUrlData = playUrlResponse
        qualityOptions = options
        selectedQualityCode = resolvedQuality
        dashStream = stream
        isPlayingOfflineCache = false
        error = nil

        guard let currentPlayer else { return }
        currentPlayer.play(stream: stream)
        currentPlayer.setPlaybackRate(resumeRate)

        await restorePlaybackState(
            on: currentPlayer,
            time: resumeTime,
            rate: resumeRate,
            shouldResume: shouldResume
        )
    }

    @MainActor
    func loadVideoPages() async {
        guard !videoPagesIsLoading else { return }
        videoPagesIsLoading = true
        defer { videoPagesIsLoading = false }

        do {
            let pages = try await BiliAPI.shared.fetchVideoPageList(bvid: bvid)
            if !pages.isEmpty {
                videoPages = pages
            }
        } catch {
            print("获取视频分P列表失败: \(error)")
        }
    }

    @MainActor
    func switchToPage(_ page: VideoPageListItem) async {
        guard page.cid > 0, page.cid != cid else { return }

        let previousIsPlaying = player?.isPlaying ?? true
        let playbackSettings = AudioVideoSettingsStore.load()
        let preferredCodec = playbackSettings.preferredCodec

        do {
            if let cachedAsset = OfflineCacheStorage.loadPlayableAsset(bvid: bvid, cid: page.cid) {
                cid = page.cid
                initialSeekTime = nil
                playUrlData = nil
                qualityOptions = [
                    VideoQualityOption(
                        id: cachedAsset.item.qualityCode,
                        code: cachedAsset.item.qualityCode,
                        label: cachedAsset.item.qualityLabel
                    )
                ]
                selectedQualityCode = cachedAsset.item.qualityCode
                dashStream = cachedAsset.stream
                videoShotMetadata = nil
                danmakuElements = OfflineCacheStorage.loadDanmakuElements(bvid: bvid, cid: page.cid)
                loadedDanmakuSegments = Set(1 ... max(1, Int(ceil(Double(max(page.duration, 1)) / 360.0))))
                loadingDanmakuSegments = []
                danmakuSegmentIndex = 1
                danmakuCID = page.cid
                skipSegments = []
                skipSegmentsCID = 0
                videoShotCID = 0
                error = nil
                isPlayingOfflineCache = true

                if let player {
                    player.play(stream: cachedAsset.stream)
                    player.setPlaybackRate(selectedPlaybackRate)
                    if previousIsPlaying {
                        player.resume()
                    } else {
                        player.pause()
                    }
                }

                Task {
                    await loadVideoShotMetadata(cid: page.cid)
                }
                if SponsorBlockSettingsStore.load().isEnabled {
                    Task {
                        await loadSkipSegments(cid: page.cid)
                    }
                }
                return
            }

            let playerInfoResponse = try? await BiliAPI.shared.fetchPlayerWbiV2(
                bvid: bvid,
                cid: page.cid
            )
            let playUrlResponse = try await BiliAPI.shared.fetchPlayUrl(
                bvid: bvid,
                cid: page.cid
            )
            let options = DashStreamSelector.qualityOptions(from: playUrlResponse)
            let availableQualityCodes = options.map(\.code)
            let fallbackQuality = availableQualityCodes.max()
            let targetQuality = selectedQualityCode.flatMap { code in
                availableQualityCodes.contains(code) ? code : nil
            } ?? fallbackQuality

            guard let resolvedQuality = targetQuality,
                  let stream = DashStreamSelector.selectStream(
                      from: playUrlResponse,
                      qualityCode: resolvedQuality,
                      preferredCodec: preferredCodec
                  )
            else {
                throw APIError.noVideoOrAudio
            }

            cid = page.cid
            playerInfo = playerInfoResponse?.data
            initialSeekTime = nil
            playUrlData = playUrlResponse
            qualityOptions = options
            selectedQualityCode = resolvedQuality
            dashStream = stream
            videoShotMetadata = nil
            danmakuElements = []
            loadedDanmakuSegments = []
            loadingDanmakuSegments = []
            danmakuSegments = [:]
            danmakuRenderCenter = 1
            danmakuSegmentIndex = 1
            danmakuCID = 0
            skipSegments = []
            skipSegmentsCID = 0
            videoShotCID = 0
            error = nil
            isPlayingOfflineCache = false

            if let player {
                player.play(stream: stream)
                player.setPlaybackRate(selectedPlaybackRate)
                if previousIsPlaying {
                    player.resume()
                } else {
                    player.pause()
                }
            }

            Task {
                await loadDanmakuSegment(cid: page.cid, segmentIndex: 1)
            }
            Task {
                await loadVideoShotMetadata(cid: page.cid)
            }
            if SponsorBlockSettingsStore.load().isEnabled {
                Task {
                    await loadSkipSegments(cid: page.cid)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func preferredQuality(for settings: AudioVideoSettings) -> PreferredVideoQuality {
        if NetworkTypeMonitor.shared.isCellularConnection {
            return settings.cellularDefaultQuality
        }
        return settings.defaultQuality
    }

    @MainActor
    func setPlaybackRate(_ rate: Double) {
        selectedPlaybackRate = rate
        player?.setPlaybackRate(rate)
    }

    @MainActor
    func rebuildPlayerPreservingState() async {
        guard !isRebuildingPlayer else { return }
        isRebuildingPlayer = true
        defer { isRebuildingPlayer = false }

        guard let oldPlayer = player, let stream = dashStream else { return }

        let resumeTime = oldPlayer.currentTime
        let resumeRate = selectedPlaybackRate
        let shouldResume = oldPlayer.isPlaying

        oldPlayer.pause()

        let newPlayer = MPVKitPlayer()
        player = newPlayer
        playerRebuildToken = UUID()

        newPlayer.play(stream: stream)
        newPlayer.setPlaybackRate(resumeRate)

        // Restore after readiness with retries; fixed delay is too flaky on rotation.
        await restorePlaybackState(
            on: newPlayer,
            time: resumeTime,
            rate: resumeRate,
            shouldResume: shouldResume
        )
    }

    @MainActor
    private func restorePlaybackState(
        on player: MPVKitPlayer,
        time: Double,
        rate: Double,
        shouldResume: Bool
    ) async {
        let targetTime = max(0, time)

        // Wait for player state to start updating (controller attached / file loaded).
        for _ in 0 ..< 20 {
            if player.duration > 0 || player.currentTime > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 100000000)
        }

        player.seek(to: targetTime)
        player.setPlaybackRate(rate)

        if shouldResume {
            player.resume()
        } else {
            player.pause()
        }

        // One more correction pass to reduce occasional drift after stream rebuild.
        for _ in 0 ..< 6 {
            try? await Task.sleep(nanoseconds: 120000000)
            if abs(player.currentTime - targetTime) <= 1.0 {
                break
            }
            player.seek(to: targetTime)
        }

        if !shouldResume {
            player.pause()
        }
    }

    @MainActor
    func loadRelatedVideos() async {
        guard !relatedIsLoading else { return }
        relatedIsLoading = true
        relatedError = nil

        do {
            let videos = try await BiliAPI.shared.fetchRelatedVideos(bvid: bvid, limit: 40)
            relatedVideos = videos
        } catch {
            relatedError = error.localizedDescription
            relatedVideos = []
        }

        relatedIsLoading = false
    }

    @MainActor
    func loadDanmakuSegment(cid: Int? = nil, segmentIndex: Int = 1) async {
        guard !isPlayingOfflineCache else { return }
        let targetCid = cid ?? self.cid
        guard targetCid > 0 else {
            danmakuError = "无效的 cid"
            danmakuElements = []
            return
        }

        if danmakuCID != targetCid {
            danmakuCID = targetCid
            loadedDanmakuSegments = []
            loadingDanmakuSegments = []
            danmakuSegments = [:]
            danmakuRenderCenter = 1
            danmakuElements = []
            danmakuSegmentIndex = 1
        }
        guard !loadedDanmakuSegments.contains(segmentIndex) else { return }
        guard !loadingDanmakuSegments.contains(segmentIndex) else { return }

        danmakuIsLoading = true
        danmakuError = nil
        danmakuSegmentIndex = segmentIndex
        loadingDanmakuSegments.insert(segmentIndex)

        do {
            let reply = try await BiliAPI.shared.fetchDanmakuSegment(
                cid: targetCid,
                segmentIndex: segmentIndex
            )
            guard danmakuCID == targetCid else {
                loadingDanmakuSegments.remove(segmentIndex)
                danmakuIsLoading = !loadingDanmakuSegments.isEmpty
                return
            }
            loadedDanmakuSegments.insert(segmentIndex)
            loadingDanmakuSegments.remove(segmentIndex)
            mergeDanmakuElements(reply.elems, for: segmentIndex)
        } catch {
            loadingDanmakuSegments.remove(segmentIndex)
            danmakuError = error.localizedDescription
        }

        danmakuIsLoading = !loadingDanmakuSegments.isEmpty
    }

    @MainActor
    func loadSkipSegments(
        cid: Int? = nil,
        refreshServerCache: Bool = false
    ) async {
        let targetCid = cid ?? self.cid
        skipSegmentsCID = targetCid
        skipSegmentsIsLoading = true
        skipSegmentsError = nil
        defer {
            if skipSegmentsCID == targetCid {
                skipSegmentsIsLoading = false
            }
        }

        do {
            let segments = try await SponsorBlockAPI.fetchSkipSegments(
                videoID: bvid,
                cid: targetCid > 0 ? targetCid : nil,
                refreshServerCache: refreshServerCache
            )
            guard skipSegmentsCID == targetCid else { return }
            skipSegments = segments
        } catch {
            guard skipSegmentsCID == targetCid else { return }
            skipSegments = []
            skipSegmentsError = error.localizedDescription
        }
    }

    @MainActor
    func preloadDanmakuIfNeeded(currentTime: Double) async {
        guard !isPlayingOfflineCache else { return }
        let targetCid = cid
        guard targetCid > 0 else { return }

        let currentSegment = max(1, Int(currentTime / 360.0) + 1)
        danmakuRenderCenter = currentSegment
        await loadDanmakuSegment(cid: targetCid, segmentIndex: currentSegment)
        await loadDanmakuSegment(cid: targetCid, segmentIndex: currentSegment + 1)
        // The previous segment is needed for a seek just after a 6-minute boundary:
        // those scroll items can still be visible for up to the configured duration.
        if currentSegment > 1 {
            await loadDanmakuSegment(cid: targetCid, segmentIndex: currentSegment - 1)
        }
        updateDanmakuRenderWindow(around: currentSegment)
    }

    @MainActor
    func loadVideoShotMetadata(cid: Int? = nil) async {
        let targetCid = cid ?? self.cid
        guard targetCid > 0 else { return }
        guard !(videoShotCID == targetCid && videoShotMetadata != nil) else { return }

        videoShotCID = targetCid
        videoShotIsLoading = true
        defer {
            if videoShotCID == targetCid {
                videoShotIsLoading = false
            }
        }

        do {
            let metadata = try await BiliAPI.shared.fetchVideoShotPreview(
                bvid: bvid,
                cid: targetCid
            )
            guard videoShotCID == targetCid else { return }
            videoShotMetadata = metadata
            warmVideoShotSpriteSheetsIfNeeded()
        } catch {
            print("加载视频快照预览失败: \(error)")
        }
    }

    private func warmVideoShotSpriteSheetsIfNeeded() {
        guard let spriteSheetURLs = videoShotMetadata?.spriteSheetURLs, !spriteSheetURLs.isEmpty else {
            return
        }

        videoShotWarmTask?.cancel()
        videoShotWarmTask = Task(priority: .utility) {
            let session = URLSession.shared
            for url in spriteSheetURLs {
                if Task.isCancelled { return }

                let request = URLRequest(
                    url: url,
                    cachePolicy: .returnCacheDataElseLoad,
                    timeoutInterval: 30
                )
                do {
                    _ = try await session.data(for: request)
                } catch {
                    continue
                }
            }
        }
    }

    @MainActor
    private func mergeDanmakuElements(
        _ newItems: [Bilibili_Community_Service_Dm_V1_DanmakuElem],
        for segmentIndex: Int
    ) {
        danmakuSegments[segmentIndex] = newItems
        updateDanmakuRenderWindow(around: danmakuRenderCenter)
    }

    /// Keeps only a small segment cache and exposes a bounded, stable-ID render window.
    private func updateDanmakuRenderWindow(around currentSegment: Int) {
        let window = Set(max(1, currentSegment - 1) ... currentSegment + 2)
        danmakuSegments = danmakuSegments.filter { window.contains($0.key) }
        loadedDanmakuSegments = loadedDanmakuSegments.filter(window.contains)

        var merged: [Bilibili_Community_Service_Dm_V1_DanmakuElem] = []
        for index in window.sorted() {
            merged.append(contentsOf: danmakuSegments[index] ?? [])
        }
        var seen: Set<Int64> = []
        danmakuElements = merged
            .filter { elem in
                if seen.contains(elem.id) { return false }
                seen.insert(elem.id)
                return true
            }
            .sorted { lhs, rhs in
                if lhs.progress == rhs.progress {
                    return lhs.id < rhs.id
                }
                return lhs.progress < rhs.progress
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

    func toggleOwnerFollow() async throws {
        guard !isOwnerFollowRequesting else { return }
        guard let ownerMid = videoDetail?.owner.mid, ownerMid > 0 else { return }

        isOwnerFollowRequesting = true
        let wasFollowing = isOwnerFollowing
        let previousFollowerCount = ownerFollowerCount

        // 乐观更新，提升点击反馈速度
        isOwnerFollowing.toggle()
        if var followerCount = ownerFollowerCount {
            if wasFollowing {
                followerCount = max(0, followerCount - 1)
            } else {
                followerCount += 1
            }
            ownerFollowerCount = followerCount
        }

        do {
            let act = wasFollowing ? 2 : 1
            try await BiliAPI.shared.modifyUserRelation(fid: ownerMid, act: act)
        } catch {
            // 失败时回滚状态，避免 UI 与服务端不一致
            isOwnerFollowing = wasFollowing
            ownerFollowerCount = previousFollowerCount
            isOwnerFollowRequesting = false
            throw error
        }

        isOwnerFollowRequesting = false
    }

    func addToWatchLater() {
        Task { await addToWatchLaterAsync() }
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

    @MainActor
    private func addToWatchLaterAsync() async {
        guard !isWatchLaterRequesting else { return }
        guard !isWatchLater else { return }
        guard !bvid.isEmpty else { return }

        isWatchLaterRequesting = true
        do {
            try await BiliAPI.shared.addToWatchLater(bvid: bvid)
            isWatchLater = true
        } catch {
            self.error = error.localizedDescription
        }
        isWatchLaterRequesting = false
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
        guard !isPlayingOfflineCache else { return }
        historyReportStartTask?.cancel()
        historyReportTimer?.invalidate()
        historyReportTimer = nil

        historyReportStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1000000000)
            guard let self, !Task.isCancelled, let player = self.player else { return }

	            self.reportHistoryIfNeeded(with: player)

	            self.historyReportTimer = Timer.scheduledTimer(
	                withTimeInterval: 15,
	                repeats: true
	            ) { [weak self] _ in
	                guard let self, let currentPlayer = self.player else { return }
	                self.reportHistoryIfNeeded(with: currentPlayer)
	            }
	        }
	    }

    private func reportHistoryIfNeeded(with player: MPVKitPlayer) {
        guard !isPlayingOfflineCache else { return }
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
        historyReportStartTask?.cancel()
        historyReportStartTask = nil
        historyReportTimer?.invalidate()
        historyReportTimer = nil

        guard !isPlayingOfflineCache else { return }

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
        historyReportStartTask?.cancel()
        historyReportTimer?.invalidate()
        player?.stop()
    }
}

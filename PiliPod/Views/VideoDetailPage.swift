//
//  VideoDetailPage.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Observation
import SwiftUI
#if canImport(UIKit)
import MediaPlayer
import UIKit
#endif

struct VideoDetailPage: View {
    private static let introBVPattern = try? NSRegularExpression(
        pattern: #"BV[0-9A-Za-z]{10}"#
    )

    enum SponsorBlockDraftActionType: String, CaseIterable, Hashable {
        case skip
        case fill

        var title: String {
            switch self {
            case .skip:
                return "跳过"
            case .fill:
                return "整个视频"
            }
        }
    }

    struct SponsorBlockDraftSegment: Identifiable, Equatable {
        let id = UUID()
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        var category: SponsorBlockCategory = .sponsor
        var actionType: SponsorBlockDraftActionType = .skip
    }

    private struct PlaybackSponsorSegment: Identifiable, Equatable {
        let id: String
        let uuid: String
        let category: SponsorBlockCategory
        let behavior: SponsorBlockSegmentBehavior
        let start: TimeInterval
        let end: TimeInterval

        var displayTitle: String { category.title }
    }

    private enum FullscreenTrigger {
        case none
        case manual
        case rotation
    }

    private enum DragInteractionMode {
        case none
        case speedBoost
        case horizontalSeek
        case brightnessAdjust
        case volumeAdjust
    }

    @State var viewModel: VideoDetailViewModel
    @State private var showDebugPanel = false
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isVideoDetailExpanded = false
    @State private var isFavoriteSheetPresented = false
    @State private var favoriteFolders: [FavoriteFolderItem] = []
    @State private var favoriteSelectedIds: Set<Int64> = []
    @State private var favoriteInitiallySelectedIds: Set<Int64> = []
    @State private var favoriteIsLoading = false
    @State private var selectedRelatedVideo: VideoItem?
    @State private var selectedUserSpaceRoute: UserSpaceRoute?
    @State private var isSpeedBoostActive = false
    @State private var speedBoostMultiplier: Double = 2.0
    @State private var isSpeedBoostPressing = false
    @State private var speedBoostTriggerTask: Task<Void, Never>?
    @State private var isHorizontalSeeking = false
    @State private var horizontalSeekBaseTime: TimeInterval = 0
    @State private var horizontalSeekPreviewTime: TimeInterval?
    @State private var progressDragPreviewTime: TimeInterval?
    @State private var isBrightnessAdjusting = false
    @State private var brightnessAdjustBaseValue: Double = 0
    @State private var brightnessPreviewValue: Double = 0
    @State private var isVolumeAdjusting = false
    @State private var volumeAdjustBaseValue: Double = 0
    @State private var volumePreviewValue: Double = 0
    @State private var systemVolumeControl = SystemVolumeController()
    @State private var dragInteractionMode: DragInteractionMode = .none
    @State private var danmakuConfig = DanmakuConfigStore.load()
    @State private var isDanmakuSettingsPresented = false
    @State private var isFullscreen = false
    @State private var fullscreenTrigger: FullscreenTrigger = .none
    @State private var isFullscreenDanmakuPanelVisible = false
    @State private var lastDanmakuPrefetchSegment = 0
    @State private var selectedTab: VideoDetailTab = .intro
    @State private var isDraggingVideoPageStrip = false
    @State private var toastMessage: String?
    @State private var sponsorBlockSettings = SponsorBlockSettingsStore.load()
    @State private var skippedSponsorSegmentIDs: Set<String> = []
    @State private var hiddenManualSponsorSegmentIDs: Set<String> = []
    @State private var manualSkipSegment: PlaybackSponsorSegment?
    @State private var showsSponsorList = false
    @State private var sponsorSegmentVotes: [String: SponsorBlockVoteSelection] = [:]
    @State private var sponsorSegmentCategoryOverrides: [String: SponsorBlockCategory] = [:]
    @State private var showsSponsorSubmitSheet = false
    @State private var sponsorDraftSegments: [SponsorBlockDraftSegment] = []
    @State private var sponsorSubmitErrorText: String?
    @State private var sponsorIsSubmitting = false
    @State private var previewDraftSegmentID: SponsorBlockDraftSegment.ID?
    @State private var showsVideoPageDrawer = false
    @State private var playerUISnapshot = PlayerUIPlaybackSnapshot()
    @State private var debugPanelRefreshTask: Task<Void, Never>?
    @State private var lastNowPlayingSyncedSecond: Int?
    @State private var cachedIntroDescriptionText = AttributedString("")
    @State private var shouldResumeAfterBackgroundPause = false
    @State private var backgroundPauseRestoreTime: TimeInterval?
    @State private var offlineCachePrefill: OfflineCacheQueryPrefill?
#if canImport(UIKit)
    @State private var preferredFullscreenOrientation: UIInterfaceOrientation = .landscapeRight
    @StateObject private var audioSessionManager = VideoPlaybackAudioSessionManager()
#endif

    let video: VideoItem
    let namespace: Namespace.ID
    let onBack: () -> Void
    private let maxHorizontalSeekOffset: TimeInterval = 50
    private let verticalBrightnessDragSensitivity: Double = 2.5

    private var heroID: String { "videoHero.\(video.bvid)" }
    private var progressSegments: [ProgressSegment] {
        let duration = resolvedVideoDuration
        guard duration > 0, sponsorBlockSettings.isEnabled else { return [] }

        return playableSponsorSegments.compactMap { segment -> ProgressSegment? in
            guard let color = progressColorForCategory(segment.category.rawValue) else { return nil }

            return ProgressSegment(
                start: segment.start / duration,
                end: segment.end / duration,
                color: color,
                opacity: 0.8
            )
        }
    }

    private var fullSegmentBanner: (text: String, color: Color)? {
        guard sponsorBlockSettings.isEnabled else { return nil }
        for segment in viewModel.fullSegments {
            if let category = sponsorCategory(for: segment),
               let banner = fullSegmentBannerInfo(for: category.rawValue)
            {
                return banner
            }
        }
        return nil
    }

    private var fullSegmentBannerCategoryRawValue: String? {
        guard sponsorBlockSettings.isEnabled else { return nil }
        for segment in viewModel.fullSegments {
            if let category = sponsorCategory(for: segment),
               fullSegmentBannerInfo(for: category.rawValue) != nil
            {
                return category.rawValue
            }
        }
        return nil
    }

    private var playableSponsorSegments: [PlaybackSponsorSegment] {
        guard sponsorBlockSettings.isEnabled else { return [] }
        let duration = resolvedVideoDuration
        guard duration > 0 else { return [] }

        return viewModel.progressSkipSegments.compactMap { segment -> PlaybackSponsorSegment? in
            guard let category = sponsorCategory(for: segment) else { return nil }
            let behavior = sponsorBlockSettings.behavior(for: category)
            guard behavior != .disabled else { return nil }
            guard segment.segment.count >= 2 else { return nil }

            let start = min(max(segment.segment[0], 0), duration)
            let end = min(max(segment.segment[1], start), duration)
            guard end > start else { return nil }

            return PlaybackSponsorSegment(
                id: segment.segmentID,
                uuid: segment.segmentID,
                category: category,
                behavior: behavior,
                start: start,
                end: end
            )
        }
    }

    private var allSponsorSegments: [SkipSegment] {
        viewModel.skipSegments.sorted { lhs, rhs in
            let lhsStart = lhs.segment.first ?? 0
            let rhsStart = rhs.segment.first ?? 0
            if lhsStart == rhsStart {
                return lhs.segmentID < rhs.segmentID
            }
            return lhsStart < rhsStart
        }
    }

    private var showsSponsorButton: Bool {
        sponsorBlockSettings.isEnabled
    }

    private var showsSponsorInfoButton: Bool {
        sponsorBlockSettings.isEnabled && !allSponsorSegments.isEmpty
    }

    private var previewDraftSegment: SponsorBlockDraftSegment? {
        guard let previewDraftSegmentID else { return nil }
        return sponsorDraftSegments.first(where: { $0.id == previewDraftSegmentID })
    }

    private var resolvedVideoDuration: TimeInterval {
        if playerUISnapshot.duration > 0 {
            return playerUISnapshot.duration
        }
        if let detailDuration = viewModel.videoDetail?.duration, detailDuration > 0 {
            return TimeInterval(detailDuration)
        }
        if video.duration > 0 {
            return TimeInterval(video.duration)
        }
        return 0
    }

    private var currentVideoPage: VideoPageListItem? {
        if let page = viewModel.videoPages.first(where: { $0.cid == viewModel.cid }) {
            return page
        }
        return viewModel.videoPages.first
    }

    init(video: VideoItem, namespace: Namespace.ID, onBack: @escaping () -> Void) {
        self.video = video
        self.namespace = namespace
        self.onBack = onBack
        _viewModel = State(initialValue: VideoDetailViewModel(
            bvid: video.bvid,
            cid: video.cid ?? 0,
            title: video.title,
            cover: video.cover
        ))
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    // DASH 播放器
                    if let stream = bindableViewModel.dashStream, let
                        player = bindableViewModel.player
                    {
                        ZStack(alignment: .center) {
                            // DASH 播放器容器
                            MPVKitPlayerView(player: player)
                                .id(bindableViewModel.currentPlayerViewID)
                                .aspectRatio(stream.aspectRatio, contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: isFullscreen ? .infinity : nil, alignment: .center)
                                .clipped()
                                .ignoresSafeArea(isFullscreen ? .all : [])
                                .background(Color.black)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showControlsAndAutoHideIfNeeded(player: player)
                                }
                                .highPriorityGesture(
                                    TapGesture(count: 2)
                                        .onEnded {
                                            togglePlayback(player: player)
                                            showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                        }
                                )
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if dragInteractionMode == .horizontalSeek {
                                                let width = max(1, geo.size.width)
                                                let ratio = Double(value.translation.width / width)
                                                let delta = ratio * maxHorizontalSeekOffset
                                                let target = clampSeekTime(horizontalSeekBaseTime + delta, duration: playerUISnapshot.duration)
                                                horizontalSeekPreviewTime = target
                                                return
                                            }

                                            if dragInteractionMode == .brightnessAdjust {
                                                let height = max(1, geo.size.height)
                                                let delta = Double(-value.translation.height / height) * verticalBrightnessDragSensitivity
                                                let target = clampUnit(brightnessAdjustBaseValue + delta)
                                                brightnessPreviewValue = target
                                                setScreenBrightness(target)
                                                return
                                            }

                                            if dragInteractionMode == .volumeAdjust {
                                                let height = max(1, geo.size.height)
                                                let delta = Double(-value.translation.height / height) * verticalBrightnessDragSensitivity
                                                let target = clampUnit(volumeAdjustBaseValue + delta)
                                                volumePreviewValue = target
                                                setSystemVolume(target)
                                                return
                                            }

                                            if dragInteractionMode == .speedBoost {
                                                return
                                            }

                                            let dx = value.translation.width
                                            let dy = value.translation.height
                                            let shouldStartHorizontalSeek =
                                                !isHorizontalSeeking &&
                                                abs(dx) > 18 &&
                                                abs(dx) > abs(dy)

                                            if shouldStartHorizontalSeek {
                                                dragInteractionMode = .horizontalSeek
                                                isHorizontalSeeking = true
                                                horizontalSeekBaseTime = playerUISnapshot.currentTime
                                                speedBoostTriggerTask?.cancel()
                                                speedBoostTriggerTask = nil
                                                isSpeedBoostPressing = false
                                                endSpeedBoostIfNeeded(player: player)
                                            }

                                            if isHorizontalSeeking {
                                                let width = max(1, geo.size.width)
                                                let ratio = Double(dx / width)
                                                let delta = ratio * maxHorizontalSeekOffset
                                                let target = clampSeekTime(horizontalSeekBaseTime + delta, duration: playerUISnapshot.duration)
                                                horizontalSeekPreviewTime = target
                                                return
                                            }

                                            let shouldStartBrightnessAdjust =
                                                !isHorizontalSeeking &&
                                                !isBrightnessAdjusting &&
                                                value.startLocation.x <= geo.size.width * 0.5 &&
                                                abs(dy) > 18 &&
                                                abs(dy) > abs(dx)

                                            if shouldStartBrightnessAdjust {
                                                dragInteractionMode = .brightnessAdjust
                                                isBrightnessAdjusting = true
                                                brightnessAdjustBaseValue = currentScreenBrightness()
                                                brightnessPreviewValue = brightnessAdjustBaseValue
                                                speedBoostTriggerTask?.cancel()
                                                speedBoostTriggerTask = nil
                                                isSpeedBoostPressing = false
                                                endSpeedBoostIfNeeded(player: player)
                                            }

                                            if isBrightnessAdjusting {
                                                let height = max(1, geo.size.height)
                                                let delta = Double(-dy / height) * verticalBrightnessDragSensitivity
                                                let target = clampUnit(brightnessAdjustBaseValue + delta)
                                                brightnessPreviewValue = target
                                                setScreenBrightness(target)
                                                return
                                            }

                                            let shouldStartVolumeAdjust =
                                                !isHorizontalSeeking &&
                                                !isBrightnessAdjusting &&
                                                !isVolumeAdjusting &&
                                                value.startLocation.x > geo.size.width * 0.5 &&
                                                abs(dy) > 18 &&
                                                abs(dy) > abs(dx)

                                            if shouldStartVolumeAdjust {
                                                dragInteractionMode = .volumeAdjust
                                                isVolumeAdjusting = true
                                                volumeAdjustBaseValue = currentSystemVolume()
                                                volumePreviewValue = volumeAdjustBaseValue
                                                speedBoostTriggerTask?.cancel()
                                                speedBoostTriggerTask = nil
                                                isSpeedBoostPressing = false
                                                endSpeedBoostIfNeeded(player: player)
                                            }

                                            if isVolumeAdjusting {
                                                let height = max(1, geo.size.height)
                                                let delta = Double(-dy / height) * verticalBrightnessDragSensitivity
                                                let target = clampUnit(volumeAdjustBaseValue + delta)
                                                volumePreviewValue = target
                                                setSystemVolume(target)
                                                return
                                            }

                                            if !isSpeedBoostPressing {
                                                isSpeedBoostPressing = true
                                                speedBoostTriggerTask?.cancel()
                                                speedBoostTriggerTask = Task { @MainActor in
                                                    do {
                                                        try await Task.sleep(nanoseconds: 200000000)
                                                    } catch {
                                                        return
                                                    }
                                                    if isSpeedBoostPressing {
                                                        beginSpeedBoostIfNeeded(player: player)
                                                    }
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            if dragInteractionMode == .horizontalSeek, isHorizontalSeeking {
                                                if let seekTarget = horizontalSeekPreviewTime {
                                                    seekPlayback(to: seekTarget, player: player)
                                                }
                                                horizontalSeekPreviewTime = nil
                                                isHorizontalSeeking = false
                                            }
                                            if isBrightnessAdjusting {
                                                isBrightnessAdjusting = false
                                            }
                                            if isVolumeAdjusting {
                                                isVolumeAdjusting = false
                                            }

                                            isSpeedBoostPressing = false
                                            speedBoostTriggerTask?.cancel()
                                            speedBoostTriggerTask = nil
                                            endSpeedBoostIfNeeded(player: player)
                                            dragInteractionMode = .none
                                        }
                                )
                                .overlay {
                                    DanmakuOverlayView(
                                        currentTime: player.currentTime,
                                        isPlaying: player.isPlaying,
                                        elements: bindableViewModel.danmakuElements,
                                        config: fullscreenAwareDanmakuConfig
                                    )
                                }
                                .overlay {
                                    PlayerLoadingOverlay(
                                        isVisible: playerUISnapshot.isBuffering,
                                        speedBytesPerSecond: playerUISnapshot.loadingSpeedBytesPerSecond
                                    )
                                    .allowsHitTesting(false)
                                }
                                .overlay {
                                    if isFullscreen && controlsVisible {
                                        VStack(spacing: 0) {
                                            LinearGradient(
                                                colors: [Color.black.opacity(0.65), Color.black.opacity(0)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                            .frame(height: 60 + geo.safeAreaInsets.top / 2)
                                            .frame(maxWidth: .infinity, alignment: .top)

                                            Spacer(minLength: 0)

                                            LinearGradient(
                                                colors: [Color.black.opacity(0), Color.black.opacity(0.68)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                            .frame(height: 65 + geo.safeAreaInsets.bottom / 2)
                                            .frame(maxWidth: .infinity, alignment: .bottom)
                                        }
                                        .ignoresSafeArea()
                                        .allowsHitTesting(false)
                                    }
                                }
                                .overlay {
                                    if !isFullscreen && !controlsVisible {
                                        ReadOnlyVideoProgressBar(
                                            currentTime: activeSeekPreviewTime(duration: playerUISnapshot.duration) ?? playerUISnapshot.currentTime,
                                            duration: playerUISnapshot.duration,
                                            bufferedUntil: playerUISnapshot.bufferedUntil,
                                            segments: progressSegments
                                        )
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                        .allowsHitTesting(false)
                                    }
                                }
                                .overlay {
                                    PlayerControlsOverlay(
                                        danmakuEnabled: $danmakuConfig.isEnabled,
                                        onShowDanmakuSettings: {
                                            if isFullscreen {
                                                isFullscreenDanmakuPanelVisible.toggle()
                                            } else {
                                                isDanmakuSettingsPresented = true
                                            }
                                        },
                                        onShowSponsorSegments: {
                                            showsSponsorList.toggle()
                                        },
                                        onShowSponsorSubmit: {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                                openSponsorSubmitDrawer()
                                            }
                                        },
                                        isFullscreen: isFullscreen,
                                        isFullscreenDanmakuPanelVisible: isFullscreenDanmakuPanelVisible,
                                        qualityOptions: bindableViewModel.qualityOptions,
                                        selectedQualityCode: bindableViewModel.selectedQualityCode,
                                        selectedPlaybackRate: bindableViewModel.selectedPlaybackRate,
                                        isVisible: controlsVisible,
                                        showsSponsorButton: showsSponsorButton,
                                        showsSponsorInfoButton: showsSponsorInfoButton,
                                        currentTime: activeSeekPreviewTime(duration: playerUISnapshot.duration) ?? playerUISnapshot.currentTime,
                                        duration: playerUISnapshot.duration,
                                        bufferedUntil: playerUISnapshot.bufferedUntil,
                                        isPlaying: playerUISnapshot.isPlaying,
                                        segments: progressSegments,
                                        onBack: { handleBackAction() },
                                        onUserInteracted: {
                                            showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                        },
                                        onTogglePlayPause: {
                                            togglePlayback(player: player)
                                        },
                                        onSeek: { time in
                                            seekPlayback(to: time, player: player)
                                            showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                        },
                                        onFullscreen: {
                                            toggleFullscreenManually()
                                        },
                                        onCacheVideo: {
                                            offlineCachePrefill = OfflineCacheQueryPrefill(
                                                bvid: viewModel.bvid,
                                                cid: viewModel.cid > 0 ? viewModel.cid : video.cid
                                            )
                                        },
                                        onShowVideoStreamInfo: {
                                            showDebugPanel.toggle()
                                        },
                                        onSelectQuality: { code in
                                            Task { @MainActor in
                                                await bindableViewModel.switchQuality(to: code)
                                            }
                                        },
                                        onSelectPlaybackRate: { rate in
                                            bindableViewModel.setPlaybackRate(rate)
                                        },
                                        onSeekPreviewChanged: { previewTime in
                                            progressDragPreviewTime = previewTime
                                        }
                                    )
                                }
                                .overlay(alignment: .trailing) {
                                    if controlsVisible && isFullscreen && isFullscreenDanmakuPanelVisible {
                                        DanmakuSettingsPanel(
                                            config: $danmakuConfig,
                                            onClose: {
                                                isFullscreenDanmakuPanelVisible = false
                                            }
                                        )
                                        .padding(.trailing, 12)
                                        .transition(.move(edge: .trailing).combined(with: .opacity))
                                    }
                                }
                                .overlay(alignment: .top) {
                                    if let seekPreview = activeSeekPreviewTime(duration: playerUISnapshot.duration) {
                                        Text("\(formatMMSS(seekPreview))/\(formatMMSS(playerUISnapshot.duration))")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .glassEffect(.regular, in: .capsule)
                                            .padding(.top, 12)
                                            .transition(.opacity)
                                    } else if isSpeedBoostActive {
                                        Text(formatSpeedBoostLabel(speedBoostMultiplier))
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .glassEffect(.regular, in: .capsule)
                                            .padding(.top, 12)
                                            .transition(.opacity)
                                    }
                                }
                                .overlay {
                                    if let previewTime = activeSeekPreviewTime(duration: playerUISnapshot.duration) {
                                        VideoShotPreviewCard(
                                            frame: bindableViewModel.videoShotMetadata?.frame(at: previewTime),
                                            fallbackAspectRatio: stream.aspectRatio
                                        )
                                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                    }
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if let manualSkipSegment {
                                        Button {
                                            performManualSponsorSkip(for: manualSkipSegment, player: player)
                                        } label: {
                                            Text("跳过：\(manualSkipSegment.displayTitle)")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.primary)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 9)
                                                .glassEffect(
                                                    .regular.interactive(),
                                                    in: Capsule()
                                                )
                                        }
                                        .tint(.primary)
                                        .padding(.leading, 16)
                                        .padding(.bottom, isFullscreen ? 120 : 50)
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                    }
                                }
                                .overlay {
                                    if isBrightnessAdjusting {
                                        HStack(alignment: .center, spacing: 10) {
                                            Image(systemName: "sun.max")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white)
                                            GeometryReader { brightnessGeo in
                                                let barWidth = max(1, brightnessGeo.size.width)
                                                ZStack(alignment: .leading) {
                                                    Capsule(style: .continuous)
                                                        .fill(Color.white.opacity(0.24))
                                                        .frame(height: 4)
                                                    Capsule(style: .continuous)
                                                        .fill(Color.white.opacity(0.95))
                                                        .frame(width: barWidth * clampUnit(brightnessPreviewValue), height: 4)
                                                }
                                                .padding(.top, 2)
                                            }
                                            .frame(width: 100, height: 10)
                                        }
                                        .frame(height: 24, alignment: .center)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .glassEffect(.clear.tint(.black), in: .capsule)
                                        .transition(.opacity)
                                    }
                                }
                                .overlay {
                                    if isVolumeAdjusting {
                                        HStack(alignment: .center, spacing: 10) {
                                            Image(systemName: "speaker.wave.3",
                                                  variableValue: volumePreviewValue)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white)
                                            GeometryReader { volumeGeo in
                                                let barWidth = max(1, volumeGeo.size.width)
                                                ZStack(alignment: .leading) {
                                                    Capsule(style: .continuous)
                                                        .fill(Color.white.opacity(0.24))
                                                        .frame(height: 4)
                                                    Capsule(style: .continuous)
                                                        .fill(Color.white.opacity(0.95))
                                                        .frame(width: barWidth * clampUnit(volumePreviewValue), height: 4)
                                                }
                                                .padding(.top, 2)
                                            }
                                            .frame(width: 100, height: 10)
                                        }
                                        .frame(height: 24, alignment: .center)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .glassEffect(.clear.tint(.black), in: .capsule)
                                        .transition(.opacity)
                                    }
                                }
                                .onAppear {
                                    // 初次进入时给用户一个可发现的控制层
                                    playerUISnapshot = player.uiSnapshot
                                    showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                }
                                .onChange(of: player.uiSnapshot) { oldSnapshot, snapshot in
                                    playerUISnapshot = snapshot
#if canImport(UIKit)
                                    if oldSnapshot.isPlaying != snapshot.isPlaying {
                                        lastNowPlayingSyncedSecond = Int(snapshot.currentTime.rounded(.down))
                                        syncSystemMediaControl(reason: "player-snapshot-state-changed")
                                    } else if snapshot.isPlaying {
                                        let currentSecond = Int(snapshot.currentTime.rounded(.down))
                                        if lastNowPlayingSyncedSecond != currentSecond {
                                            lastNowPlayingSyncedSecond = currentSecond
                                            syncSystemMediaControl(reason: "player-progress-changed")
                                        }
                                    }
                                    setIdleTimerDisabled(snapshot.isPlaying)
#endif
                                    if !oldSnapshot.isPlaying && snapshot.isPlaying && controlsVisible {
                                        refreshControlsAutoHideIfNeeded(player: player)
                                    } else if oldSnapshot.isPlaying && !snapshot.isPlaying {
                                        hideControlsTask?.cancel()
                                    }
                                    if !snapshot.isPlaying, isPlaybackEnded(player: player) {
                                        pausePlayback(player: player)
                                    }
                                    handleSponsorSegmentPlayback(currentTime: snapshot.currentTime, player: player)
                                    let segment = max(1, Int(snapshot.currentTime / 360.0) + 1)
                                    guard segment != lastDanmakuPrefetchSegment else { return }
                                    lastDanmakuPrefetchSegment = segment
                                    Task {
                                        await bindableViewModel.preloadDanmakuIfNeeded(currentTime: snapshot.currentTime)
                                    }
                                }
                                .onChange(of: showDebugPanel) { _, newValue in
                                    if newValue {
                                        startDebugPanelRefresh(player: player)
                                    } else {
                                        stopDebugPanelRefresh()
                                    }
                                    if !newValue {
                                        showControlsAndAutoHideIfNeeded(player: player, forceShow: true)
                                    } else {
                                        controlsVisible = true
                                        hideControlsTask?.cancel()
                                    }
                                }
                        }
                        .frame(
                            width: geo.size.width,
                            height: isFullscreen
                                ? geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                                : min(geo.size.width / stream.aspectRatio, geo.size.width * (4.0 / 3.0)),
                            alignment: .center
                        )
                        .clipped()
                        .layoutPriority(1)
                    } else {
                        // 加载状态：先展示封面，保证卡片→详情的 Hero 动画有目标视图
                        ZStack {
                            CachedAsyncImage(url: URL(string: video.cover)) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .background(Color.black)
                            .matchedGeometryEffect(id: heroID, in: namespace)

                            VStack(spacing: 12) {
                                if bindableViewModel.isLoading {
                                    PlayerLoadingOverlay(
                                        isVisible: true,
                                        speedBytesPerSecond: 0
                                    )
                                } else if bindableViewModel.error != nil {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                } else {
                                    PlayerLoadingOverlay(
                                        isVisible: true,
                                        speedBytesPerSecond: 0
                                    )
                                }
                            }
                        }
                        .frame(
                            width: geo.size.width,
                            height: isFullscreen
                                ? geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                                : min(geo.size.width / (16.0 / 9.0), geo.size.width * (4.0 / 3.0)),
                            alignment: .center
                        )
                        .clipped()
                        .layoutPriority(1)
                    }

                    if !isFullscreen {
                        ZStack(alignment: .bottom) {
                            VStack(spacing: 0) {
                                tabBar
                                tabContent(width: geo.size.width)
                            }

                            if let player = bindableViewModel.player, showsSponsorSubmitSheet {
                                SponsorBlockSubmitDrawer(
                                    segments: $sponsorDraftSegments,
                                    errorText: sponsorSubmitErrorText,
                                    isSubmitting: sponsorIsSubmitting,
                                    currentPlayerTime: playerUISnapshot.currentTime,
                                    videoDuration: max(playerUISnapshot.duration, resolvedVideoDuration),
                                    onClose: {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                            showsSponsorSubmitSheet = false
                                        }
                                    },
                                    onSubmit: {
                                        submitSponsorDraftSegments()
                                    },
                                    onSetStartToCurrent: { id in
                                        updateSponsorDraftSegment(id: id) { draft in
                                            draft.start = playerUISnapshot.currentTime
                                            if draft.end < draft.start {
                                                draft.end = draft.start
                                            }
                                        }
                                    },
                                    onSetEndToCurrent: { id in
                                        updateSponsorDraftSegment(id: id) { draft in
                                            draft.end = playerUISnapshot.currentTime
                                            if draft.end < draft.start {
                                                draft.start = draft.end
                                            }
                                        }
                                    },
                                    onSetStartToBoundary: { id in
                                        updateSponsorDraftSegment(id: id) { draft in
                                            draft.start = 0
                                            if draft.end < draft.start {
                                                draft.end = draft.start
                                            }
                                        }
                                    },
                                    onSetEndToBoundary: { id in
                                        updateSponsorDraftSegment(id: id) { draft in
                                            let end = max(playerUISnapshot.duration, resolvedVideoDuration)
                                            draft.end = end
                                            if draft.end < draft.start {
                                                draft.start = draft.end
                                            }
                                        }
                                    },
                                    onPreview: { id in
                                        previewSponsorDraftSegment(id: id, player: player)
                                    },
                                    onDelete: { id in
                                        removeSponsorDraftSegment(id: id)
                                    },
                                    onAddSegment: {
                                        sponsorDraftSegments.append(SponsorBlockDraftSegment())
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .zIndex(1)
                            }

                            if showsVideoPageDrawer {
                                VideoPageSelectionDrawer(
                                    pages: viewModel.videoPages,
                                    currentCID: viewModel.cid,
                                    onClose: {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                            showsVideoPageDrawer = false
                                        }
                                    },
                                    onSelect: { page in
                                        Task { @MainActor in
                                            await switchVideoPage(to: page)
                                        }
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .zIndex(2)
                            }
                        }
                        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: showsSponsorSubmitSheet)
                        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: showsVideoPageDrawer)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isFullscreen ? .center : .top)
                .sheet(isPresented: $isFavoriteSheetPresented) {
                    FavoriteFolderSheet(
                        folders: $favoriteFolders,
                        selectedIds: $favoriteSelectedIds,
                        initiallySelectedIds: $favoriteInitiallySelectedIds,
                        isLoading: $favoriteIsLoading,
                        onDismiss: { isFavoriteSheetPresented = false },
                        onConfirm: {
                            let addIds = favoriteSelectedIds.subtracting(favoriteInitiallySelectedIds)
                            let delIds = favoriteInitiallySelectedIds.subtracting(favoriteSelectedIds)

                            Task {
                                await bindableViewModel.applyFavoriteSelection(
                                    addMediaIds: Array(addIds),
                                    delMediaIds: Array(delIds),
                                    finalSelectedIds: favoriteSelectedIds
                                )
                                isFavoriteSheetPresented = false
                            }
                        },
                        onLoad: {
                            guard !favoriteIsLoading else { return }
                            favoriteIsLoading = true
                            Task {
                                do {
                                    let folders = try await bindableViewModel.fetchFavoriteFoldersForCurrentUser()
                                    await MainActor.run {
                                        favoriteFolders = folders
                                        let preselected = Set(
                                            folders.filter { $0.isSelectedInitially }.map(\.id)
                                        )
                                        favoriteInitiallySelectedIds = preselected
                                        favoriteSelectedIds = preselected
                                        favoriteIsLoading = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        favoriteFolders = []
                                        favoriteInitiallySelectedIds = []
                                        favoriteSelectedIds = []
                                        favoriteIsLoading = false
                                    }
                                }
                            }
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $isDanmakuSettingsPresented) {
                    DanmakuSettingsSheet(
                        config: $danmakuConfig,
                        onClose: { isDanmakuSettingsPresented = false }
                    )
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showsSponsorList) {
                    NavigationStack {
                        SponsorBlockSegmentsSheet(
                            segments: allSponsorSegments,
                            settings: sponsorBlockSettings,
                            categoryOverrides: sponsorSegmentCategoryOverrides,
                            voteSelections: sponsorSegmentVotes,
                            onVote: { segment, vote in
                                submitSponsorVote(for: segment, vote: vote)
                            },
                            onChangeCategory: { segment, category in
                                changeSponsorCategory(for: segment, to: category)
                            },
                            onSkipToSegmentEnd: { segment in
                                if let player = bindableViewModel.player {
                                    skipToSponsorSegmentEnd(segment, player: player)
                                }
                            }
                        )
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }

                // 调试信息面板
                if showDebugPanel, let stream = bindableViewModel.dashStream {
                    DashStreamDebugPanel(
                        stream: stream,
                        player: bindableViewModel.player,
                        playerSnapshot: playerUISnapshot,
                        selectedQualityCode: bindableViewModel.selectedQualityCode,
                        onDismiss: { showDebugPanel = false }
                    )
                }
            }
            .overlay(alignment: .top) {
                if !isFullscreen {
                    Color.black
                        .frame(height: geo.safeAreaInsets.top)
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if isFullscreen {
                    Color.black.ignoresSafeArea()
                } else {
                    Color.clear
                }
            }
        }
        .onAppear {
            danmakuConfig = DanmakuConfigStore.load()
            sponsorBlockSettings = SponsorBlockSettingsStore.load()
            cachedIntroDescriptionText = AttributedString("")
            skippedSponsorSegmentIDs = []
            hiddenManualSponsorSegmentIDs = []
            manualSkipSegment = nil
            showsSponsorList = false
            sponsorSegmentVotes = [:]
            sponsorSegmentCategoryOverrides = [:]
            showsSponsorSubmitSheet = false
            sponsorDraftSegments = []
            sponsorSubmitErrorText = nil
            sponsorIsSubmitting = false
            previewDraftSegmentID = nil
            showsVideoPageDrawer = false
            shouldResumeAfterBackgroundPause = false
            backgroundPauseRestoreTime = nil
            ensureSponsorSegmentsLoadedIfNeeded()
#if canImport(UIKit)
            if let player = bindableViewModel.player {
                playerUISnapshot = player.uiSnapshot
            }
            setIdleTimerDisabled(playerUISnapshot.isPlaying)
#endif
        }
        .onChange(of: sponsorBlockSettings) { _, newValue in
            sponsorBlockSettings = newValue.clamped()
            ensureSponsorSegmentsLoadedIfNeeded()
        }
        .onChange(of: danmakuConfig) { _, newValue in
            danmakuConfig = newValue.clamped()
            DanmakuConfigStore.save(danmakuConfig)
        }
        .task {
            lastDanmakuPrefetchSegment = 0
            sponsorBlockSettings = SponsorBlockSettingsStore.load()
            sponsorSegmentVotes = [:]
            sponsorSegmentCategoryOverrides = [:]
#if canImport(UIKit)
            configureAudioSessionHandlers()
#endif
            await bindableViewModel.loadVideoData()
            refreshCachedIntroDescription()
            playerUISnapshot = bindableViewModel.player?.uiSnapshot ?? PlayerUIPlaybackSnapshot()
            ensureSponsorSegmentsLoadedIfNeeded()
#if canImport(UIKit)
            audioSessionManager.activate()
            if let player = bindableViewModel.player {
                Task { @MainActor in
                    await syncSystemMediaControlWhenPlaybackStarts(player: player)
                }
            }
#endif

            // 加载完成后启动历史上报
            if bindableViewModel.dashStream != nil, !bindableViewModel.isPlayingOfflineCache {
                bindableViewModel.startHistoryReporting()
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            stopDebugPanelRefresh()
            if let player = bindableViewModel.player {
                speedBoostTriggerTask?.cancel()
                speedBoostTriggerTask = nil
                if isSpeedBoostActive {
                    endSpeedBoostIfNeeded(player: player)
                }
                isHorizontalSeeking = false
                horizontalSeekPreviewTime = nil
                progressDragPreviewTime = nil
                isBrightnessAdjusting = false
                isVolumeAdjusting = false
                dragInteractionMode = .none
                player.pause()
                bindableViewModel.stopHistoryReporting(with: player)
            }
#if canImport(UIKit)
            audioSessionManager.deactivate()
            setIdleTimerDisabled(false)
#endif
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toast(message: $toastMessage)
        .statusBarHidden(isFullscreen)
#if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(
                for: UIDevice.orientationDidChangeNotification
            )) { _ in
                handleDeviceOrientationChange()
            }
            .onChange(of: viewModel.selectedPlaybackRate) { _, _ in
                syncSystemMediaControl(reason: "playback-rate-changed")
            }
            .onChange(of: viewModel.title) { _, _ in
                syncSystemMediaControl(reason: "title-changed")
            }
            .onChange(of: viewModel.videoDetail?.owner.name ?? video.uploader) { _, _ in
                syncSystemMediaControl(reason: "artist-changed")
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )) { _ in
                handleDidEnterBackground()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )) { _ in
                restoreFullscreenOrientationIfNeeded()
                handleDidBecomeActive()
            }
#endif
            .navigationDestination(item: $selectedRelatedVideo) { relatedVideo in
                if #available(iOS 18.0, *) {
                    VideoDetailPage(
                        video: relatedVideo,
                        namespace: namespace,
                        onBack: { selectedRelatedVideo = nil }
                    )
                    .navigationTransition(
                        .zoom(sourceID: "videoHero.\(relatedVideo.bvid)", in: namespace)
                    )
                } else {
                    VideoDetailPage(
                        video: relatedVideo,
                        namespace: namespace,
                        onBack: { selectedRelatedVideo = nil }
                    )
                }
            }
            .navigationDestination(item: $offlineCachePrefill) { prefill in
                OfflineCacheView(initialPrefill: prefill)
            }
            .navigationDestination(item: $selectedUserSpaceRoute) { route in
                UserSpaceView(
                    mid: route.mid,
                    fromViewAid: route.fromViewAid,
                    onBack: { selectedUserSpaceRoute = nil }
                )
            }
    }

    private var fullscreenAwareDanmakuConfig: DanmakuEngineConfig {
        var config = danmakuConfig
        if isFullscreen {
            config.fontScale = danmakuConfig.fullscreenFontScale
        }
        return config
    }

    fileprivate enum VideoDetailTab: String, CaseIterable {
        case intro = "简介"
        case comments = "评论"
    }

    private enum IntroLink {
        static let scheme = "pilipod"
        static let userHost = "user"
        static let videoHost = "video"
    }

    private var hasIntroDescription: Bool {
        !cachedIntroDescriptionText.characters.isEmpty
    }

    private func attributedDescriptionSegment(for item: DescV2Item) -> AttributedString {
        switch item.type {
        case 2:
            return attributedMentionSegment(for: item)
        default:
            return attributedTextSegment(item.rawText)
        }
    }

    private func attributedMentionSegment(for item: DescV2Item) -> AttributedString {
        var text = AttributedString("@\(item.rawText) ")
        if item.bizId > 0,
           let url = URL(string: "\(IntroLink.scheme)://\(IntroLink.userHost)/\(item.bizId)")
        {
            text.link = url
        }
        return text
    }

    private func attributedTextSegment(_ text: String) -> AttributedString {
        guard let regex = Self.introBVPattern else {
            return AttributedString(text)
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else {
            return AttributedString(text)
        }

        var result = AttributedString()
        var currentIndex = text.startIndex

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            if currentIndex < range.lowerBound {
                result += AttributedString(String(text[currentIndex..<range.lowerBound]))
            }

            let bvid = String(text[range])
            var linkedText = AttributedString(bvid)
            if let url = URL(string: "\(IntroLink.scheme)://\(IntroLink.videoHost)/\(bvid)") {
                linkedText.link = url
            }
            result += linkedText
            currentIndex = range.upperBound
        }

        if currentIndex < text.endIndex {
            result += AttributedString(String(text[currentIndex..<text.endIndex]))
        }

        return result
    }

    private func refreshCachedIntroDescription() {
        guard let items = viewModel.videoDetail?.descV2, !items.isEmpty else {
            cachedIntroDescriptionText = AttributedString("")
            return
        }

        var result = AttributedString()
        for item in items {
            result += attributedDescriptionSegment(for: item)
        }
        cachedIntroDescriptionText = result
    }

    private func handleIntroLink(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == IntroLink.scheme else {
            return .systemAction
        }

        switch url.host {
        case IntroLink.userHost:
            guard let midString = url.pathComponents.dropFirst().first,
                  let mid = Int(midString)
            else {
                return .handled
            }

            selectedUserSpaceRoute = UserSpaceRoute(
                mid: mid,
                fromViewAid: viewModel.videoDetail?.aid
            )
            return .handled

        case IntroLink.videoHost:
            guard let bvid = url.pathComponents.dropFirst().first, !bvid.isEmpty else {
                return .handled
            }

            selectedRelatedVideo = VideoItem(
                bvid: bvid,
                cid: nil,
                cover: "",
                title: bvid,
                playCount: "--",
                danmakuCount: "--",
                uploader: "",
                duration: 0,
                progressSeconds: nil,
                publishTimeText: "",
                bottomRcmdReasonText: nil
            )
            return .handled

        default:
            return .handled
        }
    }

    private var tabBar: some View {
        HStack(spacing: 18) {
            ForEach(VideoDetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(titleForTab(tab))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Color(.systemBackground))
    }

    private func titleForTab(_ tab: VideoDetailTab) -> String {
        switch tab {
        case .intro:
            return tab.rawValue
        case .comments:
            if let reply = viewModel.videoDetail?.stat.reply {
                return "\(tab.rawValue) (\(reply))"
            }
            return tab.rawValue
        }
    }

    private func tabContent(width: CGFloat) -> some View {
        TabPager(
            selectedTab: $selectedTab,
            width: width,
            isSwipeEnabled: !isDraggingVideoPageStrip,
            introContent: {
                introTabContent
            },
            commentsContent: {
                VideoCommentsTabView(
                    aid: viewModel.aid,
                    onOpenUserSpace: { mid in
                        guard mid > 0 else { return }
                        selectedUserSpaceRoute = UserSpaceRoute(
                            mid: mid,
                            fromViewAid: viewModel.aid > 0 ? viewModel.aid : nil
                        )
                    }
                )
                .background(Color(.systemBackground))
            }
        )
    }

    private var introTabDisplayModel: IntroTabDisplayModel? {
        guard let detail = viewModel.videoDetail else { return nil }

        return IntroTabDisplayModel(
            aid: detail.aid,
            bvid: detail.bvid,
            ownerMid: detail.owner.mid,
            ownerFace: detail.owner.face,
            ownerName: detail.owner.name,
            ownerFollowerCount: viewModel.ownerFollowerCount,
            ownerArchiveCount: viewModel.ownerArchiveCount,
            isOwnerFollowing: viewModel.isOwnerFollowing,
            isOwnerFollowRequesting: viewModel.isOwnerFollowRequesting,
            fullSegmentBanner: fullSegmentBanner?.text,
            fullSegmentBannerCategoryRawValue: fullSegmentBannerCategoryRawValue,
            title: viewModel.title,
            viewCount: detail.stat.view,
            danmakuCount: detail.stat.danmaku,
            pubdate: detail.pubdate,
            onlineCount: viewModel.playerInfo?.onlineCount,
            isExpanded: isVideoDetailExpanded,
            introDescriptionText: cachedIntroDescriptionText,
            isLiked: viewModel.isLiked,
            isDisliked: viewModel.isDisliked,
            isCoined: viewModel.isCoined,
            isFavorited: viewModel.isFavorited,
            isWatchLater: viewModel.isWatchLater,
            likeCount: viewModel.likeCount,
            coinCount: viewModel.coinCount,
            favoriteCount: viewModel.favoriteCount,
            shareCount: detail.stat.share,
            isLikeRequesting: viewModel.isLikeRequesting,
            isDislikeRequesting: viewModel.isDislikeRequesting,
            isCoinRequesting: viewModel.isCoinRequesting,
            isFavoriteRequesting: viewModel.isFavoriteRequesting,
            isWatchLaterRequesting: viewModel.isWatchLaterRequesting,
            currentPageCID: currentVideoPage?.cid ?? viewModel.cid,
            currentPageTitle: currentVideoPage?.part ?? viewModel.title,
            videoPages: viewModel.videoPages,
            relatedIsLoading: viewModel.relatedIsLoading,
            relatedError: viewModel.relatedError,
            relatedVideos: Array(viewModel.relatedVideos.prefix(40))
        )
    }

    private var introTabContent: some View {
        Group {
            if let model = introTabDisplayModel {
                IntroTabContentView(
                    model: model,
                    namespace: namespace,
                    onOpenOwner: { mid, aid in
                        selectedUserSpaceRoute = UserSpaceRoute(
                            mid: mid,
                            fromViewAid: aid
                        )
                    },
                    onToggleFollow: {
                        guard !viewModel.isOwnerFollowRequesting else { return }
                        Task {
                            do {
                                try await viewModel.toggleOwnerFollow()
                            } catch {
                                await MainActor.run {
                                    toastMessage = error.localizedDescription
                                }
                            }
                        }
                    },
                    onToggleExpand: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isVideoDetailExpanded.toggle()
                        }
                    },
                    onOpenIntroLink: { url in
                        handleIntroLink(url)
                    },
                    onToggleLike: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.toggleLike()
                        }
                    },
                    onToggleDislike: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.toggleDislike()
                        }
                    },
                    onCoin1: {
                        Task { await viewModel.coin(multiply: 1) }
                    },
                    onCoin2: {
                        Task { await viewModel.coin(multiply: 2) }
                    },
                    onToggleFavorite: {
                        isFavoriteSheetPresented = true
                    },
                    onShare: {
                        // TODO: add share logic later
                    },
                    onLaterWatch: {
                        if !viewModel.isWatchLater {
                            viewModel.addToWatchLater()
                        }
                    },
                    onOpenPageDrawer: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            showsSponsorSubmitSheet = false
                            showsVideoPageDrawer = true
                        }
                    },
                    onSelectPage: { page in
                        Task { @MainActor in
                            await switchVideoPage(to: page)
                        }
                    },
                    onPageStripDragStateChange: { isDragging in
                        isDraggingVideoPageStrip = isDragging
                    },
                    onOpenRelatedVideo: { item in
                        selectedRelatedVideo = item
                    }
                )
                .equatable()
            } else {
                Color(.systemBackground)
            }
        }
    }

    // MARK: - 显示控制条并在需要时自动隐藏

    private func showControlsAndAutoHideIfNeeded(player: MPVKitPlayer, forceShow: Bool = false) {
        guard !showDebugPanel else {
            controlsVisible = true
            hideControlsTask?.cancel()
            return
        }

        if forceShow {
            controlsVisible = true
        } else {
            // 点一下显示；若已显示则切换为隐藏
            controlsVisible.toggle()
        }

        refreshControlsAutoHideIfNeeded(player: player)
    }

    private func refreshControlsAutoHideIfNeeded(player: MPVKitPlayer) {
        hideControlsTask?.cancel()
        guard controlsVisible, playerUISnapshot.isPlaying else { return }

        hideControlsTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 3000000000)
            } catch {
                // 重要：若被取消，请勿继续隐藏控制条
                return
            }
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.22)) {
                controlsVisible = false
            }
        }
    }

    // MARK: - 检查播放是否结束

    private func isPlaybackEnded(player: MPVKitPlayer) -> Bool {
        guard playerUISnapshot.duration > 0 else { return false }
        return playerUISnapshot.currentTime >= playerUISnapshot.duration - 0.05
    }

    // MARK: - 开始倍速播放

    private func beginSpeedBoostIfNeeded(player: MPVKitPlayer) {
        guard !isSpeedBoostActive else { return }
        guard dragInteractionMode == .none else { return }
        dragInteractionMode = .speedBoost
        isSpeedBoostActive = true
        player.setPlaybackRate(speedBoostMultiplier)
#if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
#endif
    }

    // MARK: - 结束倍速播放

    private func endSpeedBoostIfNeeded(player: MPVKitPlayer) {
        guard isSpeedBoostActive else { return }
        isSpeedBoostActive = false
        player.setPlaybackRate(1.0)
    }

    // MARK: - 格式化倍速标签

    private func formatSpeedBoostLabel(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return "\(Int(rate))x倍速中"
        }

        return String(format: "%.1fx倍速中", rate)
    }

    private func formatMMSS(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    private func handleSponsorSegmentPlayback(currentTime: TimeInterval, player: MPVKitPlayer) {
        if let previewDraftSegment {
            if previewDraftSegment.actionType == .skip,
               currentTime >= previewDraftSegment.start,
               currentTime < previewDraftSegment.end
            {
                previewDraftSegmentID = nil
                player.seek(to: previewDraftSegment.end)
                return
            }

            if currentTime >= previewDraftSegment.end {
                previewDraftSegmentID = nil
            }
        }

        guard sponsorBlockSettings.isEnabled else {
            manualSkipSegment = nil
            return
        }

        let activeSegments = playableSponsorSegments.filter { segment in
            currentTime >= segment.start && currentTime < segment.end
        }

        if let autoSegment = activeSegments.first(where: {
            $0.behavior == .autoSkip && !skippedSponsorSegmentIDs.contains($0.id)
        }) {
            performAutoSponsorSkip(for: autoSegment, player: player)
            return
        }

        if let manualSegment = activeSegments.first(where: {
            $0.behavior == .manualSkip &&
                !skippedSponsorSegmentIDs.contains($0.id) &&
                !hiddenManualSponsorSegmentIDs.contains($0.id)
        }) {
            manualSkipSegment = manualSegment
        } else {
            manualSkipSegment = nil
        }
    }

    private func performAutoSponsorSkip(for segment: PlaybackSponsorSegment, player: MPVKitPlayer) {
        skippedSponsorSegmentIDs.insert(segment.id)
        hiddenManualSponsorSegmentIDs.insert(segment.id)
        manualSkipSegment = nil
        if sponsorBlockSettings.showsSkipToast {
            toastMessage = "已自动跳过片段"
        }
        player.seek(to: segment.end)
        Task {
            await viewModel.preloadDanmakuIfNeeded(currentTime: segment.end)
            await markSponsorSegmentIfNeeded(segment)
        }
    }

    private func performManualSponsorSkip(for segment: PlaybackSponsorSegment, player: MPVKitPlayer) {
        skippedSponsorSegmentIDs.insert(segment.id)
        hiddenManualSponsorSegmentIDs.insert(segment.id)
        manualSkipSegment = nil
        player.seek(to: segment.end)
        Task {
            await viewModel.preloadDanmakuIfNeeded(currentTime: segment.end)
            await markSponsorSegmentIfNeeded(segment)
        }
    }

    private func markSponsorSegmentIfNeeded(_ segment: PlaybackSponsorSegment) async {
        guard sponsorBlockSettings.shouldTrackSkipCount else { return }
        await SponsorBlockAPI.markSegmentViewed(uuid: segment.uuid)
    }

    private func sponsorCategory(for segment: SkipSegment) -> SponsorBlockCategory? {
        if let override = sponsorSegmentCategoryOverrides[segment.segmentID] {
            return override
        }
        return SponsorBlockCategory(rawValue: segment.category)
    }

    private func skipToSponsorSegmentEnd(_ segment: SkipSegment, player: MPVKitPlayer) {
        guard segment.segment.count >= 2 else { return }
        let target = segment.segment[1]
        player.seek(to: target)
        Task {
            await viewModel.preloadDanmakuIfNeeded(currentTime: target)
        }
    }

    private func submitSponsorVote(for segment: SkipSegment, vote: SponsorBlockVoteSelection) {
        guard let userID = sponsorBlockSettings.userID, !userID.isEmpty else { return }
        let current = sponsorSegmentVotes[segment.segmentID] ?? .none
        let targetType: Int
        let nextState: SponsorBlockVoteSelection

        if current == vote {
            targetType = 20
            nextState = .none
        } else {
            targetType = vote == .upvoted ? 1 : 0
            nextState = vote
        }

        sponsorSegmentVotes[segment.segmentID] = nextState

        Task {
            do {
                try await SponsorBlockAPI.voteOnSegment(
                    uuid: segment.segmentID,
                    userID: userID,
                    type: targetType
                )
            } catch {
                await MainActor.run {
                    sponsorSegmentVotes[segment.segmentID] = current
                }
            }
        }
    }

    private func changeSponsorCategory(for segment: SkipSegment, to category: SponsorBlockCategory) {
        guard let userID = sponsorBlockSettings.userID, !userID.isEmpty else { return }
        let previous = sponsorSegmentCategoryOverrides[segment.segmentID] ?? SponsorBlockCategory(rawValue: segment.category)
        sponsorSegmentCategoryOverrides[segment.segmentID] = category

        Task {
            do {
                try await SponsorBlockAPI.changeSegmentCategory(
                    uuid: segment.segmentID,
                    userID: userID,
                    category: category.rawValue
                )
            } catch {
                await MainActor.run {
                    sponsorSegmentCategoryOverrides[segment.segmentID] = previous
                }
            }
        }
    }

    private func ensureSponsorSegmentsLoadedIfNeeded() {
        guard sponsorBlockSettings.isEnabled else { return }
        guard viewModel.skipSegments.isEmpty else { return }
        guard !viewModel.skipSegmentsIsLoading else { return }

        Task { @MainActor in
            await viewModel.loadSkipSegments()
        }
    }

    private func openSponsorSubmitDrawer() {
        if sponsorDraftSegments.isEmpty {
            sponsorDraftSegments = [SponsorBlockDraftSegment()]
        }
        sponsorSubmitErrorText = nil
        showsVideoPageDrawer = false
        showsSponsorSubmitSheet = true
    }

    @MainActor
    private func switchVideoPage(to page: VideoPageListItem) async {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            showsVideoPageDrawer = false
        }
        await viewModel.switchToPage(page)
        playerUISnapshot = viewModel.player?.uiSnapshot ?? PlayerUIPlaybackSnapshot()
        skippedSponsorSegmentIDs = []
        hiddenManualSponsorSegmentIDs = []
        manualSkipSegment = nil
        lastDanmakuPrefetchSegment = 0
        refreshCachedIntroDescription()
        syncSystemMediaControl(reason: "video-page-changed")
    }

    private func updateSponsorDraftSegment(
        id: SponsorBlockDraftSegment.ID,
        mutate: (inout SponsorBlockDraftSegment) -> Void
    ) {
        guard let index = sponsorDraftSegments.firstIndex(where: { $0.id == id }) else { return }
        var draft = sponsorDraftSegments[index]
        mutate(&draft)
        draft.start = max(0, draft.start)
        draft.end = max(0, draft.end)
        sponsorDraftSegments[index] = draft
    }

    private func removeSponsorDraftSegment(id: SponsorBlockDraftSegment.ID) {
        sponsorDraftSegments.removeAll { $0.id == id }
        if sponsorDraftSegments.isEmpty {
            sponsorDraftSegments = [SponsorBlockDraftSegment()]
        }
        if previewDraftSegmentID == id {
            previewDraftSegmentID = nil
        }
    }

    private func previewSponsorDraftSegment(id: SponsorBlockDraftSegment.ID, player: MPVKitPlayer) {
        guard let draft = sponsorDraftSegments.first(where: { $0.id == id }) else { return }
        previewDraftSegmentID = id
        seekPlayback(to: max(0, draft.start - 3), player: player, shouldPreloadDanmaku: false)
        resumePlayback(player: player)
    }

    private func startDebugPanelRefresh(player: MPVKitPlayer) {
        debugPanelRefreshTask?.cancel()
        player.refreshDebugSnapshot()
        playerUISnapshot = player.uiSnapshot
        debugPanelRefreshTask = Task { @MainActor in
            while !Task.isCancelled, showDebugPanel {
                do {
                    try await Task.sleep(nanoseconds: 100000000)
                } catch {
                    return
                }
                player.refreshDebugSnapshot()
                playerUISnapshot = player.uiSnapshot
            }
        }
    }

    private func stopDebugPanelRefresh() {
        debugPanelRefreshTask?.cancel()
        debugPanelRefreshTask = nil
    }

    private func submitSponsorDraftSegments() {
        guard let userID = sponsorBlockSettings.userID, !userID.isEmpty else {
            sponsorSubmitErrorText = "缺少用户ID"
            return
        }

        let cidValue = viewModel.cid > 0 ? String(viewModel.cid) : String(video.cid ?? 0)
        guard !cidValue.isEmpty, cidValue != "0" else {
            sponsorSubmitErrorText = "缺少CID"
            return
        }

        let duration = max(resolvedVideoDuration, viewModel.player?.duration ?? 0)
        guard duration > 0 else {
            sponsorSubmitErrorText = "视频时长无效"
            return
        }

        let payload = sponsorDraftSegments.map { draft in
            SubmitSkipSegmentRequestItem(
                segment: [min(draft.start, draft.end), max(draft.start, draft.end)],
                category: draft.category.rawValue,
                actionType: draft.actionType.rawValue
            )
        }

        sponsorIsSubmitting = true
        sponsorSubmitErrorText = nil

        Task {
            do {
                _ = try await SponsorBlockAPI.submitSegments(
                    videoID: video.bvid,
                    cid: cidValue,
                    userID: userID,
                    videoDuration: duration,
                    segments: payload
                )
                await MainActor.run {
                    sponsorIsSubmitting = false
                    sponsorDraftSegments = [SponsorBlockDraftSegment()]
                    previewDraftSegmentID = nil
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        showsSponsorSubmitSheet = false
                    }
                    Task { @MainActor in
                        await viewModel.loadSkipSegments()
                    }
                }
            } catch {
                await MainActor.run {
                    sponsorIsSubmitting = false
                    sponsorSubmitErrorText = error.localizedDescription
                }
            }
        }
    }

    private func activeSeekPreviewTime(duration: TimeInterval) -> TimeInterval? {
        if let horizontalSeekPreviewTime {
            return clampSeekTime(horizontalSeekPreviewTime, duration: duration)
        }
        if let progressDragPreviewTime {
            return clampSeekTime(progressDragPreviewTime, duration: duration)
        }
        return nil
    }

    private func clampSeekTime(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        let safeDuration = max(0, duration)
        return min(max(0, time), safeDuration)
    }

#if canImport(UIKit)
    private func togglePlayback(player: MPVKitPlayer) {
        if player.isPlaying {
            pausePlayback(player: player)
        } else {
            resumePlayback(player: player)
        }
    }

    private func pausePlayback(player: MPVKitPlayer) {
        player.pause()
        playerUISnapshot = player.uiSnapshot
    }

    private func resumePlayback(player: MPVKitPlayer) {
        player.resume()
        playerUISnapshot = player.uiSnapshot
    }

    private func seekPlayback(
        to time: TimeInterval,
        player: MPVKitPlayer,
        shouldPreloadDanmaku: Bool = true
    ) {
        player.seek(to: time)
        playerUISnapshot = player.uiSnapshot
        syncSystemMediaControl(reason: "seek")

        guard shouldPreloadDanmaku else { return }

        Task {
            await viewModel.preloadDanmakuIfNeeded(currentTime: time)
        }
    }

    private func configureAudioSessionHandlers() {
        audioSessionManager.configureHandlers(
            onPlay: {
                guard let player = viewModel.player else { return }
                resumePlayback(player: player)
            },
            onPause: {
                guard let player = viewModel.player else { return }
                pausePlayback(player: player)
            },
            onSeek: { time in
                guard let player = viewModel.player else { return }
                let target = clampSeekTime(time, duration: playerUISnapshot.duration)
                seekPlayback(to: target, player: player)
            }
        )
    }

    private func syncSystemMediaControl(reason: String = "manual") {
        let title = viewModel.title.isEmpty ? video.title : viewModel.title
        let artist = viewModel.videoDetail?.owner.name ?? video.uploader
        let artworkURL = URL(string: viewModel.cover)
        let player = viewModel.player
        let effectiveSnapshot = player?.uiSnapshot ?? playerUISnapshot
        let duration = effectiveSnapshot.duration > 0 ? effectiveSnapshot.duration : resolvedVideoDuration
        let elapsedTime = player?.currentTime ?? effectiveSnapshot.currentTime
        let isPlaying = player?.isPlaying ?? effectiveSnapshot.isPlaying
        let isPlaybackReadyForNowPlaying =
            !isPlaying ||
            effectiveSnapshot.currentTime > 0 ||
            elapsedTime > 0 ||
            effectiveSnapshot.duration > 0 ||
            (player?.duration ?? 0) > 0

        guard isPlaybackReadyForNowPlaying else {
            return
        }

        audioSessionManager.updateNowPlaying(
            info: .init(
                title: title,
                artist: artist,
                artworkURL: artworkURL,
                duration: duration,
                elapsedTime: elapsedTime,
                playbackRate: viewModel.selectedPlaybackRate,
                isPlaying: isPlaying
            )
        )
    }

    private func syncSystemMediaControlWhenPlaybackStarts(player: MPVKitPlayer) async {
        for _ in 0..<20 {
            let snapshot = player.uiSnapshot
            if snapshot.isPlaying {
                playerUISnapshot = snapshot
                lastNowPlayingSyncedSecond = Int(snapshot.currentTime.rounded(.down))
                syncSystemMediaControl(reason: "initial-playback-start")
                return
            }
            try? await Task.sleep(nanoseconds: 100000000)
        }
    }

    private func handleDidEnterBackground() {
        let playbackSettings = AudioVideoSettingsStore.load()
        guard !playbackSettings.allowsBackgroundPlayback,
              let player = viewModel.player
        else { return }

        shouldResumeAfterBackgroundPause = player.isPlaying
        backgroundPauseRestoreTime = playerUISnapshot.currentTime

        guard shouldResumeAfterBackgroundPause else {
            syncSystemMediaControl(reason: "background-noresume")
            return
        }

        pausePlayback(player: player)
    }

    private func handleDidBecomeActive() {
        guard shouldResumeAfterBackgroundPause,
              let player = viewModel.player
        else {
            shouldResumeAfterBackgroundPause = false
            backgroundPauseRestoreTime = nil
            return
        }

        shouldResumeAfterBackgroundPause = false
        let restoreTime = backgroundPauseRestoreTime
        backgroundPauseRestoreTime = nil

        if let restoreTime {
            seekPlayback(to: restoreTime, player: player)
        }
        resumePlayback(player: player)
    }
#endif

    private func clampUnit(_ value: Double) -> Double {
        min(max(0, value), 1)
    }

#if canImport(UIKit)
    private func currentScreenBrightness() -> Double {
        Double(UIScreen.main.brightness)
    }

    private func setScreenBrightness(_ value: Double) {
        UIScreen.main.brightness = CGFloat(clampUnit(value))
    }
#else
    private func currentScreenBrightness() -> Double { 0.5 }
    private func setScreenBrightness(_ value: Double) {
        _ = value
    }
#endif

    private func currentSystemVolume() -> Double {
        clampUnit(systemVolumeControl.currentVolume)
    }

    private func setSystemVolume(_ value: Double) {
        systemVolumeControl.setVolume(clampUnit(value))
    }

    // MARK: - 设置空闲计时器

#if canImport(UIKit)
    private func setIdleTimerDisabled(_ isDisabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = isDisabled
    }
#endif

    // MARK: - 格式化时长

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    // MARK: - 格式化计数

    private func formatCount(_ count: Int) -> String {
        if count >= 10000 {
            return String(
                format: "%.1f万",
                Double(count) / 10000
            )
        }

        return "\(count)"
    }

    // MARK: - 格式化时间戳

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current

        return formatter.string(from: date)
    }

#if canImport(UIKit)
    private func updateDeviceOrientationForFullscreen(isFullscreen: Bool) {
        updateDeviceOrientationForFullscreen(
            isFullscreen: isFullscreen,
            orientation: preferredFullscreenOrientation
        )
    }

    private func updateDeviceOrientationForFullscreen(
        isFullscreen: Bool,
        orientation: UIInterfaceOrientation
    ) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let targetOrientationMask: UIInterfaceOrientationMask
        if isFullscreen {
            targetOrientationMask = orientation == .landscapeLeft ? .landscapeLeft : .landscapeRight
        } else {
            targetOrientationMask = .portrait
        }
        let prefs = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: targetOrientationMask
        )
        scene.requestGeometryUpdate(prefs) { error in
            print("requestGeometryUpdate failed: \(error.localizedDescription)")
        }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
    }

    private func updatePreferredFullscreenOrientation(from orientation: UIInterfaceOrientation?) {
        guard let orientation, orientation.isLandscape else { return }
        preferredFullscreenOrientation = orientation == .landscapeLeft ? .landscapeLeft : .landscapeRight
    }

    private func restoreFullscreenOrientationIfNeeded() {
        guard isFullscreen else { return }
        updateDeviceOrientationForFullscreen(
            isFullscreen: true,
            orientation: preferredFullscreenOrientation
        )
        refreshPlayerLayoutAfterFullscreenChange()
    }
#endif

    private func toggleFullscreenManually() {
        let willEnterFullscreen = !isFullscreen
#if canImport(UIKit)
        if willEnterFullscreen {
            updatePreferredFullscreenOrientation(from: currentInterfaceOrientation())
        }
#endif
        withAnimation(.easeInOut(duration: 0.2)) {
            isFullscreen = willEnterFullscreen
            fullscreenTrigger = willEnterFullscreen ? .manual : .none
            if !willEnterFullscreen {
                isFullscreenDanmakuPanelVisible = false
            }
        }
        viewModel.player?.setKeepAspect(true)
#if canImport(UIKit)
        updateDeviceOrientationForFullscreen(isFullscreen: willEnterFullscreen)
#endif
        refreshPlayerLayoutAfterFullscreenChange()
    }

#if canImport(UIKit)
    private func handleDeviceOrientationChange() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let interfaceOrientation = scene.interfaceOrientation
        if interfaceOrientation.isLandscape {
            updatePreferredFullscreenOrientation(from: interfaceOrientation)
            if !isFullscreen {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFullscreen = true
                    fullscreenTrigger = .rotation
                }
                viewModel.player?.setKeepAspect(true)
                refreshPlayerLayoutAfterFullscreenChange()
            }
        } else if interfaceOrientation.isPortrait {
            if isFullscreen, fullscreenTrigger == .rotation {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFullscreen = false
                    fullscreenTrigger = .none
                    isFullscreenDanmakuPanelVisible = false
                }
                viewModel.player?.setKeepAspect(true)
                refreshPlayerLayoutAfterFullscreenChange()
            }
        }
    }
#endif

    private func handleBackAction() {
        if isFullscreen {
            withAnimation(.easeInOut(duration: 0.2)) {
                isFullscreen = false
                fullscreenTrigger = .none
                isFullscreenDanmakuPanelVisible = false
            }
            viewModel.player?.setKeepAspect(true)
#if canImport(UIKit)
            updateDeviceOrientationForFullscreen(isFullscreen: false)
#endif
            refreshPlayerLayoutAfterFullscreenChange()
        } else {
            onBack()
        }
    }

    private func refreshPlayerLayoutAfterFullscreenChange() {
        Task { @MainActor in
            viewModel.player?.refreshVideoOutput()
            // 多次刷新保证成功
            try? await Task.sleep(nanoseconds: 80000000)
            viewModel.player?.refreshVideoOutput()
            // try? await Task.sleep(nanoseconds: 30000000)
            // viewModel.player?.refreshVideoOutput()
        }
    }
}

private struct TabPager<IntroContent: View, CommentsContent: View>: View {
    @Binding var selectedTab: VideoDetailPage.VideoDetailTab
    let width: CGFloat
    let isSwipeEnabled: Bool
    @ViewBuilder let introContent: () -> IntroContent
    @ViewBuilder let commentsContent: () -> CommentsContent

    @GestureState private var dragTranslation: CGFloat = 0

    private var currentIndex: CGFloat {
        switch selectedTab {
        case .intro:
            return 0
        case .comments:
            return 1
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            introContent()
                .frame(width: width)

            commentsContent()
                .frame(width: width)
        }
        .frame(width: width, alignment: .leading)
        .offset(x: -currentIndex * width + dragOffset)
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86), value: selectedTab)
        .contentShape(Rectangle())
        .gesture(pagerGesture)
        .clipped()
    }

    private var dragOffset: CGFloat {
        guard isSwipeEnabled else { return 0 }
        return dragTranslation
    }

    private var pagerGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragTranslation) { value, state, _ in
                guard isSwipeEnabled else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let translation = value.translation.width
                if selectedTab == .intro {
                    state = max(-width, min(0, translation))
                } else {
                    state = max(0, min(width, translation))
                }
            }
            .onEnded { value in
                guard isSwipeEnabled else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) else { return }

                let threshold = width * 0.2
                switch selectedTab {
                case .intro:
                    guard dx < -threshold else { return }
                    selectedTab = .comments
                case .comments:
                    guard dx > threshold else { return }
                    selectedTab = .intro
                }
            }
    }
}

#if canImport(UIKit)
private struct SystemVolumeController {
    private let volumeView: MPVolumeView
    private let slider: UISlider?

    init() {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.isHidden = true
        volumeView = view
        slider = view.subviews.compactMap { $0 as? UISlider }.first
    }

    var currentVolume: Double {
        Double(AVAudioSession.sharedInstance().outputVolume)
    }

    func setVolume(_ value: Double) {
        slider?.setValue(Float(value), animated: false)
        slider?.sendActions(for: .valueChanged)
    }
}
#else
private struct SystemVolumeController {
    var currentVolume: Double { 0.5 }
    func setVolume(_ value: Double) {
        _ = value
    }
}
#endif

private struct UserSpaceRoute: Identifiable, Hashable {
    let mid: Int
    let fromViewAid: Int?

    var id: String {
        "\(mid)-\(fromViewAid ?? 0)"
    }
}

// MARK: - 视频操作

struct VideoActionBar: View {
    let isLiked: Bool
    let isDisliked: Bool
    let isCoined: Bool
    let isFavorited: Bool
    let isWatchLater: Bool

    let likeCount: Int
    let coinCount: Int
    let favoriteCount: Int
    let shareCount: Int

    let isLikeRequesting: Bool
    let isDislikeRequesting: Bool
    let isCoinRequesting: Bool
    let isFavoriteRequesting: Bool
    let isWatchLaterRequesting: Bool

    let onToggleLike: () -> Void
    let onToggleDislike: () -> Void
    let onCoin1: () -> Void
    let onCoin2: () -> Void
    let onToggleFavorite: () -> Void
    let onShare: () -> Void
    let onLaterWatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VideoActionButton(
                title: formatCount(likeCount),
                systemImage: "hand.thumbsup.fill",
                isActive: isLiked,
                // isDisabled: isLikeRequesting,
                isDisabled: false,
                onTap: onToggleLike
            )

            VideoActionButton(
                title: "点踩",
                systemImage: "hand.thumbsdown.fill",
                isActive: isDisliked,
                // isDisabled: isDislikeRequesting,
                isDisabled: false,
                onTap: onToggleDislike
            )

            VideoCoinMenuButton(
                title: formatCount(coinCount),
                assetImage: "BiliCoin",
                isActive: isCoined,
                // isDisabled: isCoinRequesting || isCoined,
                isDisabled: isCoined,
                onCoin1: onCoin1,
                onCoin2: onCoin2
            )

            VideoActionButton(
                title: formatCount(favoriteCount),
                systemImage: "star.fill",
                isActive: isFavorited,
                // isDisabled: isFavoriteRequesting,
                isDisabled: false,
                onTap: onToggleFavorite
            )

            VideoActionButton(
                title: formatCount(shareCount),
                systemImage: "square.and.arrow.up.fill",
                isActive: false,
                isDisabled: false,
                onTap: onShare
            )

            VideoActionButton(
                title: "稍后再看",
                systemImage: "clock.badge",
                isActive: isWatchLater,
                isDisabled: isWatchLaterRequesting,
                onTap: onLaterWatch
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 格式化计数（VideoActionBar中的辅助函数）

    private func formatCount(_ count: Int) -> String {
        if count >= 10000 {
            return String(
                format: "%.1f万",
                Double(count) / 10000
            )
        }

        return "\(count)"
    }
}

private struct VideoCoinMenuButton: View {
    let title: String
    let assetImage: String
    let isActive: Bool
    let isDisabled: Bool
    let onCoin1: () -> Void
    let onCoin2: () -> Void

    var body: some View {
        Menu {
            Button("投1个") { onCoin1() }
            Button("投2个") { onCoin2() }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isActive ? Color("BiliPink") : Color.white.opacity(0))
                        .animation(.smooth(duration: 0.1), value: isActive)

                    Image(assetImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(isActive ? .white : .primary)
                }
                .frame(width: 44, height: 44)
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )

                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

private struct VideoActionButton: View {
    let title: String
    let systemImage: String?
    let assetImage: String?
    let isActive: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    init(
        title: String,
        systemImage: String,
        isActive: Bool,
        isDisabled: Bool,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        assetImage = nil
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.onTap = onTap
    }

    init(
        title: String,
        assetImage: String,
        isActive: Bool,
        isDisabled: Bool,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        systemImage = nil
        self.assetImage = assetImage
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.onTap = onTap
    }

    // 点赞/投币/收藏等按钮
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isActive ? Color("BiliPink") : Color.white.opacity(0))
                        .animation(.smooth(duration: 0.1), value: isActive)
                    Group {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 16, weight: .semibold))
                        } else if let assetImage {
                            Image(assetImage)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        }
                    }
                    .foregroundStyle(isActive ? .white : .primary)
                }
                .frame(width: 44, height: 44)
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )

                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

// MARK: - 收藏夹抽屉

private struct FavoriteFolderSheet: View {
    @Binding var folders: [FavoriteFolderItem]
    @Binding var selectedIds: Set<Int64>
    @Binding var initiallySelectedIds: Set<Int64>
    @Binding var isLoading: Bool

    let onDismiss: () -> Void
    let onConfirm: () -> Void
    let onLoad: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("加载收藏夹中…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if folders.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("暂无收藏夹")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(folders) { folder in
                            FavoriteFolderRow(
                                folder: folder,
                                isSelected: selectedIds.contains(folder.id),
                                onToggle: {
                                    if selectedIds.contains(folder.id) {
                                        selectedIds.remove(folder.id)
                                    } else {
                                        selectedIds.insert(folder.id)
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("选择收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onConfirm) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(selectedIds == initiallySelectedIds)
                }
            }
            .task {
                onLoad()
            }
        }
    }
}

// MARK: - 弹幕设置抽屉

private struct DanmakuSettingsSheet: View {
    @Binding var config: DanmakuEngineConfig
    let onClose: () -> Void

    private let defaultConfig = DanmakuEngineConfig()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sliderSection(
                        title: "屏蔽等级",
                        valueText: "\(config.blockLevel)",
                        onReset: { config.blockLevel = defaultConfig.blockLevel }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { Double(config.blockLevel) },
                                set: { config.blockLevel = Int($0) }
                            ),
                            range: 0 ... 10,
                            step: 1
                        )
                    }

                    blockTypeSection

                    otherSection

                    sliderSection(
                        title: "显示区域",
                        valueText: "\(Int((config.topRegionRatio * 100).rounded()))%",
                        onReset: {
                            config.topRegionRatio = defaultConfig.topRegionRatio
                            config.bottomRegionRatio = defaultConfig.bottomRegionRatio
                        }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { config.topRegionRatio * 100 },
                                set: {
                                    let ratio = $0 / 100
                                    config.topRegionRatio = ratio
                                    config.bottomRegionRatio = ratio
                                }
                            ),
                            range: 10 ... 100,
                            step: 10
                        )
                    }

                    sliderSection(
                        title: "不透明度",
                        valueText: "\(Int((config.opacity * 100).rounded()))%",
                        onReset: { config.opacity = defaultConfig.opacity }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { config.opacity * 100 },
                                set: { config.opacity = $0 / 100 }
                            ),
                            range: 0 ... 100,
                            step: 10
                        )
                    }

                    sliderSection(
                        title: "字体粗细",
                        valueText: "\(config.fontWeightValue)",
                        onReset: { config.fontWeightValue = defaultConfig.fontWeightValue }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { Double(config.fontWeightValue) },
                                set: { config.fontWeightValue = Int($0) }
                            ),
                            range: 1 ... 9,
                            step: 1
                        )
                    }

                    sliderSection(
                        title: "描边粗细",
                        valueText: String(format: "%.1f", config.strokeWidth),
                        onReset: { config.strokeWidth = defaultConfig.strokeWidth }
                    ) {
                        steppedSlider(
                            value: $config.strokeWidth,
                            range: 0 ... 2,
                            step: 0.1
                        )
                    }

                    sliderSection(
                        title: "字体大小",
                        valueText: "\(Int((config.fontScale * 100).rounded()))%",
                        onReset: { config.fontScale = defaultConfig.fontScale }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { config.fontScale * 100 },
                                set: { config.fontScale = $0 / 100 }
                            ),
                            range: 50 ... 250,
                            step: 10
                        )
                    }

                    sliderSection(
                        title: "全屏字体大小",
                        valueText: "\(Int((config.fullscreenFontScale * 100).rounded()))%",
                        onReset: { config.fullscreenFontScale = defaultConfig.fullscreenFontScale }
                    ) {
                        steppedSlider(
                            value: Binding(
                                get: { config.fullscreenFontScale * 100 },
                                set: { config.fullscreenFontScale = $0 / 100 }
                            ),
                            range: 50 ... 250,
                            step: 10
                        )
                    }

                    sliderSection(
                        title: "滚动弹幕时长",
                        valueText: "\(Int(config.scrollDuration.rounded()))s",
                        onReset: { config.scrollDuration = defaultConfig.scrollDuration }
                    ) {
                        steppedSlider(
                            value: $config.scrollDuration,
                            range: 1 ... 30,
                            step: 1
                        )
                    }

                    sliderSection(
                        title: "静态弹幕时长",
                        valueText: "\(Int(config.staticDuration.rounded()))s",
                        onReset: { config.staticDuration = defaultConfig.staticDuration }
                    ) {
                        steppedSlider(
                            value: $config.staticDuration,
                            range: 1 ... 30,
                            step: 1
                        )
                    }

                    sliderSection(
                        title: "弹幕行高",
                        valueText: String(format: "%.1f", config.lineHeightMultiplier),
                        onReset: { config.lineHeightMultiplier = defaultConfig.lineHeightMultiplier }
                    ) {
                        steppedSlider(
                            value: $config.lineHeightMultiplier,
                            range: 1 ... 3,
                            step: 0.1
                        )
                    }
                }
                .padding(16)
            }
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
        }
    }

    private var blockTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(
                "按类型屏蔽",
                valueText: "",
                onReset: {
                    config.blockScroll = defaultConfig.blockScroll
                    config.blockTop = defaultConfig.blockTop
                    config.blockBottom = defaultConfig.blockBottom
                    config.blockColorful = defaultConfig.blockColorful
                }
            )
            HStack(spacing: 8) {
                toggleChip("滚动", isOn: $config.blockScroll)
                toggleChip("顶部", isOn: $config.blockTop)
                toggleChip("底部", isOn: $config.blockBottom)
                toggleChip("彩色", isOn: $config.blockColorful)
            }
        }
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(
                "其他",
                valueText: "",
                onReset: {
                    config.allowOverlapWhenMassive = defaultConfig.allowOverlapWhenMassive
                    config.forceAllScroll = defaultConfig.forceAllScroll
                }
            )
            HStack(spacing: 8) {
                toggleChip("海量弹幕", isOn: $config.allowOverlapWhenMassive)
                toggleChip("全部滚动", isOn: $config.forceAllScroll)
                Spacer(minLength: 0)
            }
        }
    }

    private func sliderSection(
        title: String,
        valueText: String,
        onReset: @escaping () -> Void,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(title, valueText: valueText, onReset: onReset)
            control()
        }
    }

    private func titleRow(_ title: String, valueText: String, onReset: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private func steppedSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Slider(value: value, in: range, step: step)
            .tint(Color("BiliPink"))
    }

    private func toggleChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isOn.wrappedValue ? Color("BiliPink") : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DanmakuSettingsPanel: View {
    @Binding var config: DanmakuEngineConfig
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("弹幕设置")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
            }

            Toggle("屏蔽滚动", isOn: $config.blockScroll)
                .tint(Color("BiliPink"))
            Toggle("屏蔽顶部", isOn: $config.blockTop)
                .tint(Color("BiliPink"))
            Toggle("屏蔽底部", isOn: $config.blockBottom)
                .tint(Color("BiliPink"))
            Toggle("屏蔽彩色", isOn: $config.blockColorful)
                .tint(Color("BiliPink"))
        }
        .foregroundStyle(.white)
        .font(.system(size: 14, weight: .medium))
        .padding(14)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
    }
}

private struct FavoriteFolderRow: View {
    let folder: FavoriteFolderItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: folder.isPrivate ? "folder.fill.badge.person.crop" : "folder.fill")
                    .foregroundStyle(.primary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Text("\(folder.mediaCount)个内容 \(folder.isPrivate ? "私密" : "公开")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color("BiliPink") : .secondary)
                    .imageScale(.large)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 独立的视频菜单组件，避免跟随视频时间的高频刷新

private struct PlaybackRateMenuView: View, Equatable {
    let selectedRate: Double
    let onUserInteracted: () -> Void
    let onSelect: (Double) -> Void

    static func == (lhs: PlaybackRateMenuView, rhs: PlaybackRateMenuView) -> Bool {
        lhs.selectedRate == rhs.selectedRate
    }

    var body: some View {
        Picker(selection: playbackRateSelection) {
            let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
            ForEach(rates, id: \.self) { rate in
                Text(playbackRateText(rate))
                    .tag(rate)
            }
        } label: {
            Text(playbackRateMenuLabel)
                .foregroundStyle(.white)
                .font(.system(size: 12, weight: .semibold))
                .padding(8)
        }
        .pickerStyle(.menu)
        .tint(.white)
    }

    private var playbackRateMenuLabel: String {
        selectedRate == 1.0 ? "倍速" : playbackRateText(selectedRate)
    }

    private var playbackRateSelection: Binding<Double> {
        Binding(
            get: { selectedRate },
            set: { newRate in
                onUserInteracted()
                onSelect(newRate)
            }
        )
    }

    private func playbackRateText(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }
}

private struct QualityMenuView: View, Equatable {
    let options: [VideoQualityOption]
    let selectedCode: Int?
    let onUserInteracted: () -> Void
    let onSelect: (Int) -> Void

    static func == (lhs: QualityMenuView, rhs: QualityMenuView) -> Bool {
        lhs.selectedCode == rhs.selectedCode && lhs.options.count == rhs.options.count
    }

    var body: some View {
        Picker(selection: qualitySelection) {
            ForEach(options) { option in
                Text(option.label)
                    .tag(Optional(option.code))
            }
        } label: {
            Text(currentQualityLabel)
                .foregroundStyle(.white)
                .font(.system(size: 12, weight: .semibold))
                .padding(8)
        }
        .pickerStyle(.menu)
        .tint(.white)
    }

    private var currentQualityLabel: String {
        if let selectedCode = selectedCode,
           let selected = options.first(where: { $0.code == selectedCode })
        {
            return selected.label
        }
        return "清晰度"
    }

    private var qualitySelection: Binding<Int?> {
        Binding(
            get: { selectedCode },
            set: { newCode in
                guard let newCode else { return }
                onUserInteracted()
                onSelect(newCode)
            }
        )
    }
}

// MARK: - 独立的更多菜单，避免跟随播放进度高频重建导致系统 Menu 失效

private struct MoreActionsMenuView: View, Equatable {
    let onUserInteracted: () -> Void
    let onCacheVideo: () -> Void
    let onShowVideoStreamInfo: () -> Void

    static func == (lhs: MoreActionsMenuView, rhs: MoreActionsMenuView) -> Bool {
        true
    }

    var body: some View {
        // 保持菜单结构静态，避免父视图因 currentTime 高频更新时重建系统 Menu。
        Menu {
            Button("缓存视频") {
                onUserInteracted()
                onCacheVideo()
            }

            Button("视频流信息") {
                onUserInteracted()
                onShowVideoStreamInfo()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 40, height: 40)
        }
        .glassEffect(
            .regular.interactive(),
            in: .circle
        )
    }
}

// MARK: - 视频控制器覆盖

struct PlayerLoadingOverlay: View {
    let isVisible: Bool
    let speedBytesPerSecond: Double

    var body: some View {
        if isVisible {
            VStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .controlSize(.regular)

                Text(formattedSpeed)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                .black.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var formattedSpeed: String {
        let speed = max(speedBytesPerSecond, 0)
        let kilobytes = speed / 1024.0
        guard kilobytes >= 1024 else {
            return "\(format(kilobytes)) KB/s"
        }
        return "\(format(kilobytes / 1024.0)) MB/s"
    }

    private func format(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }
}

private struct PlayerControlsOverlay: View {
    @Binding var danmakuEnabled: Bool

    let onShowDanmakuSettings: () -> Void
    let onShowSponsorSegments: () -> Void
    let onShowSponsorSubmit: () -> Void
    let isFullscreen: Bool
    let isFullscreenDanmakuPanelVisible: Bool
    let qualityOptions: [VideoQualityOption]
    let selectedQualityCode: Int?
    let selectedPlaybackRate: Double
    let isVisible: Bool
    let showsSponsorButton: Bool
    let showsSponsorInfoButton: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedUntil: TimeInterval
    let isPlaying: Bool
    let segments: [ProgressSegment]
    let onBack: () -> Void
    let onUserInteracted: () -> Void
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onFullscreen: () -> Void
    let onCacheVideo: () -> Void
    let onShowVideoStreamInfo: () -> Void
    let onSelectQuality: (Int) -> Void
    let onSelectPlaybackRate: (Double) -> Void
    let onSeekPreviewChanged: (TimeInterval?) -> Void

    var body: some View {
        ZStack {
            if isVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomBar
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: isVisible)
            }
        }
        .allowsHitTesting(isVisible)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            // 左上角返回
            Button(action: {
                onUserInteracted()
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(
                .regular.interactive(),
                in: .circle
            )

            Spacer()

            // 空降助手-标记片段 按钮
            if showsSponsorButton && !isFullscreen {
                Button(action: {
                    onUserInteracted()
                    onShowSponsorSubmit()
                }) {
                    Image("SponsorBlockerStart")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                }
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )
            }

            // 空降助手-列表 按钮
            if showsSponsorButton && showsSponsorInfoButton {
                Button(action: {
                    onUserInteracted()
                    onShowSponsorSegments()
                }) {
                    Image("SponsorBlockerInfo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                }
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )
            }

            if !isFullscreen {
                // 右上角弹幕设置按钮
                Button(action: {
                    onUserInteracted()
                    onShowDanmakuSettings()
                }) {
                    Image("DanmakuSetting")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                }
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )
            }

            MoreActionsMenuView(
                onUserInteracted: onUserInteracted,
                onCacheVideo: onCacheVideo,
                onShowVideoStreamInfo: onShowVideoStreamInfo
            )
            .equatable()
        }
        .padding(12)
    }

    private var bottomBar: some View {
        Group {
            if isFullscreen {
                fullscreenBottomBar
            } else {
                regularBottomBar
            }
        }
    }

    private var regularBottomBar: some View {
        HStack(spacing: 10) {
            Button(action: {
                onUserInteracted()
                onTogglePlayPause()
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .glassEffect(
                .regular.interactive(),
                in: .circle
            )

            VideoProgressBar(
                currentTime: currentTime,
                duration: duration,
                bufferedUntil: bufferedUntil,
                segments: segments,
                onSeek: { t in onSeek(t) },
                onUserInteracted: onUserInteracted,
                onSeekPreviewChanged: onSeekPreviewChanged
            )

            Text("\(formatMMSS(currentTime))/\(formatMMSS(duration))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .glassEffect(
                    .regular,
                    in: .capsule
                )

            Button(action: {
                onUserInteracted()
                onFullscreen()
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .glassEffect(
                .regular.interactive(),
                in: .circle
            )
            .accessibilityLabel("全屏")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var fullscreenBottomBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(formatMMSS(currentTime))/\(formatMMSS(duration))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 12)

            VideoProgressBar(
                currentTime: currentTime,
                duration: duration,
                bufferedUntil: bufferedUntil,
                segments: segments,
                onSeek: { t in onSeek(t) },
                onUserInteracted: onUserInteracted,
                onSeekPreviewChanged: onSeekPreviewChanged
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)

            HStack {
                HStack(spacing: 10) {
                    // 播放/暂停按钮
                    actionCircleButton(systemName: isPlaying ? "pause.fill" : "play.fill") {
                        onUserInteracted()
                        onTogglePlayPause()
                    }
                    // 横屏下的弹幕设置按钮
                    actionCircleButton(imageName: "DanmakuSetting") {
                        onUserInteracted()
                        onShowDanmakuSettings()
                    }
                    // 横屏下的弹幕开关按钮
                    actionCircleButton(imageName: danmakuEnabled ? "DanmakuOn" : "DanmakuOff") {
                        onUserInteracted()
                        danmakuEnabled.toggle()
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    // 倍速目录
                    PlaybackRateMenuView(
                        selectedRate: selectedPlaybackRate,
                        onUserInteracted: onUserInteracted,
                        onSelect: onSelectPlaybackRate
                    )
                    .equatable()

                    // 画质目录
                    QualityMenuView(
                        options: qualityOptions,
                        selectedCode: selectedQualityCode,
                        onUserInteracted: onUserInteracted,
                        onSelect: onSelectQuality
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 10)
    }

    private func actionCircleButton(
        systemName: String? = nil,
        imageName: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                } else if let imageName {
                    Image(imageName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 32, height: 32)
        }
        .glassEffect(
            .regular.interactive(),
            in: .circle
        )
    }

    // MARK: - 格式化时间（分钟:秒）

    private func formatMMSS(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
}

// MARK: - 视频进度条 (Segment-Friendly)

private func progressColorForCategory(_ category: String) -> Color? {
    switch category {
    case "sponsor":
        return .green
    case "selfpromo":
        return .yellow
    case "interaction":
        return .purple
    case "poi_highlight":
        return .pink
    case "intro":
        return .cyan
    case "outro":
        return .indigo
    case "preview":
        return .blue
    case "padding":
        return .black
    case "filler":
        return .purple
    case "music_offtopic":
        return .orange
    default:
        return nil
    }
}

func fullSegmentBannerInfo(for category: String) -> (text: String, color: Color)? {
    switch category {
    case "exclusive_access":
        return ("独家访问/抢先体验", .mint)
    case "sponsor":
        return ("赞助/恰饭", .green)
    case "selfpromo":
        return ("无偿/自我推广", .yellow)
    case "interaction":
        return ("互动提醒", .purple)
    case "poi_highlight":
        return ("精彩时刻", .pink)
    case "intro":
        return ("开场动画", .cyan)
    case "outro":
        return ("结束画面", .indigo)
    case "preview":
        return ("回顾/概要", .blue)
    case "padding":
        return ("填充内容", .black)
    case "filler":
        return ("闲聊/玩笑", .purple)
    case "music_offtopic":
        return ("非音乐部分", .orange)
    default:
        return nil
    }
}

func formatSegmentTime(_ seconds: TimeInterval) -> String {
    let safeSeconds = max(0, Int(seconds.rounded(.down)))
    let hours = safeSeconds / 3600
    let minutes = (safeSeconds % 3600) / 60
    let remainingSeconds = safeSeconds % 60

    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    return String(format: "%02d:%02d", minutes, remainingSeconds)
}

private struct ProgressSegment: Identifiable, Equatable {
    let id = UUID()
    /// 0...1
    let start: Double
    /// 0...1, must be >= start
    let end: Double
    let color: Color
    let opacity: Double

    init(start: Double, end: Double, color: Color, opacity: Double = 0.45) {
        self.start = start
        self.end = end
        self.color = color
        self.opacity = opacity
    }
}

private struct VideoProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedUntil: TimeInterval
    let segments: [ProgressSegment]
    let onSeek: (TimeInterval) -> Void
    let onUserInteracted: () -> Void
    let onSeekPreviewChanged: (TimeInterval?) -> Void

    @GestureState private var isDragging = false
    @State private var dragProgress: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            VideoProgressTrack(
                width: w,
                height: 4,
                playedProgress: dragProgress ?? normalizedProgress(currentTime, duration: duration),
                bufferedProgress: normalizedProgress(bufferedUntil, duration: duration),
                segments: segments,
                playedColor: Color.white.opacity(0.95),
                showsKnob: true,
                knobOpacity: isDragging ? 1 : 0.9
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        onUserInteracted()
                        let p = min(max(value.location.x / w, 0), 1)
                        dragProgress = p
                        if duration > 0 {
                            onSeekPreviewChanged(duration * p)
                        } else {
                            onSeekPreviewChanged(nil)
                        }
                    }
                    .onEnded { value in
                        onUserInteracted()
                        let p = min(max(value.location.x / w, 0), 1)
                        dragProgress = nil
                        onSeekPreviewChanged(nil)
                        guard duration > 0 else { return }
                        onSeek(duration * p)
                    }
            )
        }
        .frame(height: 22)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}

private struct ReadOnlyVideoProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedUntil: TimeInterval
    let segments: [ProgressSegment]

    var body: some View {
        GeometryReader { geo in
            VideoProgressTrack(
                width: max(1, geo.size.width),
                height: 2,
                playedProgress: normalizedProgress(currentTime, duration: duration),
                bufferedProgress: normalizedProgress(bufferedUntil, duration: duration),
                segments: segments,
                playedColor: Color("BiliPink"),
                showsKnob: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 2)
    }
}

private struct VideoShotPreviewCard: View {
    let frame: VideoShotFrame?
    let fallbackAspectRatio: Double

    private var cardAspectRatio: CGFloat {
        if let frame, frame.tileHeight > 0 {
            return CGFloat(frame.tileWidth) / CGFloat(frame.tileHeight)
        }
        let safeRatio = fallbackAspectRatio > 0 ? fallbackAspectRatio : (16.0 / 9.0)
        return CGFloat(safeRatio)
    }

    var body: some View {
        Group {
            if let frame {
                VideoShotSpriteTileView(frame: frame)
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .frame(width: 160, height: 160 / cardAspectRatio)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.96), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 8)
        .allowsHitTesting(false)
    }
}

private struct VideoShotSpriteTileView: View {
    let frame: VideoShotFrame

#if canImport(UIKit)
    @State private var image: UIImage?
#endif
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geo in
            let tileWidth = max(1, CGFloat(frame.tileWidth))
            let tileHeight = max(1, CGFloat(frame.tileHeight))
            let totalWidth = tileWidth * CGFloat(max(1, frame.columns))
            let totalHeight = tileHeight * CGFloat(max(1, frame.rows))
            let scaleX = geo.size.width / tileWidth
            let scaleY = geo.size.height / tileHeight

            ZStack {
#if canImport(UIKit)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: totalWidth * scaleX, height: totalHeight * scaleY)
                        .offset(
                            x: -CGFloat(frame.column) * tileWidth * scaleX,
                            y: -CGFloat(frame.row) * tileHeight * scaleY
                        )
                } else if isLoading {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            ProgressView()
                                .tint(.white)
                        }
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                }
#else
                Rectangle()
                    .fill(Color.white.opacity(0.1))
#endif
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
#if canImport(UIKit)
        .task(id: frame.sheetURL.absoluteString) {
            await loadSpriteSheetIfNeeded()
        }
#endif
    }

#if canImport(UIKit)
    @MainActor
    private func loadSpriteSheetIfNeeded() async {
        if image != nil || isLoading { return }
        isLoading = true
        defer { isLoading = false }
        image = await VideoShotSpriteLoader.shared.loadImage(from: frame.sheetURL)
    }
#endif
}

#if canImport(UIKit)
private actor VideoShotSpriteLoader {
    static let shared = VideoShotSpriteLoader()

    private let cache = NSCache<NSURL, UIImage>()

    func loadImage(from url: URL) async -> UIImage? {
        let nsURL = url as NSURL
        if let cached = cache.object(forKey: nsURL) {
            return cached
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 30
        )
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let cookie = LoginSession.shared.cookieString
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode),
              let image = UIImage(data: data)
        else {
            return nil
        }

        cache.setObject(image, forKey: nsURL)
        return image
    }
}
#endif

private struct VideoProgressTrack: View {
    let width: CGFloat
    let height: CGFloat
    let playedProgress: Double
    let bufferedProgress: Double
    let segments: [ProgressSegment]
    let playedColor: Color
    let showsKnob: Bool
    var knobOpacity: Double = 1

    var body: some View {
        let clampedPlayedProgress = min(max(playedProgress, 0), 1)
        let clampedBufferedProgress = min(max(bufferedProgress, 0), 1)
        let knobSize: CGFloat = 10

        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.2))
                .frame(height: height)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.5))
                .frame(width: width * clampedBufferedProgress, height: height)

            ForEach(segments) { seg in
                let s = min(max(seg.start, 0), 1)
                let e = min(max(seg.end, 0), 1)
                if e > s {
                    Capsule(style: .continuous)
                        .fill(seg.color.opacity(seg.opacity))
                        .frame(width: width * (e - s), height: height)
                        .offset(x: width * s)
                }
            }

            Capsule(style: .continuous)
                .fill(playedColor)
                .frame(width: width * clampedPlayedProgress, height: height)

            if showsKnob {
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                    .offset(x: width * clampedPlayedProgress - knobSize / 2)
                    .opacity(knobOpacity)
            }
        }
    }
}

private func normalizedProgress(_ value: TimeInterval, duration: TimeInterval) -> Double {
    guard duration > 0 else { return 0 }
    return min(max(value / duration, 0), 1)
}

// MARK: - DASH 流详情窗口

struct DashStreamDebugPanel: View {
    let stream: DashStream
    let player: MPVKitPlayer?
    let playerSnapshot: PlayerUIPlaybackSnapshot
    let selectedQualityCode: Int?
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("DASH 流详情")
                        .font(.headline)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("视频参数").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow(
                                "画质",
                                qualityDescription(
                                    selectedQualityCode ?? stream.qualityCode
                                )
                            )
                            InfoRow("分辨率", "\(stream.width)×\(stream.height)")
                            InfoRow("宽高比", String(format: "%.2f:1", stream.aspectRatio))
                            InfoRow("帧率", "\(stream.fps) fps")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("编码信息").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow("视频编码", stream.videoCodec)
                            InfoRow("音频编码", stream.audioCodec)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("码率").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            InfoRow("视频码率", formatBitrate(stream.videoBitrate))
                            InfoRow("音频码率", formatBitrate(stream.audioBitrate))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("流地址").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            URIRow("视频", stream.videoURL.absoluteString)
                            URIRow("音频", stream.audioURL.absoluteString)
                        }

                        if let player = player {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("播放器状态").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                                InfoRow("播放状态", playerSnapshot.isPlaying ? "播放中" : "已暂停")
                                InfoRow("当前时间", formatTime(playerSnapshot.currentTime))
                                InfoRow("总时长", formatTime(playerSnapshot.duration))
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("解码器").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                                InfoRow("硬件解码", player.hwdecCurrent.isEmpty ? "—" : player.hwdecCurrent)
                                InfoRow("视频解码器", player.videoCodec.isEmpty ? "—" : player.videoCodec)
                                InfoRow("音频解码器", player.audioCodec.isEmpty ? "—" : player.audioCodec)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("高动态视频").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                                InfoRow("显示增强", playerSnapshot.hdrDiagnostics.isEnabledInSettings ? "已开启" : "已关闭")
                                InfoRow("视频类型", dynamicRangeSourceLabel(for: playerSnapshot.hdrDiagnostics))
                                InfoRow("高动态显示请求", playerSnapshot.hdrDiagnostics.requestsExtendedRange ? "已开启" : "未开启")
                                InfoRow("高动态显示状态", playerSnapshot.hdrDiagnostics.extendedRangeActive ? "生效中" : "未生效")
                                InfoRow(
                                    "当前 / 最大高光余量",
                                    String(
                                        format: "%.2f / %.2f",
                                        playerSnapshot.hdrDiagnostics.currentEDRHeadroom,
                                        playerSnapshot.hdrDiagnostics.potentialEDRHeadroom
                                    )
                                )
                                InfoRow("显示色域", fallback(playerSnapshot.hdrDiagnostics.displayGamut))
                                InfoRow("显示空间", fallback(playerSnapshot.hdrDiagnostics.displayColorSpace))
                                InfoRow("亮度映射", fallback(playerSnapshot.hdrDiagnostics.toneMapping))
                                InfoRow("视频色域", fallback(playerSnapshot.hdrDiagnostics.videoPrimaries))
                                InfoRow("亮度曲线", fallback(playerSnapshot.hdrDiagnostics.videoGamma))
                                InfoRow("色阶范围", fallback(playerSnapshot.hdrDiagnostics.videoColorLevels))
                                InfoRow("色彩矩阵", fallback(playerSnapshot.hdrDiagnostics.videoColorMatrix))
                                InfoRow("解码像素格式", fallback(playerSnapshot.hdrDiagnostics.videoPixelFormat))
                                InfoRow("硬件像素格式", fallback(playerSnapshot.hdrDiagnostics.videoHardwarePixelFormat))
                                InfoRow("峰值亮度估计", fallback(playerSnapshot.hdrDiagnostics.videoSignalPeak))
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(16)
        }
    }

    // MARK: - 格式化比特率

    private func formatBitrate(_ bitrate: Int) -> String {
        let kbps = Double(bitrate) / 1000
        return String(format: "%.2f Kbps", kbps)
    }

    private func qualityDescription(_ code: Int) -> String {
        "\(DashStreamSelector.qualityLabel(for: code)) (\(code))"
    }

    // MARK: - 格式化时间

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func dynamicRangeSourceLabel(for diagnostics: HDRPlaybackDiagnostics) -> String {
        diagnostics.likelyHDRSource ? "HDR / 杜比视界" : "标准动态范围"
    }

    private func fallback(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct URIRow: View {
    let label: String
    let url: String

    init(_ label: String, _ url: String) {
        self.label = label
        self.url = url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(url)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var ns

        var body: some View {
            VideoDetailPage(
                video: VideoItem(
                    bvid: "BV1WsD1BhEvt",
                    cid: 37424204720,
                    cover: "https://picsum.photos/800/450",
                    title: "七里香 格温",
                    playCount: "12.9万",
                    danmakuCount: "345",
                    uploader: "还有下次的叭",
                    duration: 325,
                    progressSeconds: nil,
                    publishTimeText: "2026-05-25",
                    bottomRcmdReasonText: nil
                ),
                namespace: ns,
                onBack: {}
            )
        }
    }

    return PreviewWrapper()
}

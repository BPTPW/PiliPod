import SwiftUI
#if canImport(UIKit)
import MediaPlayer
import UIKit
#endif

struct VideoPlayerPreviewDraftInfo {
    let start: TimeInterval
    let end: TimeInterval
    let actionType: VideoDetailPage.SponsorBlockDraftActionType
}

struct VideoDetailPlayerSurfaceView: View {
    enum DragInteractionMode {
        case none
        case speedBoost
        case horizontalSeek
        case brightnessAdjust
        case volumeAdjust
    }

    let stream: DashStream
    let player: MPVKitPlayer
    let playerViewID: String
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets
    let nonFullscreenBackSwipeReservedWidth: CGFloat
    let maxHorizontalSeekOffset: TimeInterval
    let verticalBrightnessDragSensitivity: Double
    let progressSegments: [ProgressSegment]
    let danmakuElements: [Bilibili_Community_Service_Dm_V1_DanmakuElem]
    let danmakuOverlayConfig: DanmakuEngineConfig
    let qualityOptions: [VideoQualityOption]
    let selectedQualityCode: Int?
    let selectedPlaybackRate: Double
    let showsSponsorButton: Bool
    let showsSponsorInfoButton: Bool
    let videoShotMetadata: VideoShotPreviewMetadata?
    let manualSkipTitle: String?
    let previewDraftInfo: VideoPlayerPreviewDraftInfo?
    let currentVideoDurationFallback: TimeInterval
    let onBack: () -> Void
    let onShowDanmakuSettingsSheet: () -> Void
    let onShowSponsorSegments: () -> Void
    let onShowSponsorSubmit: () -> Void
    let onCacheVideo: () -> Void
    let onReloadVideo: () -> Void
    let onSelectQuality: (Int) -> Void
    let onSelectPlaybackRate: (Double) -> Void
    let onManualSkip: () -> Void
    let onPlaybackStateSync: (String) -> Void
    let onPlaybackTick: (TimeInterval) -> Void
    let onPreloadDanmakuBoundary: (TimeInterval) -> Void
    let onPreviewDraftFinished: () -> Void
    let onPlaybackEnded: () -> Void
    let onToggleFullscreen: () -> Void

    @Binding var danmakuConfig: DanmakuEngineConfig
    @Binding var isDanmakuEnabled: Bool
    @Binding var isFullscreen: Bool

    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
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
    @State private var isFullscreenDanmakuPanelVisible = false
    @State private var playerUISnapshot = PlayerUIPlaybackSnapshot()
    @State private var lastDanmakuPrefetchSegment = 0
    @State private var lastNowPlayingSyncedSecond: Int?
    @State private var showDebugPanel = false
    @State private var debugPanelRefreshTask: Task<Void, Never>?

    private var playerHeight: CGFloat {
        isFullscreen
            ? containerSize.height + safeAreaInsets.top + safeAreaInsets.bottom
            : min(containerSize.width / stream.aspectRatio, containerSize.width * (4.0 / 3.0))
    }

    var body: some View {
        ZStack(alignment: .center) {
            MPVKitPlayerView(player: player)
                .id(playerViewID)
                .aspectRatio(stream.aspectRatio, contentMode: .fit)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: isFullscreen ? .infinity : nil,
                    alignment: .center
                )
                .clipped()
                .ignoresSafeArea(isFullscreen ? .all : [])
                .background(Color.black)
                .contentShape(Rectangle())
                .onTapGesture {
                    showControlsAndAutoHideIfNeeded(forceShow: false)
                }
                .highPriorityGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            togglePlayback()
                            showControlsAndAutoHideIfNeeded(forceShow: true)
                        }
                )
                .simultaneousGesture(playerGesture)
                .overlay {
                    DanmakuOverlayView(
                        currentTime: player.currentTime,
                        isPlaying: player.isPlaying,
                        elements: danmakuElements,
                        config: danmakuOverlayConfig
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
                            .frame(height: 60 + safeAreaInsets.top / 2)
                            .frame(maxWidth: .infinity, alignment: .top)

                            Spacer(minLength: 0)

                            LinearGradient(
                                colors: [Color.black.opacity(0), Color.black.opacity(0.68)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 65 + safeAreaInsets.bottom / 2)
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
                            duration: effectiveDuration,
                            bufferedUntil: playerUISnapshot.bufferedUntil,
                            segments: progressSegments
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                    }
                }
                .overlay {
                    PlayerControlsOverlay(
                        danmakuEnabled: danmakuEnabledBinding,
                        onShowDanmakuSettings: {
                            if isFullscreen {
                                isFullscreenDanmakuPanelVisible.toggle()
                            } else {
                                onShowDanmakuSettingsSheet()
                            }
                        },
                        onShowSponsorSegments: onShowSponsorSegments,
                        onShowSponsorSubmit: onShowSponsorSubmit,
                        isFullscreen: isFullscreen,
                        isFullscreenDanmakuPanelVisible: isFullscreenDanmakuPanelVisible,
                        qualityOptions: qualityOptions,
                        selectedQualityCode: selectedQualityCode,
                        selectedPlaybackRate: selectedPlaybackRate,
                        isVisible: controlsVisible,
                        showsSponsorButton: showsSponsorButton,
                        showsSponsorInfoButton: showsSponsorInfoButton,
                        currentTime: activeSeekPreviewTime(duration: playerUISnapshot.duration) ?? playerUISnapshot.currentTime,
                        duration: effectiveDuration,
                        bufferedUntil: playerUISnapshot.bufferedUntil,
                        isPlaying: playerUISnapshot.isPlaying,
                        segments: progressSegments,
                        onBack: onBack,
                        onUserInteracted: {
                            showControlsAndAutoHideIfNeeded(forceShow: true)
                        },
                        onTogglePlayPause: {
                            togglePlayback()
                        },
                        onSeek: { time in
                            seekPlayback(to: time)
                            showControlsAndAutoHideIfNeeded(forceShow: true)
                        },
                        onFullscreen: onToggleFullscreen,
                        onCacheVideo: onCacheVideo,
                        onReloadVideo: onReloadVideo,
                        onShowVideoStreamInfo: toggleDebugPanel,
                        onSelectQuality: onSelectQuality,
                        onSelectPlaybackRate: onSelectPlaybackRate,
                        onSeekPreviewChanged: { previewTime in
                            progressDragPreviewTime = previewTime
                        }
                    )
                }
                .overlay(alignment: .trailing) {
                    if controlsVisible && isFullscreen && isFullscreenDanmakuPanelVisible {
                        DanmakuSettingsPanel(
                            config: $danmakuConfig,
                            isDanmakuEnabled: $isDanmakuEnabled,
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
                        Text("\(formatMMSS(seekPreview))/\(formatMMSS(effectiveDuration))")
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
                            frame: videoShotMetadata?.frame(at: previewTime),
                            fallbackAspectRatio: stream.aspectRatio
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let manualSkipTitle {
                        Button(action: onManualSkip) {
                            Text("跳过：\(manualSkipTitle)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .tint(.primary)
                        .padding(.leading, 16)
                        .padding(.bottom, isFullscreen ? 120 : 50)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .overlay {
                    if isBrightnessAdjusting {
                        valueHud(systemName: "sun.max", value: brightnessPreviewValue)
                    }
                }
                .overlay {
                    if isVolumeAdjusting {
                        valueHud(
                            systemName: "speaker.wave.3",
                            value: volumePreviewValue,
                            variableValue: volumePreviewValue
                        )
                    }
                }
                .overlay {
                    if showDebugPanel {
                        DashStreamDebugPanel(
                            stream: stream,
                            player: player,
                            playerSnapshot: playerUISnapshot,
                            selectedQualityCode: selectedQualityCode,
                            onDismiss: {
                                showDebugPanel = false
                                stopDebugPanelRefresh()
                            }
                        )
                    }
                }
                .onAppear {
                    playerUISnapshot = player.uiSnapshot
                    showControlsAndAutoHideIfNeeded(forceShow: true)
                }
                .onDisappear {
                    hideControlsTask?.cancel()
                    speedBoostTriggerTask?.cancel()
                    stopDebugPanelRefresh()
                }
                .onChange(of: player.uiSnapshot) { oldSnapshot, snapshot in
                    playerUISnapshot = snapshot
                    handleSnapshotChange(oldSnapshot: oldSnapshot, snapshot: snapshot)
                }
                .frame(width: containerSize.width, height: playerHeight, alignment: .center)
                .clipped()
                .layoutPriority(1)
        }
    }

    private var playerGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isFullscreen, value.startLocation.x <= nonFullscreenBackSwipeReservedWidth {
                    return
                }

                if dragInteractionMode == .horizontalSeek {
                    let width = max(1, containerSize.width)
                    let ratio = Double(value.translation.width / width)
                    let delta = ratio * maxHorizontalSeekOffset
                    let target = clampSeekTime(horizontalSeekBaseTime + delta, duration: effectiveDuration)
                    horizontalSeekPreviewTime = target
                    return
                }

                if dragInteractionMode == .brightnessAdjust {
                    let height = max(1, playerHeight)
                    let delta = Double(-value.translation.height / height) * verticalBrightnessDragSensitivity
                    let target = clampUnit(brightnessAdjustBaseValue + delta)
                    brightnessPreviewValue = target
                    setScreenBrightness(target)
                    return
                }

                if dragInteractionMode == .volumeAdjust {
                    let height = max(1, playerHeight)
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
                    endSpeedBoostIfNeeded()
                }

                if isHorizontalSeeking {
                    let width = max(1, containerSize.width)
                    let ratio = Double(dx / width)
                    let delta = ratio * maxHorizontalSeekOffset
                    let target = clampSeekTime(horizontalSeekBaseTime + delta, duration: effectiveDuration)
                    horizontalSeekPreviewTime = target
                    return
                }

                let shouldStartBrightnessAdjust =
                    !isHorizontalSeeking &&
                    !isBrightnessAdjusting &&
                    value.startLocation.x <= containerSize.width * 0.5 &&
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
                    endSpeedBoostIfNeeded()
                }

                if isBrightnessAdjusting {
                    let height = max(1, playerHeight)
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
                    value.startLocation.x > containerSize.width * 0.5 &&
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
                    endSpeedBoostIfNeeded()
                }

                if isVolumeAdjusting {
                    let height = max(1, playerHeight)
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
                            beginSpeedBoostIfNeeded()
                        }
                    }
                }
            }
            .onEnded { _ in
                if dragInteractionMode == .horizontalSeek, isHorizontalSeeking {
                    if let seekTarget = horizontalSeekPreviewTime {
                        seekPlayback(to: seekTarget)
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
                endSpeedBoostIfNeeded()
                dragInteractionMode = .none
            }
    }

    private var effectiveDuration: TimeInterval {
        if playerUISnapshot.duration > 0 {
            return playerUISnapshot.duration
        }
        return currentVideoDurationFallback
    }

    private var danmakuEnabledBinding: Binding<Bool> {
        Binding(
            get: { isDanmakuEnabled },
            set: { isDanmakuEnabled = $0 }
        )
    }

    private func handleSnapshotChange(oldSnapshot: PlayerUIPlaybackSnapshot, snapshot: PlayerUIPlaybackSnapshot) {
#if canImport(UIKit)
        if oldSnapshot.isPlaying != snapshot.isPlaying {
            lastNowPlayingSyncedSecond = Int(snapshot.currentTime.rounded(.down))
            onPlaybackStateSync("player-snapshot-state-changed")
        } else if snapshot.isPlaying {
            let currentSecond = Int(snapshot.currentTime.rounded(.down))
            if lastNowPlayingSyncedSecond != currentSecond {
                lastNowPlayingSyncedSecond = currentSecond
                onPlaybackStateSync("player-progress-changed")
            }
        }
        UIApplication.shared.isIdleTimerDisabled = snapshot.isPlaying
#endif
        if !oldSnapshot.isPlaying && snapshot.isPlaying && controlsVisible {
            refreshControlsAutoHideIfNeeded()
        } else if oldSnapshot.isPlaying && !snapshot.isPlaying {
            hideControlsTask?.cancel()
        }
        if !snapshot.isPlaying, snapshot.currentTime >= snapshot.duration - 0.05, snapshot.duration > 0 {
            onPlaybackEnded()
        }
        handlePreviewDraft(snapshot.currentTime)
        onPlaybackTick(snapshot.currentTime)
        let segment = max(1, Int(snapshot.currentTime / 360.0) + 1)
        guard segment != lastDanmakuPrefetchSegment else { return }
        lastDanmakuPrefetchSegment = segment
        onPreloadDanmakuBoundary(snapshot.currentTime)
    }

    private func handlePreviewDraft(_ currentTime: TimeInterval) {
        guard let previewDraftInfo else { return }
        if previewDraftInfo.actionType == .skip,
           currentTime >= previewDraftInfo.start,
           currentTime < previewDraftInfo.end
        {
            player.seek(to: previewDraftInfo.end)
            onPreviewDraftFinished()
            return
        }

        if currentTime >= previewDraftInfo.end {
            onPreviewDraftFinished()
        }
    }

    private func showControlsAndAutoHideIfNeeded(forceShow: Bool) {
        guard !showDebugPanel else {
            controlsVisible = true
            hideControlsTask?.cancel()
            return
        }

        if forceShow {
            controlsVisible = true
        } else {
            controlsVisible.toggle()
        }

        refreshControlsAutoHideIfNeeded()
    }

    private func refreshControlsAutoHideIfNeeded() {
        hideControlsTask?.cancel()
        guard controlsVisible, playerUISnapshot.isPlaying else { return }

        hideControlsTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 3000000000)
            } catch {
                return
            }
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.22)) {
                controlsVisible = false
            }
        }
    }

    private func beginSpeedBoostIfNeeded() {
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

    private func endSpeedBoostIfNeeded() {
        guard isSpeedBoostActive else { return }
        isSpeedBoostActive = false
        player.setPlaybackRate(1.0)
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            player.resume()
        }
        playerUISnapshot = player.uiSnapshot
    }

    private func seekPlayback(to time: TimeInterval) {
        player.seek(to: time)
        playerUISnapshot = player.uiSnapshot
        onPlaybackStateSync("seek")
    }

    private func toggleDebugPanel() {
        showDebugPanel.toggle()
        if showDebugPanel {
            startDebugPanelRefresh()
        } else {
            stopDebugPanelRefresh()
        }
    }

    private func startDebugPanelRefresh() {
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
    private func setScreenBrightness(_ value: Double) { _ = value }
#endif

    private func currentSystemVolume() -> Double {
        clampUnit(systemVolumeControl.currentVolume)
    }

    private func setSystemVolume(_ value: Double) {
        systemVolumeControl.setVolume(clampUnit(value))
    }

    private func valueHud(
        systemName: String,
        value: Double,
        variableValue: Double? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemName, variableValue: variableValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            GeometryReader { valueGeo in
                let barWidth = max(1, valueGeo.size.width)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.24))
                        //.fill(.tertiary)
                        .frame(height: 4)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.95))
                        //.fill(.primary)
                        .frame(width: barWidth * clampUnit(value), height: 4)
                }
                .padding(.top, 2)
            }
            .frame(width: 100, height: 10)
        }
        .frame(height: 24, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.clear.tint(.gray), in: .capsule)
        .transition(.opacity)
    }
}

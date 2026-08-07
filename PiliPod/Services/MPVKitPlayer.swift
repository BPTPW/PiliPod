//
//  MPVKitPlayer.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import Foundation
import Observation
import UIKit

/// Rendering is deliberately independent from playback state. VOD uses the
/// existing Metal embedder while live streams use libmpv's render API, which
/// can redraw into its current viewport without recreating the video track.
protocol MPVPlaybackController: AnyObject {
    func applyHTTPHeaders(_ headers: [String: String])
    func applyPlaybackSettings(_ settings: AudioVideoSettings)
    func setAllowsViewportVideoRebind(_ enabled: Bool)
    func loadFile(_ url: URL)
    func addAudio(_ url: URL)
    func play()
    func pause()
    func setPlaybackRate(_ rate: Double)
    func stop()
    func seek(to time: TimeInterval)
    func timePosition() -> TimeInterval
    func durationValue() -> TimeInterval
    func demuxerCacheTime() -> TimeInterval
    func cacheSpeedBytesPerSecond() -> Double
    func downloadSpeedBytesPerSecond() -> Double
    func isPaused() -> Bool
    func isPausedForCache() -> Bool
    func videoCodec() -> String
    func audioCodec() -> String
    func hwdecCurrent() -> String
    func videoPixelFormat() -> String
    func videoHardwarePixelFormat() -> String
    func videoPrimaries() -> String
    func videoGamma() -> String
    func videoSignalPeak() -> String
    func videoColorLevels() -> String
    func videoColorMatrix() -> String
    func currentToneMapping() -> String
    func isExtendedDynamicRangeRequested() -> Bool
    func displayColorSpaceName() -> String
    func currentEDRHeadroom() -> CGFloat
    func potentialEDRHeadroom() -> CGFloat
    func displayGamut() -> String
}

struct PlayerUIPlaybackSnapshot: Equatable {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var bufferedUntil: TimeInterval = 0
    var isPlaying = false
    var isBuffering = false
    var loadingSpeedBytesPerSecond: Double = 0
    var hdrDiagnostics = HDRPlaybackDiagnostics()
}

struct HDRPlaybackDiagnostics: Equatable {
    var isEnabledInSettings = false
    var prefersEDROutput = false
    var requestsExtendedRange = false
    var currentEDRHeadroom: CGFloat = 1.0
    var potentialEDRHeadroom: CGFloat = 1.0
    var displayGamut = ""
    var displayColorSpace = ""
    var toneMapping = ""
    var videoPrimaries = ""
    var videoGamma = ""
    var videoPixelFormat = ""
    var videoHardwarePixelFormat = ""
    var videoColorLevels = ""
    var videoColorMatrix = ""
    var videoSignalPeak = ""

    var likelyHDRSource: Bool {
        let gamma = videoGamma.lowercased()
        let primaries = videoPrimaries.lowercased()
        return gamma.contains("pq")
            || gamma.contains("hlg")
            || primaries.contains("bt.2020")
            || primaries.contains("bt2020")
    }

    var extendedRangeActive: Bool {
        requestsExtendedRange && currentEDRHeadroom > 1.0
    }
}

@Observable
class MPVKitPlayer: NSObject {
    private static let bufferingStallThreshold: TimeInterval = 0.6
    private static let bufferingCacheAheadThreshold: TimeInterval = 0.5

    private weak var controller: (any MPVPlaybackController)?
    private var displayLink: CADisplayLink?
    private var uiRefreshTimer: Timer?
    private var pendingStream: DashStream?
    private var activeStream: DashStream?
    private var activeStreamCandidateIndex = 0
    private var playbackStartUptime: TimeInterval?
    private var pendingDirectVideoURL: URL?
    private var playbackIntent = false
    private var lastObservedPlaybackTime: TimeInterval = 0
    private var lastPlaybackProgressUptime = ProcessInfo.processInfo.systemUptime
    private let playbackSettings: AudioVideoSettings
    private let avPlayerSession: AVPlayerSession?
    private var settingsObserver: NSObjectProtocol?
    private var isAmbientModeVisible = false

    /// The selected core is captured when this playback session is created.
    /// Changing Settings therefore affects only subsequently created players.
    let usesAVPlayer: Bool
    private(set) var isAmbientModeEnabled: Bool
    private(set) var ambientGradientDuration: TimeInterval

    private(set) var isPlaying = false
    private(set) var playbackRate: Double = 1.0
    private(set) var playbackSeekRevision = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var bufferedUntil: TimeInterval = 0
    private(set) var isBuffering = false
    private(set) var loadingSpeedBytesPerSecond: Double = 0
    private(set) var hdrDiagnostics = HDRPlaybackDiagnostics()
    private(set) var uiSnapshot = PlayerUIPlaybackSnapshot()
    private(set) var playbackError: String?
    private(set) var ambientPalette = AmbientPalette.fallback

    var videoCodec: String { controller?.videoCodec() ?? "" }
    var audioCodec: String { controller?.audioCodec() ?? "" }
    var hwdecCurrent: String { controller?.hwdecCurrent() ?? "" }

    private let httpHeaders: [String: String]

    override init() {
        self.httpHeaders = [
            "Cookie": LoginSession.shared.cookieString,
            "User-Agent": "Mozilla/5.0 BiliIOS/1.0",
            "Referer": "https://www.bilibili.com/",
            "Origin": "https://www.bilibili.com"
        ]
        self.playbackSettings = AudioVideoSettingsStore.load()
        self.usesAVPlayer = playbackSettings.playerCore == .avPlayer
        self.isAmbientModeEnabled = playbackSettings.playerCore == .avPlayer
            && playbackSettings.ambientModeEnabled
        self.ambientGradientDuration = playbackSettings.ambientGradientSpeed.duration
        if playbackSettings.playerCore == .avPlayer {
            self.avPlayerSession = AVPlayerSession(
                headers: httpHeaders,
                playbackSettings: playbackSettings
            )
        } else {
            self.avPlayerSession = nil
        }
        super.init()
        avPlayerSession?.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.currentTime = snapshot.currentTime
            self.duration = snapshot.duration
            self.bufferedUntil = snapshot.bufferedUntil
            self.isPlaying = snapshot.isPlaying
            self.isBuffering = snapshot.isBuffering
            self.loadingSpeedBytesPerSecond = snapshot.loadingSpeedBytesPerSecond
            self.uiSnapshot = snapshot
            self.playbackError = self.avPlayerSession?.errorMessage
        }
        avPlayerSession?.onAmbientPalette = { [weak self] palette in
            guard let self, self.isAmbientModeEnabled else { return }
            if palette.differsVisibly(from: self.ambientPalette) {
                self.ambientPalette = palette
            }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .audioVideoSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let settings = notification.object as? AudioVideoSettings
            else { return }
            self.isAmbientModeEnabled = self.usesAVPlayer && settings.ambientModeEnabled
            self.ambientGradientDuration = settings.ambientGradientSpeed.duration
            if !self.isAmbientModeEnabled {
                self.ambientPalette = .fallback
            }
            self.avPlayerSession?.applyPlaybackSettings(settings)
            self.avPlayerSession?.setAmbientModeActive(
                self.isAmbientModeEnabled && self.isAmbientModeVisible
            )
        }
        hdrDiagnostics.isEnabledInSettings = playbackSettings.highDynamicRangeEnabled
        hdrDiagnostics.prefersEDROutput = playbackSettings.prefersEDROutput
    }

    func attach(_ controller: any MPVPlaybackController) {
        guard !usesAVPlayer else { return }
        self.controller = controller
        controller.applyHTTPHeaders(httpHeaders)
        controller.applyPlaybackSettings(playbackSettings)

        if let stream = pendingStream {
            play(stream: stream)
        } else if let url = pendingDirectVideoURL {
            play(videoURL: url)
        }
    }

    func attachAVPlayer(to view: UIView) {
        guard usesAVPlayer else { return }
        avPlayerSession?.attach(to: view)
    }

    func layoutAVPlayer(in bounds: CGRect) {
        avPlayerSession?.layout(in: bounds)
    }

    func setAmbientModeVisible(_ visible: Bool) {
        isAmbientModeVisible = visible
        avPlayerSession?.setAmbientModeActive(isAmbientModeEnabled && visible)
        if !visible {
            ambientPalette = .fallback
        }
    }

    func startPictureInPicture() {
        avPlayerSession?.startPictureInPicture()
    }

    func stopPictureInPicture() {
        avPlayerSession?.stopPictureInPicture()
    }

    func play(stream: DashStream) {
        if let avPlayerSession {
            pendingStream = nil
            pendingDirectVideoURL = nil
            playbackError = nil
            avPlayerSession.play(stream: stream)
            return
        }
        pendingStream = stream
        activeStream = stream
        activeStreamCandidateIndex = 0
        playbackStartUptime = ProcessInfo.processInfo.systemUptime
        pendingDirectVideoURL = nil
        guard let controller else { return }

        controller.setAllowsViewportVideoRebind(true)
        controller.loadFile(stream.videoURL)
        controller.addAudio(stream.audioURL)
        controller.play()
        resetPlaybackProgressTracking()
        playbackIntent = true
        isPlaying = true
        startDisplayLink()
        startUIRefreshTimerIfNeeded()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func play(videoURL: URL) {
        if let avPlayerSession {
            pendingStream = nil
            pendingDirectVideoURL = nil
            playbackError = nil
            avPlayerSession.play(liveURL: videoURL)
            return
        }
        pendingDirectVideoURL = videoURL
        pendingStream = nil
        activeStream = nil
        activeStreamCandidateIndex = 0
        playbackStartUptime = nil
        guard let controller else { return }

        controller.setAllowsViewportVideoRebind(false)
        controller.loadFile(videoURL)
        controller.play()
        resetPlaybackProgressTracking()
        playbackIntent = true
        isPlaying = true
        startDisplayLink()
        startUIRefreshTimerIfNeeded()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func resume() {
        if let avPlayerSession { avPlayerSession.resume(); return }
        controller?.play()
        resetPlaybackProgressTracking()
        playbackIntent = true
        isPlaying = true
        startDisplayLink()
        startUIRefreshTimerIfNeeded()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func pause() {
        if let avPlayerSession { avPlayerSession.pause(); return }
        controller?.pause()
        playbackIntent = false
        isPlaying = false
        isBuffering = false
        loadingSpeedBytesPerSecond = 0
        stopDisplayLink()
        stopUIRefreshTimer()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func setPlaybackRate(_ rate: Double) {
        if let avPlayerSession {
            playbackRate = max(rate, 0.1)
            avPlayerSession.setRate(playbackRate)
            return
        }
        let normalizedRate = max(rate, 0.1)
        playbackRate = normalizedRate
        controller?.setPlaybackRate(normalizedRate)
    }

    func stop() {
        if let avPlayerSession { avPlayerSession.stop(); return }
        controller?.stop()
        activeStream = nil
        activeStreamCandidateIndex = 0
        playbackStartUptime = nil
        playbackIntent = false
        isPlaying = false
        isBuffering = false
        loadingSpeedBytesPerSecond = 0
        stopDisplayLink()
        stopUIRefreshTimer()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func seek(to time: TimeInterval) {
        if let avPlayerSession {
            playbackSeekRevision &+= 1
            avPlayerSession.seek(to: time)
            return
        }
        playbackSeekRevision &+= 1
        if duration > 0 {
            currentTime = min(max(time, 0), duration)
        } else {
            currentTime = max(time, 0)
        }
        resetPlaybackProgressTracking()
        controller?.seek(to: time)
        refreshUISnapshot(includeDiagnostics: false)
    }

    private func resetPlaybackProgressTracking() {
        lastObservedPlaybackTime = currentTime
        lastPlaybackProgressUptime = ProcessInfo.processInfo.systemUptime
    }

    private func startDisplayLink() {
        if displayLink != nil { return }
        displayLink = CADisplayLink(target: self, selector: #selector(updatePlayerState))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func startUIRefreshTimerIfNeeded() {
        guard uiRefreshTimer == nil else { return }
        uiRefreshTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(updateUISnapshot),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(uiRefreshTimer!, forMode: .common)
    }

    private func stopUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
    }

    @objc private func updateUISnapshot() {
        refreshUISnapshot(includeDiagnostics: false)
    }

    func refreshDebugSnapshot() {
        refreshUISnapshot(includeDiagnostics: true)
    }

    private func refreshUISnapshot(includeDiagnostics: Bool) {
        var snapshot = PlayerUIPlaybackSnapshot(
            currentTime: currentTime,
            duration: duration,
            bufferedUntil: bufferedUntil,
            isPlaying: isPlaying,
            isBuffering: isBuffering,
            loadingSpeedBytesPerSecond: loadingSpeedBytesPerSecond,
            hdrDiagnostics: uiSnapshot.hdrDiagnostics
        )

        if includeDiagnostics, let controller {
            let diagnostics = HDRPlaybackDiagnostics(
                isEnabledInSettings: playbackSettings.highDynamicRangeEnabled,
                prefersEDROutput: playbackSettings.prefersEDROutput,
                requestsExtendedRange: controller.isExtendedDynamicRangeRequested(),
                currentEDRHeadroom: controller.currentEDRHeadroom(),
                potentialEDRHeadroom: controller.potentialEDRHeadroom(),
                displayGamut: controller.displayGamut(),
                displayColorSpace: controller.displayColorSpaceName(),
                toneMapping: controller.currentToneMapping(),
                videoPrimaries: controller.videoPrimaries(),
                videoGamma: controller.videoGamma(),
                videoPixelFormat: controller.videoPixelFormat(),
                videoHardwarePixelFormat: controller.videoHardwarePixelFormat(),
                videoColorLevels: controller.videoColorLevels(),
                videoColorMatrix: controller.videoColorMatrix(),
                videoSignalPeak: controller.videoSignalPeak()
            )
            hdrDiagnostics = diagnostics
            snapshot.hdrDiagnostics = diagnostics
        }

        uiSnapshot = snapshot
    }

    @objc private func updatePlayerState() {
        guard let controller else { return }

        let previousTime = currentTime
        let now = ProcessInfo.processInfo.systemUptime
        let time = controller.timePosition()
        if time.isFinite {
            let normalizedTime = max(time, 0)
            if duration > 0,
               normalizedTime <= 0.001,
               currentTime >= duration - 0.5,
               controller.isPaused()
            {
                currentTime = duration
            } else {
                currentTime = normalizedTime
            }
        }
        if abs(currentTime - previousTime) > 0.01 {
            lastObservedPlaybackTime = currentTime
            lastPlaybackProgressUptime = now
        }

        let total = controller.durationValue()
        if total > 0 {
            duration = total
        }

        let bufferedTime = controller.demuxerCacheTime()
        let cacheSpeedBytesPerSecond = max(controller.cacheSpeedBytesPerSecond(), 0)
        let downloadSpeedBytesPerSecond = max(controller.downloadSpeedBytesPerSecond(), 0)
        if duration > 0 {
            bufferedUntil = min(max(bufferedTime, 0), duration)
        } else {
            bufferedUntil = 0
        }
        let pausedForCache = controller.isPausedForCache()
        loadingSpeedBytesPerSecond = cacheSpeedBytesPerSecond > 0
            ? cacheSpeedBytesPerSecond
            : downloadSpeedBytesPerSecond

        let isControllerPaused = controller.isPaused()
        let reachedPlaybackEnd = duration > 0 && currentTime >= duration - 0.05
        let stalledFor = now - lastPlaybackProgressUptime
        let cacheAhead = max(bufferedTime - currentTime, 0)
        let cacheAheadIsLow = cacheAhead < Self.bufferingCacheAheadThreshold
        let stalledWhileTryingToPlay =
            playbackIntent &&
            !reachedPlaybackEnd &&
            stalledFor >= Self.bufferingStallThreshold &&
            cacheAheadIsLow
        isBuffering = pausedForCache || stalledWhileTryingToPlay

        // MPVKit exposes no structured network error callback here. If a new
        // route never starts at all, retry the original playurl candidates once
        // the startup has genuinely stalled; this avoids losing the API's
        // primary/backup URLs after a manual CDN rewrite fails.
        if playbackIntent,
           currentTime <= 0.05,
           let playbackStartUptime,
           now - playbackStartUptime >= 8,
           let activeStream,
           let fallback = activeStream.fallbackStream(at: activeStreamCandidateIndex + 1)
        {
            activeStreamCandidateIndex += 1
            self.playbackStartUptime = now
            controller.loadFile(fallback.videoURL)
            controller.addAudio(fallback.audioURL)
            controller.play()
            return
        }

        if currentTime > 0.05 {
            playbackStartUptime = nil
        }

        if playbackIntent {
            if reachedPlaybackEnd && isControllerPaused {
                playbackIntent = false
                isPlaying = false
            } else {
                isPlaying = true
            }
        } else {
            isPlaying = false
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        stopDisplayLink()
        stopUIRefreshTimer()
    }
}

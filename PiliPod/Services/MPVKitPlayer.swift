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
    private var pendingDirectVideoURL: URL?
    private var playbackIntent = false
    private var lastObservedPlaybackTime: TimeInterval = 0
    private var lastPlaybackProgressUptime = ProcessInfo.processInfo.systemUptime
    private let playbackSettings: AudioVideoSettings
    private let avPlayerSession: AVPlayerSession?

    /// The selected core is captured when this playback session is created.
    /// Changing Settings therefore affects only subsequently created players.
    let usesAVPlayer: Bool

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
        stopDisplayLink()
        stopUIRefreshTimer()
    }
}

//
//  MPVKitPlayer.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import Foundation
import Observation
import UIKit

struct PlayerUIPlaybackSnapshot: Equatable {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var bufferedUntil: TimeInterval = 0
    var isPlaying = false
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
    private weak var controller: MPVKitMetalViewController?
    private var displayLink: CADisplayLink?
    private var uiRefreshTimer: Timer?
    private var pendingStream: DashStream?
    private var pendingDirectVideoURL: URL?
    private let playbackSettings: AudioVideoSettings

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var bufferedUntil: TimeInterval = 0
    private(set) var hdrDiagnostics = HDRPlaybackDiagnostics()
    private(set) var uiSnapshot = PlayerUIPlaybackSnapshot()

    var videoCodec: String { controller?.videoCodec() ?? "" }
    var audioCodec: String { controller?.audioCodec() ?? "" }
    var hwdecCurrent: String { controller?.hwdecCurrent() ?? "" }

    private let httpHeaders: [String: String]

    override init() {
        self.httpHeaders = [
            "Cookie": LoginSession.shared.cookieString,
            "User-Agent": "Mozilla/5.0 BiliIOS/1.0",
            "Referer": "https://www.bilibili.com/"
        ]
        self.playbackSettings = AudioVideoSettingsStore.load()
        super.init()
        hdrDiagnostics.isEnabledInSettings = playbackSettings.highDynamicRangeEnabled
        hdrDiagnostics.prefersEDROutput = playbackSettings.prefersEDROutput
    }

    func attach(_ controller: MPVKitMetalViewController) {
        self.controller = controller
        controller.applyHTTPHeaders(httpHeaders)
        controller.applyPlaybackSettings(playbackSettings)

        if let stream = pendingStream {
            play(stream: stream)
        } else if let url = pendingDirectVideoURL {
            play(videoURL: url)
        }
    }

    func play(stream: DashStream) {
        pendingStream = stream
        pendingDirectVideoURL = nil
        guard let controller else { return }

        controller.loadFile(stream.videoURL)
        controller.addAudio(stream.audioURL)
        controller.play()

        startDisplayLink()
        startUIRefreshTimerIfNeeded()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func play(videoURL: URL) {
        pendingDirectVideoURL = videoURL
        pendingStream = nil
        guard let controller else { return }

        controller.loadFile(videoURL)
        controller.play()

        startDisplayLink()
        startUIRefreshTimerIfNeeded()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func resume() {
        controller?.play()
        isPlaying = true
        startDisplayLink()
        startUIRefreshTimerIfNeeded()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func pause() {
        controller?.pause()
        isPlaying = false
        stopDisplayLink()
        stopUIRefreshTimer()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func setPlaybackRate(_ rate: Double) {
        controller?.setPlaybackRate(rate)
    }

    func setKeepAspect(_ enabled: Bool) {
        controller?.setKeepAspect(enabled)
    }

    func refreshVideoOutput() {
        controller?.refreshVideoOutput()
    }

    func stop() {
        controller?.stop()
        isPlaying = false
        stopDisplayLink()
        stopUIRefreshTimer()
        refreshUISnapshot(includeDiagnostics: false)
    }

    func seek(to time: TimeInterval) {
        if duration > 0 {
            currentTime = min(max(time, 0), duration)
        } else {
            currentTime = max(time, 0)
        }
        controller?.seek(to: time)
        refreshUISnapshot(includeDiagnostics: false)
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

        let total = controller.durationValue()
        if total > 0 {
            duration = total
        }

        let cacheAhead = controller.demuxerCacheTime()
        if duration > 0 {
            bufferedUntil = min(max(currentTime + max(cacheAhead, 0), 0), duration)
        } else {
            bufferedUntil = 0
        }

        isPlaying = !controller.isPaused()
    }

    deinit {
        stopDisplayLink()
        stopUIRefreshTimer()
    }
}

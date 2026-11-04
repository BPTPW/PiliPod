//
//  PlaybackSession.swift
//  PiliPod
//

import Foundation
import Observation
import UIKit

struct PlayerUIPlaybackSnapshot: Equatable {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var bufferedUntil: TimeInterval = 0
    var isPlaying = false
    var isBuffering = false
    var loadingSpeedBytesPerSecond: Double = 0
    var hlsBridgeDiagnostics = HLSBridgeDiagnostics()
    var hdrDiagnostics = HDRPlaybackDiagnostics()
}

struct HLSBridgeDiagnostics: Equatable {
    var isActive = false
    var endpoint = ""
    var port: Int?
    var activeRequestCount = 0
    var completedRequestCount = 0
    var totalBytesTransferred: Int64 = 0
    var loadingSpeedBytesPerSecond: Double = 0
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
final class PlaybackSession: NSObject {
    private let settings: AudioVideoSettings
    private let avPlayerSession: AVPlayerSession
    private var settingsObserver: NSObjectProtocol?
    private var isAmbientModeVisible = false

    private(set) var isPlaying = false
    private(set) var playbackRate = 1.0
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
    private(set) var isAmbientModeEnabled: Bool
    private(set) var ambientGradientDuration: TimeInterval
    private(set) var listenVideoAudioEnergy: Float = 0
    private(set) var listenVideoAudioEnergyEnabled: Bool
    private(set) var listenVideoAudioDebugEnabled: Bool
    private(set) var listenVideoAudioEnvelopeTime: TimeInterval?
    private(set) var listenVideoAudioEnvelopeFrameCount = 0

    private let httpHeaders: [String: String]

    override init() {
        httpHeaders = [
            "Cookie": LoginSession.shared.cookieString,
            "User-Agent": "Mozilla/5.0 BiliIOS/1.0",
            "Referer": "https://www.bilibili.com/",
            "Origin": "https://www.bilibili.com"
        ]
        settings = AudioVideoSettingsStore.load()
        isAmbientModeEnabled = settings.ambientModeEnabled
        ambientGradientDuration = settings.ambientGradientSpeed.duration
        listenVideoAudioEnergyEnabled = settings.listenVideoAudioEnergyEnabled
        listenVideoAudioDebugEnabled = settings.listenVideoAudioDebugEnabled
        avPlayerSession = AVPlayerSession(headers: httpHeaders, playbackSettings: settings)
        super.init()

        avPlayerSession.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.currentTime = snapshot.currentTime
            self.duration = snapshot.duration
            self.bufferedUntil = snapshot.bufferedUntil
            self.isPlaying = snapshot.isPlaying
            self.isBuffering = snapshot.isBuffering
            self.loadingSpeedBytesPerSecond = snapshot.loadingSpeedBytesPerSecond
            self.uiSnapshot = snapshot
            self.playbackError = self.avPlayerSession.errorMessage
            self.hdrDiagnostics = snapshot.hdrDiagnostics
        }
        avPlayerSession.onAmbientPalette = { [weak self] palette in
            guard let self, self.isAmbientModeEnabled else { return }
            if palette.differsVisibly(from: self.ambientPalette) {
                self.ambientPalette = palette
            }
        }
        avPlayerSession.onListenVideoAudioEnergy = { [weak self] in self?.listenVideoAudioEnergy = $0 }
        avPlayerSession.onListenVideoAudioEnvelopeDebug = { [weak self] _, frameTime, frameCount in
            self?.listenVideoAudioEnvelopeTime = frameTime
            self?.listenVideoAudioEnvelopeFrameCount = frameCount
        }
        hdrDiagnostics.isEnabledInSettings = settings.highDynamicRangeEnabled
        hdrDiagnostics.prefersEDROutput = settings.prefersEDROutput
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .audioVideoSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let settings = notification.object as? AudioVideoSettings else { return }
            self.isAmbientModeEnabled = settings.ambientModeEnabled
            self.ambientGradientDuration = settings.ambientGradientSpeed.duration
            self.listenVideoAudioEnergyEnabled = settings.listenVideoAudioEnergyEnabled
            self.listenVideoAudioDebugEnabled = settings.listenVideoAudioDebugEnabled
            if !settings.listenVideoAudioEnergyEnabled {
                self.listenVideoAudioEnergy = 0
                self.listenVideoAudioEnvelopeTime = nil
                self.listenVideoAudioEnvelopeFrameCount = 0
            }
            if !settings.ambientModeEnabled { self.ambientPalette = .fallback }
            self.avPlayerSession.applyPlaybackSettings(settings)
            self.avPlayerSession.setAmbientModeActive(settings.ambientModeEnabled && self.isAmbientModeVisible)
        }
    }

    func attachAVPlayer(to view: UIView) { avPlayerSession.attach(to: view) }
    func layoutAVPlayer(in bounds: CGRect) { avPlayerSession.layout(in: bounds) }

    func setAmbientModeVisible(_ visible: Bool) {
        isAmbientModeVisible = visible
        avPlayerSession.setAmbientModeActive(isAmbientModeEnabled && visible)
        if !visible { ambientPalette = .fallback }
    }

    func startPictureInPicture() { avPlayerSession.startPictureInPicture() }

    func startPictureInPicture(
        onStarted: @escaping () -> Void,
        onRestore: @escaping () -> Void,
        onStopped: @escaping () -> Void
    ) {
        avPlayerSession.startPictureInPicture(onStarted: onStarted, onRestore: onRestore, onStopped: onStopped)
    }

    func stopPictureInPicture() { avPlayerSession.stopPictureInPicture() }
    func setListenVideoModeActive(_ active: Bool) { avPlayerSession.setListenVideoModeActive(active) }
    func play(stream: DashStream, initialSeekTime: TimeInterval? = nil) { avPlayerSession.play(stream: stream, initialSeekTime: initialSeekTime) }
    func play(videoURL: URL) { avPlayerSession.play(liveURL: videoURL) }
    func liveStreamDiagnostics() -> LiveStreamDiagnostics? { avPlayerSession.liveStreamDiagnostics() }
    func resume() { avPlayerSession.resume() }
    func pause() { avPlayerSession.pause() }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = max(rate, 0.1)
        avPlayerSession.setRate(playbackRate)
    }

    func stop() { avPlayerSession.stop() }

    func seek(to time: TimeInterval) {
        playbackSeekRevision &+= 1
        avPlayerSession.seek(to: time)
    }

    func refreshDebugSnapshot() {
        uiSnapshot = avPlayerSession.snapshot
        hdrDiagnostics = avPlayerSession.snapshot.hdrDiagnostics
    }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }
}

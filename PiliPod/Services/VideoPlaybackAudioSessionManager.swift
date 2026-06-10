//
//  VideoPlaybackAudioSessionManager.swift
//  PiliPod
//
//  Created by Codex on 2026/6/9.
//

#if canImport(UIKit)
import AVFoundation
import Combine
import MediaPlayer
import UIKit

@MainActor
final class VideoPlaybackAudioSessionManager: ObservableObject {
    struct PlaybackInfo: Equatable {
        var title: String
        var artist: String
        var artworkURL: URL?
        var duration: TimeInterval
        var elapsedTime: TimeInterval
        var playbackRate: Double
        var isPlaying: Bool
        var isLiveStream = false
        var supportsSeeking = true
    }

    private let commandCenter = MPRemoteCommandCenter.shared()
    private let audioEngine = AVAudioEngine()
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artworkLoadTask: Task<Void, Never>?
    private var currentArtworkURL: URL?
    private var currentArtworkImage: UIImage?
    private var lastPlaybackInfo: PlaybackInfo?
    private var didRegisterCommands = false
    private var silenceNode: AVAudioSourceNode?
    private var notificationObservers: [NSObjectProtocol] = []

    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var onSeek: ((TimeInterval) -> Void)?

    func configureHandlers(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.onPlay = onPlay
        self.onPause = onPause
        self.onSeek = onSeek
    }

    func activate() {
        do {
            try ensurePlaybackSessionReady(reason: "activate")
            installAudioSessionObserversIfNeeded()
            registerRemoteCommandsIfNeeded()
        } catch {
            print("[AudioSession] Failed to activate audio session: \(error.localizedDescription)")
        }
    }

    func deactivate() {
        teardown()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[AudioSession] Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    func updateNowPlaying(info: PlaybackInfo) {
        let normalizedInfo = PlaybackInfo(
            title: info.title,
            artist: info.artist,
            artworkURL: info.artworkURL,
            duration: info.duration,
            elapsedTime: info.elapsedTime,
            playbackRate: info.isPlaying ? info.playbackRate : 0,
            isPlaying: info.isPlaying,
            isLiveStream: info.isLiveStream,
            supportsSeeking: info.supportsSeeking
        )

        lastPlaybackInfo = normalizedInfo

        let session = AVAudioSession.sharedInstance()

        if currentArtworkURL != normalizedInfo.artworkURL {
            currentArtworkURL = normalizedInfo.artworkURL
            currentArtworkImage = nil
            loadArtworkIfNeeded(from: normalizedInfo.artworkURL)
        }

        if normalizedInfo.isPlaying {
            do {
                try ensurePlaybackSessionReady(reason: "updateNowPlaying.playing")
            } catch {
                print("[AudioSession] Failed to refresh playback session while playing: \(error.localizedDescription)")
            }
        } else {
            suspendPlaybackSessionIfNeeded(reason: "updateNowPlaying.paused")
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = normalizedInfo.supportsSeeking && !normalizedInfo.isLiveStream
        publishNowPlaying(info: normalizedInfo, artwork: currentArtworkImage)
    }

    private func teardown() {
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        audioEngine.stop()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        UIApplication.shared.endReceivingRemoteControlEvents()
        unregisterRemoteCommands()
        removeAudioSessionObservers()
        lastPlaybackInfo = nil
        currentArtworkURL = nil
        currentArtworkImage = nil
    }

    private func registerRemoteCommandsIfNeeded() {
        guard !didRegisterCommands else { return }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        commandTargets = [
            (
                commandCenter.playCommand,
                commandCenter.playCommand.addTarget { [weak self] _ in
                    self?.handlePlay()
                    return .success
                }
            ),
            (
                commandCenter.pauseCommand,
                commandCenter.pauseCommand.addTarget { [weak self] _ in
                    self?.handlePause()
                    return .success
                }
            ),
            (
                commandCenter.togglePlayPauseCommand,
                commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                    self?.handleToggle()
                    return .success
                }
            ),
            (
                commandCenter.changePlaybackPositionCommand,
                commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                    guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                        return .commandFailed
                    }
                    self?.handleSeek(to: event.positionTime)
                    return .success
                }
            )
        ]

        didRegisterCommands = true
    }

    private func unregisterRemoteCommands() {
        guard didRegisterCommands else { return }

        for (command, target) in commandTargets {
            command.removeTarget(target)
        }

        commandTargets.removeAll()
        didRegisterCommands = false
    }

    private func handlePlay() {
        print("[AudioSession] Remote command: play")
        onPlay?()
    }

    private func handlePause() {
        print("[AudioSession] Remote command: pause")
        onPause?()
    }

    private func handleToggle() {
        let isPlaying = lastPlaybackInfo?.isPlaying ?? false
        
        if lastPlaybackInfo?.isPlaying ?? false {
            onPause?()
        } else {
            onPlay?()
        }
    }

    private func handleSeek(to position: TimeInterval) {
        onSeek?(position)
    }

    private func publishNowPlaying(info: PlaybackInfo, artwork: UIImage?) {
        let effectiveRate = info.isPlaying ? Float(max(info.playbackRate, 0)) : 0

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.artist,
            MPNowPlayingInfoPropertyPlaybackRate: effectiveRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Float(max(info.playbackRate, 0)),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if info.isLiveStream {
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        } else {
            let effectiveDuration = max(info.duration, 0)
            let effectiveElapsed = min(
                max(info.elapsedTime, 0),
                effectiveDuration > 0 ? effectiveDuration : info.elapsedTime
            )
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = effectiveDuration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = effectiveElapsed
        }

        if let artwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                artwork
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = info.isPlaying ? .playing : .paused
    }

    private func ensurePlaybackSessionReady(reason: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        try startSilentAudioEngineIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    private func suspendPlaybackSessionIfNeeded(reason: String) {
        if audioEngine.isRunning {
            audioEngine.stop()
            print("[AudioSession][SessionSuspended] reason=\(reason) engineRunning=\(audioEngine.isRunning)")
        }
    }

    private func startSilentAudioEngineIfNeeded() throws {
        if silenceNode == nil {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
            let sourceNode = AVAudioSourceNode { _, _, _, audioBufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for buffer in buffers {
                    guard let pointer = buffer.mData else { continue }
                    memset(pointer, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }

            silenceNode = sourceNode
            audioEngine.attach(sourceNode)

            if let format {
                audioEngine.connect(sourceNode, to: audioEngine.mainMixerNode, format: format)
            } else {
                audioEngine.connect(sourceNode, to: audioEngine.mainMixerNode, format: nil)
            }
        }

        if !audioEngine.isRunning {
            try audioEngine.start()
            print("[AudioSession] Started silent audio engine")
        }
    }

    private func installAudioSessionObserversIfNeeded() {
        guard notificationObservers.isEmpty else { return }

        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleAudioSessionInterruption(notification)
            },
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleMediaServicesReset()
            },
            center.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: audioEngine,
                queue: .main
            ) { [weak self] _ in
                self?.handleAudioEngineConfigurationChange()
            }
        ]
    }

    private func removeAudioSessionObservers() {
        let center = NotificationCenter.default
        for observer in notificationObservers {
            center.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            print("[AudioSession] Received interruption with unknown payload")
            return
        }

        print("[AudioSession][Interruption] type=\(type.rawValue) lastPlaying=\(lastPlaybackInfo?.isPlaying.description ?? "nil")")

        guard type == .ended, let playbackInfo = lastPlaybackInfo, playbackInfo.isPlaying else { return }

        do {
            try ensurePlaybackSessionReady(reason: "interruptionEnded")
            publishNowPlaying(info: playbackInfo, artwork: currentArtworkImage)
        } catch {
            print("[AudioSession] Failed to recover after interruption: \(error.localizedDescription)")
        }
    }

    private func handleMediaServicesReset() {

        guard let playbackInfo = lastPlaybackInfo else { return }

        do {
            try ensurePlaybackSessionReady(reason: "mediaServicesReset")
            registerRemoteCommandsIfNeeded()
            publishNowPlaying(info: playbackInfo, artwork: currentArtworkImage)
        } catch {
            print("[AudioSession] Failed to recover after media services reset: \(error.localizedDescription)")
        }
    }

    private func handleAudioEngineConfigurationChange() {
        guard let playbackInfo = lastPlaybackInfo, playbackInfo.isPlaying else { return }

        do {
            try ensurePlaybackSessionReady(reason: "audioEngineConfigurationChange")
            publishNowPlaying(info: playbackInfo, artwork: currentArtworkImage)
        } catch {
            print("[AudioSession] Failed to recover after audio engine configuration change: \(error.localizedDescription)")
        }
    }

    private func loadArtworkIfNeeded(from url: URL?) {
        artworkLoadTask?.cancel()
        artworkLoadTask = nil

        guard let url else { return }

        artworkLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let image = await SharedRemoteImageStore.shared.image(for: url)
            guard !Task.isCancelled, self.currentArtworkURL == url else { return }

            self.currentArtworkImage = image
            print("[AudioSession] Artwork \(image == nil ? "load failed" : "loaded") for \(url.absoluteString)")

            if let playbackInfo = self.lastPlaybackInfo {
                self.publishNowPlaying(info: playbackInfo, artwork: image)
            }
        }
    }
}
#endif

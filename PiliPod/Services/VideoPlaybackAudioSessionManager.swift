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
    }

    private let commandCenter = MPRemoteCommandCenter.shared()
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artworkLoadTask: Task<Void, Never>?
    private var currentArtworkURL: URL?
    private var currentArtworkImage: UIImage?
    private var lastPlaybackInfo: PlaybackInfo?
    private var didRegisterCommands = false

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
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            registerRemoteCommandsIfNeeded()
            print("[AudioSession] Activated playback audio session")
        } catch {
            print("[AudioSession] Failed to activate audio session: \(error.localizedDescription)")
        }
    }

    func deactivate() {
        teardown()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            print("[AudioSession] Deactivated playback audio session")
        } catch {
            print("[AudioSession] Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    func updateNowPlaying(info: PlaybackInfo) {
        lastPlaybackInfo = info

        if currentArtworkURL != info.artworkURL {
            currentArtworkURL = info.artworkURL
            currentArtworkImage = nil
            loadArtworkIfNeeded(from: info.artworkURL)
        }

        publishNowPlaying(info: info, artwork: currentArtworkImage)
        print(
            "[AudioSession] Updated now playing title=\(info.title) artist=\(info.artist) " +
            "elapsed=\(Int(info.elapsedTime.rounded())) duration=\(Int(info.duration.rounded())) " +
            "rate=\(info.playbackRate) isPlaying=\(info.isPlaying)"
        )
    }

    private func teardown() {
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        unregisterRemoteCommands()
        lastPlaybackInfo = nil
        currentArtworkURL = nil
        currentArtworkImage = nil
    }

    private func registerRemoteCommandsIfNeeded() {
        guard !didRegisterCommands else { return }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

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
        print("[AudioSession] Remote command: togglePlayPause -> \(isPlaying ? "pause" : "play")")

        if isPlaying {
            onPause?()
        } else {
            onPlay?()
        }
    }

    private func handleSeek(to position: TimeInterval) {
        print("[AudioSession] Remote command: seek -> \(position)")
        onSeek?(position)
    }

    private func publishNowPlaying(info: PlaybackInfo, artwork: UIImage?) {
        let effectiveDuration = max(info.duration, 0)
        let effectiveElapsed = min(
            max(info.elapsedTime, 0),
            effectiveDuration > 0 ? effectiveDuration : info.elapsedTime
        )
        let effectiveRate = info.isPlaying ? Float(max(info.playbackRate, 0)) : 0

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.artist,
            MPMediaItemPropertyPlaybackDuration: effectiveDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: effectiveElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: effectiveRate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]

        if let artwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                artwork
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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

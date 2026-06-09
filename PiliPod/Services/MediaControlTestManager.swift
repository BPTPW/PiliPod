//
//  MediaControlTestManager.swift
//  PiliPod
//
//  Created by Codex on 2026/6/9.
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

@MainActor
final class MediaControlTestManager: ObservableObject {
    @Published var title = "PiliPod Media Test"
    @Published var artist = "Codex"
    @Published var duration: Double = 300
    @Published var progress: Double = 72
    @Published var rate: Double = 1
    @Published private(set) var isSessionActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var eventLogs: [String] = []

    private let commandCenter = MPRemoteCommandCenter.shared()
    private let audioEngine = AVAudioEngine()
    private var silenceNode: AVAudioSourceNode?
    private var playbackTask: Task<Void, Never>?
    private var commandTargets: [Any] = []
    private var didConfigureCommands = false

    deinit {
        Task { @MainActor in
            unregisterRemoteCommands()
            playbackTask?.cancel()
            audioEngine.stop()
        }
    }

    func startSession() {
        do {
            try configureAudioSession()
            try startSilentAudioEngineIfNeeded()
            registerRemoteCommandsIfNeeded()

            isSessionActive = true
            isPlaying = true
            appendLog("媒体控制已启动")
            updateNowPlaying()
            startPlaybackLoopIfNeeded()
        } catch {
            appendLog("启动失败: \(error.localizedDescription)")
        }
    }

    func stopSession() {
        playbackTask?.cancel()
        playbackTask = nil
        audioEngine.stop()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        unregisterRemoteCommands()
        isPlaying = false
        isSessionActive = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            appendLog("关闭 Audio Session 失败: \(error.localizedDescription)")
        }

        appendLog("媒体控制已关闭")
    }

    func applyNowPlayingUpdate() {
        guard isSessionActive else {
            appendLog("尚未启动媒体控制，已忽略更新")
            return
        }

        progress = normalizedProgress(progress)
        duration = max(duration, 1)
        rate = max(rate, 0)
        updateNowPlaying()
        appendLog("已更新锁屏/控制中心内容")
    }

    func clearLogs() {
        eventLogs.removeAll()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func startSilentAudioEngineIfNeeded() throws {
        if silenceNode == nil {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
            let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
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
        }
    }

    private func registerRemoteCommandsIfNeeded() {
        guard !didConfigureCommands else { return }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        commandTargets = [
            commandCenter.playCommand.addTarget { [weak self] _ in
                self?.handlePlayCommand()
                return .success
            },
            commandCenter.pauseCommand.addTarget { [weak self] _ in
                self?.handlePauseCommand()
                return .success
            },
            commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                self?.handleToggleCommand()
                return .success
            },
            commandCenter.nextTrackCommand.addTarget { [weak self] _ in
                self?.appendLog("收到远程事件: nextTrack")
                return .success
            },
            commandCenter.previousTrackCommand.addTarget { [weak self] _ in
                self?.appendLog("收到远程事件: previousTrack")
                return .success
            },
            commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }

                self.progress = self.normalizedProgress(positionEvent.positionTime)
                self.appendLog("收到远程事件: seek -> \(self.formatTime(self.progress))")
                self.updateNowPlaying()
                return .success
            }
        ]

        didConfigureCommands = true
    }

    private func unregisterRemoteCommands() {
        guard didConfigureCommands else { return }

        let commands: [MPRemoteCommand] = [
            commandCenter.playCommand,
            commandCenter.pauseCommand,
            commandCenter.togglePlayPauseCommand,
            commandCenter.nextTrackCommand,
            commandCenter.previousTrackCommand,
            commandCenter.changePlaybackPositionCommand
        ]

        for (command, target) in zip(commands, commandTargets) {
            command.removeTarget(target)
        }

        commandTargets.removeAll()
        didConfigureCommands = false
    }

    private func handlePlayCommand() {
        guard isSessionActive else {
            appendLog("收到远程事件: play，但媒体控制未启动")
            return
        }

        isPlaying = true
        appendLog("收到远程事件: play")
        updateNowPlaying()
    }

    private func handlePauseCommand() {
        guard isSessionActive else {
            appendLog("收到远程事件: pause，但媒体控制未启动")
            return
        }

        isPlaying = false
        appendLog("收到远程事件: pause")
        updateNowPlaying()
    }

    private func handleToggleCommand() {
        guard isSessionActive else {
            appendLog("收到远程事件: toggle，但媒体控制未启动")
            return
        }

        isPlaying.toggle()
        appendLog("收到远程事件: toggle -> \(isPlaying ? "play" : "pause")")
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        let effectiveDuration = max(duration, 1)
        let effectiveProgress = normalizedProgress(progress)
        let playbackRate = isPlaying ? Float(rate) : 0

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: effectiveDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: effectiveProgress,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let artwork = makeArtworkImage() {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                artwork
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func makeArtworkImage() -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 160, weight: .regular)
        return UIImage(systemName: "waveform.circle.fill", withConfiguration: configuration)?
            .withTintColor(.systemPink, renderingMode: .alwaysOriginal)
    }

    private func startPlaybackLoopIfNeeded() {
        guard playbackTask == nil else { return }

        playbackTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { break }
                await self.tickPlaybackProgress()
            }
        }
    }

    private func tickPlaybackProgress() {
        guard isSessionActive, isPlaying else { return }

        let nextProgress = progress + (0.5 * rate)
        if nextProgress >= duration {
            progress = duration
            isPlaying = false
            appendLog("播放进度到达末尾，已自动暂停")
        } else {
            progress = nextProgress
        }

        updateNowPlaying()
    }

    private func normalizedProgress(_ candidate: Double) -> Double {
        max(0, min(candidate, max(duration, 1)))
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        eventLogs.insert("[\(formatter.string(from: Date()))] \(message)", at: 0)
    }

    private func formatTime(_ value: Double) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

//
//  MPVKitPlayer.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import Foundation
import Observation
import UIKit

@Observable
class MPVKitPlayer: NSObject {
    private weak var controller: MPVKitMetalViewController?
    private var displayLink: CADisplayLink?
    private var pendingStream: DashStream?

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var bufferedUntil: TimeInterval = 0

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
        super.init()
    }

    func attach(_ controller: MPVKitMetalViewController) {
        self.controller = controller
        controller.applyHTTPHeaders(httpHeaders)

        if let stream = pendingStream {
            play(stream: stream)
        }
    }

    func play(stream: DashStream) {
        pendingStream = stream
        guard let controller else { return }

        controller.loadFile(stream.videoURL)
        controller.addAudio(stream.audioURL)
        controller.play()

        startDisplayLink()
    }

    func resume() {
        controller?.play()
        isPlaying = true
        startDisplayLink()
    }

    func pause() {
        controller?.pause()
        isPlaying = false
        stopDisplayLink()
    }

    func setPlaybackRate(_ rate: Double) {
        controller?.setPlaybackRate(rate)
    }

    func stop() {
        controller?.stop()
        isPlaying = false
        stopDisplayLink()
    }

    func seek(to time: TimeInterval) {
        if duration > 0 {
            currentTime = min(max(time, 0), duration)
        } else {
            currentTime = max(time, 0)
        }
        controller?.seek(to: time)
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
    }
}

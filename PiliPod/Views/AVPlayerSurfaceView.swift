//
//  AVPlayerSurfaceView.swift
//  PiliPod
//

import AVFoundation
import SwiftUI

struct AVPlayerSurfaceView: UIViewRepresentable {
    let player: PlaybackSession

    func makeUIView(context: Context) -> AVPlayerSurfaceHostView {
        AVPlayerSurfaceHostView(player: player)
    }

    func updateUIView(_ uiView: AVPlayerSurfaceHostView, context: Context) {
        uiView.player = player
    }

    static func dismantleUIView(_ uiView: AVPlayerSurfaceHostView, coordinator: ()) {
        uiView.layer.sublayers?.forEach { layer in
            if layer is AVPlayerLayer { layer.removeFromSuperlayer() }
        }
    }
}

final class AVPlayerSurfaceHostView: UIView {
    weak var player: PlaybackSession? {
        didSet {
            guard oldValue !== player else { return }
            player?.attachAVPlayer(to: self)
            setNeedsLayout()
        }
    }

    init(player: PlaybackSession) {
        self.player = player
        super.init(frame: .zero)
        backgroundColor = .black
        player.attachAVPlayer(to: self)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        player?.layoutAVPlayer(in: bounds)
    }
}

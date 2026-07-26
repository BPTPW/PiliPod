//
//  MPVKitPlayerView.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import AVFoundation
import SwiftUI

struct MPVKitPlayerView: UIViewControllerRepresentable {
    let player: MPVKitPlayer

    func makeUIViewController(context: Context) -> MPVKitMetalViewController {
        let controller = MPVKitMetalViewController()
        player.attach(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: MPVKitMetalViewController, context: Context) {
        uiViewController.invalidateVideoLayout()
    }
}

struct AVPlayerSurfaceView: UIViewRepresentable {
    let player: MPVKitPlayer

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
    weak var player: MPVKitPlayer? {
        didSet {
            guard oldValue !== player else { return }
            player?.attachAVPlayer(to: self)
            setNeedsLayout()
        }
    }

    init(player: MPVKitPlayer) {
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

#Preview {
    MPVKitPlayerView(player: MPVKitPlayer())
        .frame(height: 300)
}

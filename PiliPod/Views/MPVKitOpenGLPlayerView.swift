//
//  MPVKitOpenGLPlayerView.swift
//  PiliPod
//

import SwiftUI
import GLKit

/// Live-only surface backed by libmpv's OpenGL render API.
struct MPVKitOpenGLPlayerView: UIViewControllerRepresentable {
    let player: MPVKitPlayer

    func makeUIViewController(context: Context) -> MPVKitOpenGLViewController {
        let controller = MPVKitOpenGLViewController()
        player.attach(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: MPVKitOpenGLViewController, context: Context) {
        uiViewController.view.setNeedsLayout()
    }
}

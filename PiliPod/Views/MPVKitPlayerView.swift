//
//  MPVKitPlayerView.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

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

#Preview {
    MPVKitPlayerView(player: MPVKitPlayer())
        .frame(height: 300)
}

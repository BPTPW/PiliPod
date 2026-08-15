//
//  ManualPictureInPictureCoordinator.swift
//  PiliPod
//

import Foundation

enum ManualPictureInPictureRoute {
    case video(VideoItem)
    case live(LiveCardModel)
}

extension Notification.Name {
    static let manualPictureInPictureDidStart = Notification.Name("manualPictureInPictureDidStart")
    static let manualPictureInPictureRestoreRequested = Notification.Name("manualPictureInPictureRestoreRequested")
    static let manualPictureInPictureRestoreOnHome = Notification.Name("manualPictureInPictureRestoreOnHome")
}

/// Keeps the AVPlayer-backed session alive after a manually opened PiP leaves
/// its SwiftUI playback page. System-background PiP deliberately does not use
/// this coordinator.
final class ManualPictureInPictureCoordinator {
    static let shared = ManualPictureInPictureCoordinator()

    private var retainedPlayer: MPVKitPlayer?
    private var route: ManualPictureInPictureRoute?

    private init() {}

    func start(player: MPVKitPlayer, route: ManualPictureInPictureRoute) {
        guard player.usesAVPlayer else { return }
        stopIfNeeded(except: player)
        retainedPlayer = player
        self.route = route
        player.startPictureInPicture(
            onStarted: { [weak self] in
                guard let self, self.retainedPlayer === player else { return }
                NotificationCenter.default.post(name: .manualPictureInPictureDidStart, object: nil)
            },
            onRestore: { [weak self] in
                guard let self, let route = self.route else { return }
                NotificationCenter.default.post(
                    name: .manualPictureInPictureRestoreRequested,
                    object: route
                )
            },
            onStopped: { [weak self] in
                guard let self, self.retainedPlayer === player else { return }
                self.retainedPlayer = nil
                self.route = nil
            }
        )
    }

    func isRetaining(_ player: MPVKitPlayer) -> Bool {
        retainedPlayer === player
    }

    func stopIfNeeded(except player: MPVKitPlayer? = nil) {
        guard let retainedPlayer, retainedPlayer !== player else { return }
        self.retainedPlayer = nil
        route = nil
        retainedPlayer.stopPictureInPicture()
        retainedPlayer.stop()
    }
}

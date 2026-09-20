//
//  PiliPodApp.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
final class PiliPodAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedInterfaceOrientations: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedInterfaceOrientations
    }

    @MainActor
    static func updateOrientation(
        to mask: UIInterfaceOrientationMask,
        in scene: UIWindowScene? = nil
    ) {
        supportedInterfaceOrientations = mask

        guard let windowScene = scene ?? activeWindowScene else { return }
        windowScene.windows.forEach {
            $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        let preferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: mask
        )
        windowScene.requestGeometryUpdate(preferences) { error in
            print("requestGeometryUpdate failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    static var activeWindowScene: UIWindowScene? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return windowScenes.first(where: { $0.activationState == .foregroundActive })
            ?? windowScenes.first(where: { $0.activationState == .foregroundInactive })
            ?? windowScenes.first
    }
}
#endif

@main
struct PiliPodApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(PiliPodAppDelegate.self) private var appDelegate
#endif

    init() {
        CacheStorageService.configureSharedURLCacheIfNeeded()
        ErrorLogService.installUncaughtExceptionHandler()
        LoginImportService.restore()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

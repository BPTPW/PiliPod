//
//  PiliPodApp.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

@main
struct PiliPodApp: App {
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

//
//  MainTabView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct MainTabView: View {
    @State private var homeViewModel = HomeViewModel()
    @State private var selectedTab: MainTab = .home

    private enum MainTab: Hashable {
        case home
        case mine
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(viewModel: homeViewModel)
                .tag(MainTab.home)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("首页")
                }

            MyView()
                .tag(MainTab.mine)
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("我的")
                }
        }
        .onChange(of: selectedTab) { newTab in
            guard newTab == .home else { return }
            Task {
                await homeViewModel.refreshUnreadMessageCountIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .manualPictureInPictureRestoreRequested)) { notification in
            selectedTab = .home
            // Deliver a second event after the tab transition has committed.
            // This makes restoration work even when the user was in My/UserSpace.
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .manualPictureInPictureRestoreOnHome,
                    object: notification.object
                )
            }
        }
    }
}

#Preview {
    MainTabView()
}

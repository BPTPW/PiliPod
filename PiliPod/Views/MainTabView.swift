//
//  MainTabView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var homeViewModel = HomeViewModel()
    @State private var selectedTab: MainTab = .home
    @State private var profileTabAvatar: UIImage?
    @ObservedObject private var loginSession = LoginSession.shared

    private enum MainTab: Hashable {
        case home
        case dynamic
        case mine
        case search
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(String("首页"), systemImage: "house.fill", value: MainTab.home) {
                HomeView(viewModel: homeViewModel)
            }
            Tab(String("动态"), image: "DynamicIcon", value: MainTab.dynamic) {
                DynamicView()
            }
            Tab(value: MainTab.mine) {
                MyView()
            } label: {
                Label {
                    Text("我的")
                } icon: {
                    profileTabIcon
                }
            }
            // iOS 27 之后 .search 的表现行为和 iOS 26 有所区别，但我不建议使用 .prominet，会导致无法正常生成搜索框
            Tab(String("搜索"), systemImage: "magnifyingglass", value: MainTab.search, role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
        .toolbar(.visible, for: .tabBar)
        .task {
            await homeViewModel.loadUserIfNeeded()
        }
        .task(id: homeViewModel.userFace) {
            guard let face = homeViewModel.userFace,
                  let url = URL(string: face),
                  let image = await SharedRemoteImageStore.shared.image(for: url)
            else {
                profileTabAvatar = nil
                return
            }
            profileTabAvatar = tabBarAvatar(from: image)
        }
        .onReceive(loginSession.$isLogin) { isLogin in
            if isLogin {
                Task {
                    await homeViewModel.loadUserIfNeeded()
                }
            } else {
                homeViewModel.userFace = nil
                profileTabAvatar = nil
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

    private var profileTabIcon: Image {
        if loginSession.isLogin, let profileTabAvatar {
            Image(uiImage: profileTabAvatar.withRenderingMode(.alwaysOriginal))
                .renderingMode(.original)
        } else {
            Image(systemName: "person.circle")
        }
    }

    private func tabBarAvatar(from image: UIImage) -> UIImage {
        let iconSize = CGSize(width: 28, height: 28)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false

        return UIGraphicsImageRenderer(size: iconSize, format: format).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: iconSize)).addClip()

            let scale = max(iconSize.width / image.size.width, iconSize.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (iconSize.width - size.width) / 2,
                y: (iconSize.height - size.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }
}

#Preview {
    MainTabView()
}

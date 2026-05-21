//
//  MainTabView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct MainTabView: View {
    @State private var homeViewModel = HomeViewModel()

    var body: some View {
        TabView {
            HomeView(viewModel: homeViewModel)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("首页")
                }

            MineView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("我的")
                }
        }
    }
}

#Preview {
    MainTabView()
}

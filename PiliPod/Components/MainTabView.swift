//
//  MainTabView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
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

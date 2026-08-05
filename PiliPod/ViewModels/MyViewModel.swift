//
//  MyViewModel.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Combine
import Foundation

@MainActor
final class MyViewModel: ObservableObject {
    @Published var user: UserCard?
    @Published var stat: MyStat?

    func loadUser() async {
        guard LoginSession.shared.isLogin else {
            user = nil
            stat = nil
            return
        }

        do {
            async let userInfo = BiliAPI.shared.fetchMyInfo()
            async let userStat = BiliAPI.shared.fetchMyStat()

            user = try await userInfo
            stat = try await userStat
        } catch {
            ErrorLogService.record(error, context: "加载我的资料")
            print(error)
        }
    }
}

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
        let accountID = LoginSession.shared.selectedID(for: .main)
        guard LoginSession.shared.isLogin else {
            user = nil
            stat = nil
            return
        }

        do {
            async let userInfo = BiliAPI.shared.fetchMyInfo()
            async let userStat = BiliAPI.shared.fetchMyStat()

            let loadedUser = try await userInfo
            let loadedStat = try await userStat
            guard !Task.isCancelled, accountID == LoginSession.shared.selectedID(for: .main) else { return }
            user = loadedUser
            stat = loadedStat
        } catch {
            ErrorLogService.record(error, context: "加载我的资料")
            print(error)
        }
    }
}

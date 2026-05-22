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

    func loadUser() async {
        guard LoginSession.shared.isLogin else {
            user = nil
            return
        }

        do {
            user = try await BiliAPI.shared.fetchMyInfo()
        } catch {
            print(error)
        }
    }
}

//
//  LoginViewModel.swift
//  PiliPod
//
//  Created by co on 2026/5/27.
//

import Foundation
import Combine

@MainActor
final class LoginViewModel: ObservableObject {
    let authService = BiliAuthService()

    @Published var username = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    func executeLoginFlow() async {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "请输入账号和密码"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let status = await authService.login(account: username, password: password)
        await handleLoginStatus(status)
    }

    func handleLoginStatus(_ status: BiliLoginStatus) async {
        switch status {
        case .success(let data):
            print("登录成功！拿到了数据：")
            print("AccessKey: \(data["access_token"] as? String ?? "")")
            print("Refresh: \(data["refresh_token"] as? String ?? "")")
            if let tokenInfo = data["token_info"] as? [String: Any] {
                print("TokenInfo: \(tokenInfo)")
            }
            if let cookieInfo = data["cookie_info"] as? [String: Any] {
                print("CookieInfo: \(cookieInfo)")
            }
            print("RawData: \(data)")

        case .needGeetest(let captchaKey, let gt, let challenge):
            print("触发人机验证风控！")
            print("captchaKey: \(captchaKey)")
            print("gt: \(gt)")
            print("challenge: \(challenge)")

        case .failed(let code, let message):
            let messageText = "[\(code)] \(message)"
            errorMessage = messageText
            print("登录失败：\(messageText)")
        }
    }
}

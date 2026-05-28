//
//  LoginViewModel.swift
//  PiliPod
//
//  Created by co on 2026/5/27.
//

import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    let authService = BiliAuthService()

    @Published var username = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var geetestContext: GeetestContext?
    @Published var phoneVerifyContext: PhoneVerifyContext?
    @Published var loginSucceeded = false
    @Published var phoneVerifyMessage: String?

    struct GeetestContext: Identifiable {
        let id = UUID()
        let recaptchaToken: String
        let gt: String
        let challenge: String
    }

    struct PhoneVerifyContext: Identifiable {
        let id = UUID()
        let tmpCode: String
        let requestId: String
        let source: String
        let refererURL: String
        let maskedTel: String
        var captchaKey: String?
    }

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
            let saved = authService.persistLogin(data: data)
            if saved {
                loginSucceeded = true
                print("登录成功并已保存登录状态")
            } else {
                errorMessage = "登录成功，但解析登录凭证失败"
                print("登录成功但保存失败：\(data)")
            }

        case .needGeetest(let recaptchaToken, let gt, let challenge):
            print("触发人机验证风控！")
            print("recaptchaToken: \(recaptchaToken)")
            print("gt: \(gt)")
            print("challenge: \(challenge)")
            geetestContext = GeetestContext(
                recaptchaToken: recaptchaToken,
                gt: gt,
                challenge: challenge
            )

        case .needPhoneVerify(let context):
            phoneVerifyContext = PhoneVerifyContext(
                tmpCode: context.tmpCode,
                requestId: context.requestId,
                source: context.source,
                refererURL: context.refererURL,
                maskedTel: context.maskedTel
            )
            phoneVerifyMessage = nil

        case .failed(let code, let message):
            let messageText = "[\(code)] \(message)"
            errorMessage = messageText
            print("登录失败：\(messageText)")
        }
    }

    func submitGeetestResult(
        _ result: GeetestValidateResult,
        recaptchaToken: String
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let status = await authService.login(
            account: username,
            password: password,
            geetestParams: (
                validate: result.validate,
                challenge: result.challenge,
                seccode: result.seccode
            ),
            recaptchaToken: recaptchaToken
        )
        geetestContext = nil
        await handleLoginStatus(status)
    }

    func sendPhoneVerifySMS() async {
        guard let context = phoneVerifyContext else { return }
        isLoading = true
        phoneVerifyMessage = nil
        defer { isLoading = false }

        let preCaptureRes = await authService.preCapture()
        switch preCaptureRes {
        case .failure(let error):
            phoneVerifyMessage = "获取极验参数失败：\(error.localizedDescription)"
        case .success(let pre):
            geetestContext = GeetestContext(
                recaptchaToken: pre.recaptchaToken,
                gt: pre.gt,
                challenge: pre.challenge
            )
            phoneVerifyMessage = "请先完成人机验证后发送短信"

            // 记录短信发送所需上下文
            pendingSmsContext = (
                tmpCode: context.tmpCode,
                refererURL: context.refererURL,
                recaptchaToken: pre.recaptchaToken
            )
        }
    }

    func submitPhoneVerifyGeetest(_ result: GeetestValidateResult) async {
        guard let pending = pendingSmsContext else { return }
        isLoading = true
        defer { isLoading = false }

        let sendRes = await authService.safeCenterSmsCode(
            tmpCode: pending.tmpCode,
            geeChallenge: result.challenge,
            geeSeccode: result.seccode,
            geeValidate: result.validate,
            recaptchaToken: pending.recaptchaToken,
            refererURL: pending.refererURL
        )

        switch sendRes {
        case .success(let captchaKey):
            phoneVerifyMessage = "短信验证码已发送，请查收"
            if var context = phoneVerifyContext {
                context.captchaKey = captchaKey
                phoneVerifyContext = context
            }
        case .failure(let error):
            phoneVerifyMessage = "发送短信验证码失败：\(error.localizedDescription)"
        }
    }

    func submitPhoneVerifyCode(_ code: String) async {
        guard let context = phoneVerifyContext else { return }
        guard !code.isEmpty else {
            phoneVerifyMessage = "请输入短信验证码"
            return
        }
        guard let captchaKey = context.captchaKey, !captchaKey.isEmpty else {
            phoneVerifyMessage = "请先发送短信验证码"
            return
        }

        isLoading = true
        phoneVerifyMessage = nil
        defer { isLoading = false }

        let verifyRes = await authService.safeCenterSmsVerify(
            code: code,
            tmpCode: context.tmpCode,
            requestId: context.requestId,
            source: context.source,
            captchaKey: captchaKey,
            refererURL: context.refererURL
        )

        switch verifyRes {
        case .failure(let error):
            phoneVerifyMessage = "验证短信失败：\(error.localizedDescription)"
        case .success(let oauthCode):
            let status = await authService.oauth2AccessToken(code: oauthCode)
            await handleLoginStatus(status)
            if loginSucceeded {
                phoneVerifyContext = nil
            }
        }
    }

    // 仅用于手机号风控流程中“先极验再发短信”的中间态
    private var pendingSmsContext: (tmpCode: String, refererURL: String, recaptchaToken: String)?
}

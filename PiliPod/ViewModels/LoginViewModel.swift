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
    let authService: BiliAuthService
    init(authService: BiliAuthService = BiliAuthService()) { self.authService = authService }

    enum Method: String, CaseIterable { case password = "密码", sms = "短信", qr = "扫码", cookie = "Cookie" }
    @Published var method = Method.password
    @Published var phone = ""
    @Published var country = BiliLoginCountry.china
    @Published var countries = [BiliLoginCountry.china]
    @Published var smsCode = ""
    @Published var cookieText = ""
    @Published var qrURL: String?
    @Published var qrMessage = ""
    @Published var smsMessage = ""
    @Published var resendAt = Date.distantPast
    private var smsCredential: (phone: String, country: Int, key: String)?
    private var smsCaptchaTarget: (phone: String, country: Int)?

    func loadCountries() async {
        if let loaded = try? await authService.countries(), !loaded.isEmpty { countries = loaded }
    }

    func runQRCode() async {
        qrURL = nil
        qrMessage = "正在获取二维码…"
        errorMessage = nil
        do {
            let qr = try await authService.generateQRCode()
            try Task.checkCancellation()
            qrURL = qr.url
            qrMessage = "请使用哔哩哔哩客户端扫码并确认登录"
            let deadline = Date().addingTimeInterval(TimeInterval(qr.expiresIn))
            while Date() < deadline {
                try await Task.sleep(for: .seconds(2))
                let status = try await authService.pollQRCode(qr.authCode)
                try Task.checkCancellation()
                switch status {
                case .waiting(let message): qrMessage = message
                case .expired: qrURL = nil; qrMessage = "二维码已过期，请刷新"; return
                case .login(let result): await handleLoginStatus(result); qrURL = nil; return
                }
            }
            qrURL = nil
            qrMessage = "二维码已过期，请刷新"
        } catch {
            guard !Task.isCancelled else { return }
            qrURL = nil
            qrMessage = "获取二维码或查询状态失败，请刷新重试"
        }
    }

    func sendLoginSMS(captcha: (GeetestValidateResult, String)? = nil) async {
        guard !isLoading, Date() >= resendAt else { return }
        let number = phone.trimmingCharacters(in: .whitespaces)
        guard (5...20).contains(number.count), number.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            errorMessage = "请输入有效手机号"; return
        }
        let selectedCountry = country.callingCode
        if captcha != nil, smsCaptchaTarget?.phone != number || smsCaptchaTarget?.country != selectedCountry {
            errorMessage = "手机号或地区已变更，请重新获取验证码"; return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let status = try await authService.sendLoginSMS(phone: number, countryID: selectedCountry,
                captcha: captcha.map { (result: $0.0, token: $0.1) })
            guard !Task.isCancelled, phone.trimmingCharacters(in: .whitespaces) == number, country.callingCode == selectedCountry else { return }
            switch status {
            case .sent(let key):
                smsCredential = (number, selectedCountry, key)
                smsCaptchaTarget = nil
                resendAt = Date().addingTimeInterval(60)
                smsMessage = "验证码已发送"
            case .captcha(let challenge):
                smsCaptchaTarget = (number, selectedCountry)
                geetestContext = GeetestContext(recaptchaToken: challenge.recaptchaToken,
                    gt: challenge.gt, challenge: challenge.challenge)
            case .failed(let message): errorMessage = message
            }
        } catch { errorMessage = "发送验证码失败，请重试" }
    }

    func submitSMSCaptcha(_ result: GeetestValidateResult, token: String) async {
        geetestContext = nil
        await sendLoginSMS(captcha: (result, token))
    }

    func submitSelectedMethod() async {
        guard !isLoading else { return }
        switch method {
        case .password: await executeLoginFlow()
        case .qr: break
        case .sms:
            guard let credential = smsCredential,
                  credential.phone == phone.trimmingCharacters(in: .whitespaces), credential.country == country.callingCode,
                  !smsCode.isEmpty, smsCode.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                errorMessage = "请先为此手机号获取验证码并填写验证码"; return
            }
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            await handleLoginStatus(authService.loginBySMS(phone: credential.phone, countryID: credential.country,
                code: smsCode, captchaKey: credential.key))
        case .cookie:
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            do {
                let account = try await authService.validateCookie(cookieText.trimmingCharacters(in: .whitespacesAndNewlines))
                try Task.checkCancellation()
                try LoginSession.shared.add([account])
                loginSucceeded = true
            } catch { errorMessage = "Cookie 无效、已过期或无法保存到安全存储" }
        }
    }

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
        guard !Task.isCancelled else { return }
        switch status {
        case .success(let data):
            let saved = authService.persistLogin(data: data)
            if saved {
                loginSucceeded = true
                print("登录成功并已保存登录状态")
            } else {
                errorMessage = "登录成功，但登录凭据无效或无法保存到安全存储"
                print("登录成功但凭据解析或安全存储失败")
            }

        case .needGeetest(let recaptchaToken, let gt, let challenge):
            print("触发人机验证风控！")
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

import Foundation
import Security
import Testing
@testable import PiliPod

private final class LoginMockProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, [String: Any]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (status, payload) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct LoginMethodTests {
    private func service(_ handler: @escaping (URLRequest) throws -> (Int, [String: Any])) -> BiliAuthService {
        LoginMockProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginMockProtocol.self]
        configuration.httpShouldSetCookies = false
        return BiliAuthService(session: URLSession(configuration: configuration))
    }
    private func form(_ request: URLRequest) -> [String: String] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return Dictionary(uniqueKeysWithValues: raw.split(separator: "&").map { part in
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(pair[0]), pair.count > 1 ? String(pair[1]).removingPercentEncoding ?? "" : "")
        })
    }

    @Test func qrCodeUsesSignedAnonymousTVRequest() async throws {
        let auth = service { request in
            #expect(request.httpMethod == "POST")
            #expect(!request.httpShouldHandleCookies)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(items.contains { $0.name == "local_id" && $0.value == "0" })
            #expect(items.contains { $0.name == "sign" && $0.value?.count == 32 })
            return (200, ["code": 0, "data": ["url": "https://passport.bilibili.com/test", "auth_code": "fake-code", "expires_in": 90]])
        }
        let qr = try await auth.generateQRCode()
        #expect(qr.authCode == "fake-code")
        #expect(qr.expiresIn == 90)
    }
    @Test func qrWaitingExpiryAndSuccessAreDistinct() async throws {
        for code in [86039, 86090, 86038, 0] {
            let auth = service { _ in (200, ["code": code, "message": "waiting", "data": [:]]) }
            let status = try await auth.pollQRCode("fake-code")
            switch (code, status) {
            case (86039, .waiting), (86090, .waiting), (86038, .expired), (0, .login(.success)): break
            default: Issue.record("Incorrect QR status")
            }
        }
    }
    @Test func unexpectedQRResponseIsAnError() async throws {
        let auth = service { _ in (503, ["code": 0]) }
        do { _ = try await auth.pollQRCode("fake"); Issue.record("Expected HTTP failure") } catch {}
    }
    @Test func smsUsesDialCodeAndCaptchaFields() async throws {
        let auth = service { request in
            let params = form(request)
            #expect(params["cid"] == "86")
            #expect(params["tel"] == "13800000000")
            #expect(params["gee_validate"] == "fake-validate")
            #expect(params["recaptcha_token"] == "fake-token")
            #expect(params["login_session_id"]?.count == 32)
            #expect(params["sign"]?.count == 32)
            #expect(!request.httpShouldHandleCookies)
            return (200, ["code": 0, "data": ["recaptcha_url": "", "captcha_key": "fake-key"]])
        }
        let result = GeetestValidateResult(validate: "fake-validate", challenge: "fake-challenge", seccode: "fake-seccode")
        let status = try await auth.sendLoginSMS(phone: "13800000000", countryID: 86, captcha: (result, "fake-token"))
        guard case .sent(let key) = status else { Issue.record("Expected SMS success"); return }
        #expect(key == "fake-key")
    }
    @Test func smsChallengeDoesNotCountAsSent() async throws {
        let auth = service { _ in (200, ["code": -105, "data": ["recaptcha_url":
            "https://passport.bilibili.com/captcha?gee_gt=gt&gee_challenge=challenge&recaptcha_token=token"]]) }
        let result = try await auth.sendLoginSMS(phone: "13800000000", countryID: 86)
        guard case .captcha(let captcha) = result else { Issue.record("Expected captcha"); return }
        #expect(captcha.gt == "gt")
        #expect(captcha.recaptchaToken == "token")
    }
    @Test func countryIDsAreNotDialCodes() async throws {
        let auth = service { _ in (200, ["code": 0, "data": ["common": [
            ["id": 1, "cname": "中国大陆", "country_id": "86"],
            ["id": 5, "cname": "中国香港特别行政区", "country_id": "852"]], "others": []]]) }
        let countries = try await auth.countries()
        #expect(countries[0].id == 1)
        #expect(countries[0].callingCode == 86)
        #expect(countries[1].callingCode == 852)
    }
    @Test func smsLoginSendsEncryptedDeviceAndReturnsTokens() async throws {
        let privateKey = try #require(SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let bytes = try #require(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
        let pem = "-----BEGIN PUBLIC KEY-----\n" + bytes.base64EncodedString() + "\n-----END PUBLIC KEY-----"
        let auth = service { request in
            if request.url?.path == "/api/oauth2/getKey" {
                return (200, ["code": 0, "data": ["hash": "fake-hash", "key": pem]])
            }
            #expect(request.url?.path == "/x/passport-login/login/sms")
            let params = form(request)
            #expect(params["cid"] == "852")
            #expect(params["captcha_key"] == "fake-key")
            #expect(params["code"] == "123456")
            #expect(params["dt"]?.isEmpty == false)
            return (200, ["code": 0, "data": ["token_info": ["access_token": "fake-token", "refresh_token": "fake-refresh"]]])
        }
        let status = await auth.loginBySMS(phone: "12345678", countryID: 852, code: "123456", captchaKey: "fake-key")
        guard case .success(let data) = status else { Issue.record("Expected SMS login success"); return }
        #expect((data["token_info"] as? [String: String])?["access_token"] == "fake-token")
    }
    @Test func cookieParsingPreservesEqualsAndAdditionalCookies() throws {
        let account = try BiliAuthService.parseCookie("SESSDATA=fake==; bili_jct=csrf; DedeUserID=123; DedeUserID__ckMd5=checksum")
        #expect(account.cookies.SESSDATA == "fake==")
        #expect(account.cookies.dictionary["DedeUserID__ckMd5"] == "checksum")
        #expect(account.accessKey == nil)
        #expect(throws: AccountStorageError.self) { try BiliAuthService.parseCookie("SESSDATA=a; SESSDATA=b; bili_jct=c; DedeUserID=123") }
        #expect(throws: AccountStorageError.self) { try BiliAuthService.parseCookie("SESSDATA=a\r\nInjected=x; bili_jct=c; DedeUserID=123") }
    }
    @Test func cookieValidationRejectsMismatchedUID() async throws {
        let auth = service { request in
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("DedeUserID=123") == true)
            #expect(!request.httpShouldHandleCookies)
            return (200, ["code": 0, "data": ["isLogin": true, "mid": 456]])
        }
        do { _ = try await auth.validateCookie("SESSDATA=fake; bili_jct=csrf; DedeUserID=123"); Issue.record("Expected UID mismatch") } catch {}
    }
    @Test func cookieValidationAcceptsMatchingUID() async throws {
        let auth = service { _ in (200, ["code": 0, "data": ["isLogin": true, "mid": 123, "uname": "测试用户"]]) }
        let account = try await auth.validateCookie("SESSDATA=fake; bili_jct=csrf; DedeUserID=123")
        #expect(account.id == "123")
        #expect(account.displayName == "测试用户（123）")
    }
    @Test func compatibleJSONPreservesCredentialsAndEmptyAssignments() throws {
        let cookies = ["SESSDATA": "fake-session", "bili_jct": "fake-csrf", "DedeUserID": "123",
                       "DedeUserID__ckMd5": "fake-checksum", "sid": "fake-sid", "buvid3": "fake-buvid"]
        let fixture: [String: Any] = ["123": ["cookies": cookies, "accessKey": "fake-access", "refresh": "fake-refresh", "type": []]]
        let accounts = try LoginImportService.decode(JSONSerialization.data(withJSONObject: fixture))
        var state = AccountState()
        state.accounts = accounts
        let roundtrip = try LoginImportService.decode(LoginImportService.encode(state))
        #expect(roundtrip[0].cookies.dictionary == cookies)
        #expect(roundtrip[0].accessKey == "fake-access")
        #expect(roundtrip[0].refresh == "fake-refresh")
        #expect(roundtrip[0].type == [])
        #expect(state.account(for: .main) == nil)
        state.assignments[.playback] = "123"
        #expect(try LoginImportService.decode(LoginImportService.encode(state))[0].type == [3])
    }
    @Test func oldStoredCookiesRemainDecodable() throws {
        let old = Data("{\"SESSDATA\":\"fake\",\"bili_jct\":\"csrf\",\"DedeUserID\":\"123\"}".utf8)
        let cookies = try JSONDecoder().decode(BiliCookie.self, from: old)
        #expect(cookies.extraCookies == nil)
        #expect(cookies.DedeUserID == "123")
    }
    @Test func cookieOnlyAccountExportsNullTokensAndAssignedRoles() throws {
        let account = try BiliAuthService.parseCookie("SESSDATA=fake; bili_jct=csrf; DedeUserID=123")
        var state = AccountState()
        state.add(account, activate: true)
        let data = try LoginImportService.encode(state)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        #expect(json["123"]?["accessKey"] is NSNull)
        #expect(json["123"]?["refresh"] is NSNull)
        let restored = try LoginImportService.decode(data)
        #expect(restored[0].accessKey == nil)
        #expect(restored[0].type == [0, 1, 2, 3])
    }
    @Test func smsCredentialCannotBeUsedForAnotherPhone() async throws {
        let auth = service { _ in (200, ["code": 0, "data": ["recaptcha_url": "", "captcha_key": "fake"]]) }
        let model = LoginViewModel(authService: auth)
        model.method = .sms
        model.phone = "13800000000"
        await model.sendLoginSMS()
        #expect(model.resendAt > Date())
        model.phone = "13900000000"
        model.smsCode = "123456"
        await model.submitSelectedMethod()
        #expect(model.errorMessage != nil)
        #expect(!model.loginSucceeded)
    }
}

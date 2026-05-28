import CryptoKit
import Foundation
import Security

// MARK: - 1. 严格的 RFC3986 编码器

extension String {
    func biliUrlEncoded() -> String {
        let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        let allowed = CharacterSet(charactersIn: unreserved)
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

// MARK: - 2. 状态模型 (支持风控验证码反馈)

public enum BiliLoginStatus {
    case success(data: [String: Any])
    /// 如果返回此状态，拉起 WebView 供用户验证，验证后将 geetest 的返回值重新传入 login 函数
    case needGeetest(recaptchaToken: String, gt: String, challenge: String)
    case needPhoneVerify(context: BiliPhoneVerifyContext)
    case failed(code: Int, message: String)
}

public struct BiliPhoneVerifyContext {
    let tmpCode: String
    let requestId: String
    let source: String
    let refererURL: String
    let maskedTel: String
}

public struct BiliPreCaptchaData {
    let recaptchaToken: String
    let gt: String
    let challenge: String
}

// MARK: - 3. 本地设备特征管理器 (确保全局唯一，防风控)

public class BiliDeviceConfig {
    public static let shared = BiliDeviceConfig()

    // 初始化时从UserDefaults读取，如果没有则生成并保存
    public lazy var deviceId: String = {
        if let saved = UserDefaults.standard.string(forKey: "bili_device_id") { return saved }
        let newId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(newId, forKey: "bili_device_id")
        return newId
    }()

    public lazy var buvid: String = {
        if let saved = UserDefaults.standard.string(forKey: "bili_buvid") { return saved }
        let digest = Insecure.MD5.hash(data: UUID().uuidString.data(using: .utf8) ?? Data())
        let md5Str = digest.map { String(format: "%02X", $0) }.joined()
        let newBuvid = "XY" + md5Str
        UserDefaults.standard.set(newBuvid, forKey: "bili_buvid")
        return newBuvid
    }()

    // 固定伪装参数
    public let build = "2001100"
    public let mobiApp = "android_hd"
    public let platform = "android"
    public let device = "phone"
    public let deviceName = "Phone"
    public let devicePlatform = "Android14vivo"
    public let statistics = "{\"appId\":1,\"platform\":3,\"version\":\"7.30.0\",\"abtest\":\"\"}"
    public let userAgent = "Mozilla/5.0 BiliDroid/7.30.0 (bbcallen@gmail.com) os/android model/vivo mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/14 network/2"
}

// MARK: - 4. 核心登录服务

public class BiliAuthService {
    private let appKey = "dfca71928277209b"
    private let appSecret = "b5475a8825547a4fc26c7d518eaaa02e"
    private let config = BiliDeviceConfig.shared

    public init() {}

    @discardableResult
    public func persistLogin(data: [String: Any]) -> Bool {
        let accessToken = (data["access_token"] as? String)
            ?? ((data["token_info"] as? [String: Any])?["access_token"] as? String)
        let refreshToken = (data["refresh_token"] as? String)
            ?? ((data["token_info"] as? [String: Any])?["refresh_token"] as? String)

        var cookieDict: [String: String] = [:]
        if let cookieInfo = data["cookie_info"] as? [String: Any],
           let cookieArray = cookieInfo["cookies"] as? [[String: Any]]
        {
            for item in cookieArray {
                if let name = item["name"] as? String, let value = item["value"] as? String {
                    cookieDict[name] = value
                }
            }
        }

        guard
            let sessdata = cookieDict["SESSDATA"],
            let biliJct = cookieDict["bili_jct"],
            let dedeUserID = cookieDict["DedeUserID"]
        else {
            return false
        }

        let cookie = BiliCookie(
            SESSDATA: sessdata,
            bili_jct: biliJct,
            DedeUserID: dedeUserID,
            sid: cookieDict["sid"],
            buvid3: cookieDict["buvid3"] ?? BiliDeviceConfig.shared.buvid
        )

        LoginSession.shared.cookies = cookie
        LoginSession.shared.accessKey = accessToken
        LoginSession.shared.refresh = refreshToken
        LoginSession.shared.type = nil
        LoginSession.shared.isLogin = true
        LoginImportService.saveToLocal(cookie)
        return true
    }

    /// 仅密码登录（参考 loginByPwd）
    public func login(
        account: String,
        password: String,
        geetestParams: (validate: String, challenge: String, seccode: String)? = nil,
        recaptchaToken: String? = nil
    ) async -> BiliLoginStatus {
        do {
            // 1. 获取登录加密公钥与 hash 盐
            let keyInfo = try await fetchOAuth2Key()

            // 2. 加密密码 (hash + password)
            let encryptedPassword = try rsaEncrypt(payload: keyInfo.hash + password, publicKeyPEM: keyInfo.key)

            // 3. 动态生成 dt 并加密（与 loginByPwd 一致：字段内预编码）
            let dtRaw = generateRandomString(length: 16)
            let dtEncrypted = try rsaEncrypt(payload: dtRaw, publicKeyPEM: keyInfo.key).biliUrlEncoded()

            // 4. 组装参数（按 loginByPwd 对齐）
            var params: [String: String] = [
                "appkey": appKey,
                "username": account,
                "password": encryptedPassword,
                "bili_local_id": config.deviceId,
                "device_id": config.deviceId,
                "buvid": config.buvid,
                "local_id": config.buvid,
                "build": config.build,
                "c_locale": "zh_CN",
                "s_locale": "zh_CN",
                "channel": "master",
                "device": config.device,
                "device_name": config.deviceName,
                "device_platform": config.devicePlatform,
                "disable_rcmd": "0",
                "dt": dtEncrypted,
                "from_pv": "main.homepage.avatar-nologin.all.click",
                "from_url": "bilibili://pegasus/promo".biliUrlEncoded(),
                "mobi_app": config.mobiApp,
                "permission": "ALL",
                "platform": config.platform,
                "statistics": config.statistics,
                "ts": String(Int(Date().timeIntervalSince1970))
            ]

            // 5. 如果触发了风控，回填验证码凭证
            if let geetest = geetestParams {
                params["gee_challenge"] = geetest.challenge
                params["gee_seccode"] = geetest.seccode
                params["gee_validate"] = geetest.validate
            }
            if let rToken = recaptchaToken {
                params["recaptcha_token"] = rToken
            }

            // 6. 生成签名 (Sign)
            params["sign"] = generateSign(for: params)

            // 7. 发起网络请求
            let loginUrl = URL(string: "https://passport.bilibili.com/x/passport-login/oauth2/login")!
            var request = URLRequest(url: loginUrl)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(config.buvid, forHTTPHeaderField: "buvid")
            request.setValue("prod", forHTTPHeaderField: "env")
            request.setValue("android_hd", forHTTPHeaderField: "app-key")
            request.setValue(makeTraceId(), forHTTPHeaderField: "x-bili-trace-id")
            request.setValue("", forHTTPHeaderField: "x-bili-aurora-eid")
            request.setValue("", forHTTPHeaderField: "x-bili-aurora-zone")
            request.setValue("cronet", forHTTPHeaderField: "bili-http-engine")
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "content-type")
            request.setValue("https://www.bilibili.com", forHTTPHeaderField: "referer")

            let bodyString = makeOrderedBodyString(from: params)
            request.httpBody = bodyString.data(using: .utf8)

            let (data, _) = try await URLSession.shared.data(for: request)

            // 8. 处理返回结果
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failed(code: -999, message: "数据解析失败")
            }

            let code = json["code"] as? Int ?? -999
            let message = json["message"] as? String ?? "未知错误"
            let payload = json["data"] as? [String: Any]
            let status = payload?["status"] as? Int

            if code == 0, status == 2, let payload {
                return await makeNeedPhoneVerifyStatus(
                    payload: payload,
                    fallbackMessage: message
                )
            } else if code == 0 {
                // 登录成功，Token 都在 json["data"] 里
                return .success(data: json["data"] as? [String: Any] ?? [:])
            } else if code == -105 {
                // 风控拦截：从 data.url 解析验证参数
                if let resData = json["data"] as? [String: Any],
                   let rawURL = resData["url"] as? String,
                   let verifyURL = URL(string: rawURL),
                   let components = URLComponents(url: verifyURL, resolvingAgainstBaseURL: false),
                   let items = components.queryItems
                {
                    let recaptcha = items.first(where: { $0.name == "recaptcha_token" })?.value ?? ""
                    let gt = items.first(where: { $0.name == "gee_gt" })?.value ?? ""
                    let challenge = items.first(where: { $0.name == "gee_challenge" })?.value ?? ""
                    if !recaptcha.isEmpty, !gt.isEmpty, !challenge.isEmpty {
                        return .needGeetest(recaptchaToken: recaptcha, gt: gt, challenge: challenge)
                    }
                }
                return .failed(code: code, message: "解析 data.url 中验证码参数失败")
            } else {
                return .failed(code: code, message: message)
            }

        } catch {
            return .failed(code: -997, message: error.localizedDescription)
        }
    }

    // MARK: - 辅助方法

    private func fetchOAuth2Key() async throws -> (hash: String, key: String) {
        let url = URL(string: "https://passport.bilibili.com/api/oauth2/getKey")!
        var params: [String: String] = [
            "appkey": appKey,
            "ts": String(Int(Date().timeIntervalSince1970))
        ]
        params["sign"] = generateSign(for: params)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeOrderedBodyString(from: params).data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? Int, code == 0,
              let resData = json["data"] as? [String: Any],
              let hash = resData["hash"] as? String,
              let key = resData["key"] as? String
        else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "获取公钥失败"])
        }
        return (hash, key)
    }

    private func generateSign(for parameters: [String: String]) -> String {
        var validParams = parameters
        validParams.removeValue(forKey: "sign")
        let sortedKeys = validParams.keys.sorted()
        // key / value 都走 RFC3986 编码，签名串按字典序拼接
        let paramString = sortedKeys.map { key in
            let value = validParams[key] ?? ""
            let encodedKey = key.biliUrlEncoded()
            let encodedValue = value.biliUrlEncoded()
            return encodedValue.isEmpty ? encodedKey : "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: (paramString + appSecret).data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // 请求体顺序：其他 key 按字典序，最后固定 appkey、ts、sign
    private func makeOrderedBodyString(from parameters: [String: String]) -> String {
        let tailKeys = ["appkey", "ts", "sign"]
        let sortedOtherKeys = parameters.keys
            .filter { !tailKeys.contains($0) }
            .sorted()

        let orderedKeys = sortedOtherKeys + tailKeys.filter { parameters[$0] != nil }

        return orderedKeys.map { key in
            let value = parameters[key] ?? ""
            let encodedKey = key.biliUrlEncoded()
            let encodedValue = value.biliUrlEncoded()
            return encodedValue.isEmpty ? encodedKey : "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    private func generateRandomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0 ..< length).map { _ in letters.randomElement()! })
    }

    private func rsaEncrypt(payload: String, publicKeyPEM: String) throws -> String {
        guard let dataToEncrypt = payload.data(using: .utf8) else { throw NSError(domain: "RSA", code: -1) }
        let keyString = publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")

        guard let keyData = Data(base64Encoded: keyString) else { throw NSError(domain: "RSA", code: -2) }
        let options: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, options as CFDictionary, &error) else { throw NSError(domain: "RSA", code: -3) }
        guard let encryptedData = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, dataToEncrypt as CFData, &error) as Data? else { throw NSError(domain: "RSA", code: -4) }
        return encryptedData.base64EncodedString()
    }

    private func makeTraceId() -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let seed = config.buvid + timestamp
        let digest = Insecure.MD5.hash(data: Data(seed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex):\(hex):0:0"
    }

    public func preCapture() async -> Result<BiliPreCaptchaData, Error> {
        let url = URL(string: "https://passport.bilibili.com/x/safecenter/captcha/pre")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(config.buvid, forHTTPHeaderField: "buvid")
        request.setValue("prod", forHTTPHeaderField: "env")
        request.setValue("android_hd", forHTTPHeaderField: "app-key")
        request.setValue(makeTraceId(), forHTTPHeaderField: "x-bili-trace-id")
        request.setValue("cronet", forHTTPHeaderField: "bili-http-engine")

        var params: [String: String] = [
            "appkey": appKey,
            "ts": String(Int(Date().timeIntervalSince1970))
        ]
        params["sign"] = generateSign(for: params)
        request.httpBody = makeOrderedBodyString(from: params).data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(NSError(domain: "Auth", code: -2001, userInfo: [NSLocalizedDescriptionKey: "preCapture 解析失败"]))
            }
            let code = json["code"] as? Int ?? -2001
            guard code == 0,
                  let payload = json["data"] as? [String: Any],
                  let token = payload["recaptcha_token"] as? String,
                  let gt = payload["gee_gt"] as? String,
                  let challenge = payload["gee_challenge"] as? String
            else {
                let msg = json["message"] as? String ?? "preCapture 请求失败"
                return .failure(NSError(domain: "Auth", code: code, userInfo: [NSLocalizedDescriptionKey: msg]))
            }
            return .success(BiliPreCaptchaData(recaptchaToken: token, gt: gt, challenge: challenge))
        } catch {
            return .failure(error)
        }
    }

    public func safeCenterSmsCode(
        tmpCode: String,
        geeChallenge: String,
        geeSeccode: String,
        geeValidate: String,
        recaptchaToken: String,
        refererURL: String
    ) async -> Result<String, Error> {
        let url = URL(string: "https://passport.bilibili.com/x/safecenter/common/sms/send")!
        var params: [String: String] = [
            "disable_rcmd": "0",
            "sms_type": "loginTelCheck",
            "tmp_code": tmpCode,
            "gee_challenge": geeChallenge,
            "gee_seccode": geeSeccode,
            "gee_validate": geeValidate,
            "recaptcha_token": recaptchaToken,
            "appkey": appKey,
            "ts": String(Int(Date().timeIntervalSince1970))
        ]
        params["sign"] = generateSign(for: params)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(refererURL, forHTTPHeaderField: "Referer")
        request.httpBody = makeOrderedBodyString(from: params).data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(NSError(domain: "Auth", code: -2002, userInfo: [NSLocalizedDescriptionKey: "发送短信解析失败"]))
            }
            let code = json["code"] as? Int ?? -2002
            guard code == 0,
                  let payload = json["data"] as? [String: Any],
                  let captchaKey = payload["captcha_key"] as? String
            else {
                let msg = json["message"] as? String ?? "发送短信失败"
                return .failure(NSError(domain: "Auth", code: code, userInfo: [NSLocalizedDescriptionKey: msg]))
            }
            return .success(captchaKey)
        } catch {
            return .failure(error)
        }
    }

    public func safeCenterSmsVerify(
        code: String,
        tmpCode: String,
        requestId: String,
        source: String,
        captchaKey: String,
        refererURL: String
    ) async -> Result<String, Error> {
        let url = URL(string: "https://passport.bilibili.com/x/safecenter/login/tel/verify")!
        var params: [String: String] = [
            "type": "loginTelCheck",
            "code": code,
            "tmp_code": tmpCode,
            "request_id": requestId,
            "source": source,
            "captcha_key": captchaKey,
            "appkey": appKey,
            "ts": String(Int(Date().timeIntervalSince1970))
        ]
        params["sign"] = generateSign(for: params)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(refererURL, forHTTPHeaderField: "Referer")
        request.httpBody = makeOrderedBodyString(from: params).data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(NSError(domain: "Auth", code: -2003, userInfo: [NSLocalizedDescriptionKey: "短信验证解析失败"]))
            }
            let retCode = json["code"] as? Int ?? -2003
            guard retCode == 0,
                  let payload = json["data"] as? [String: Any],
                  let oauthCode = payload["code"] as? String
            else {
                let msg = json["message"] as? String ?? "短信验证失败"
                return .failure(NSError(domain: "Auth", code: retCode, userInfo: [NSLocalizedDescriptionKey: msg]))
            }
            return .success(oauthCode)
        } catch {
            return .failure(error)
        }
    }

    public func oauth2AccessToken(code: String) async -> BiliLoginStatus {
        let url = URL(string: "https://passport.bilibili.com/x/passport-login/oauth2/access_token")!
        var params: [String: String] = [
            "build": config.build,
            "buvid": config.buvid,
            "code": code,
            "disable_rcmd": "0",
            "grant_type": "authorization_code",
            "local_id": config.buvid,
            "mobi_app": config.mobiApp,
            "platform": config.platform,
            "appkey": appKey,
            "ts": String(Int(Date().timeIntervalSince1970))
        ]
        params["sign"] = generateSign(for: params)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(config.buvid, forHTTPHeaderField: "buvid")
        request.setValue("prod", forHTTPHeaderField: "env")
        request.setValue("android_hd", forHTTPHeaderField: "app-key")
        request.setValue(makeTraceId(), forHTTPHeaderField: "x-bili-trace-id")
        request.setValue("cronet", forHTTPHeaderField: "bili-http-engine")
        print(makeOrderedBodyString(from: params))
        request.httpBody = makeOrderedBodyString(from: params).data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failed(code: -2004, message: "access_token 解析失败")
            }
            print(String(data: data, encoding: .utf8))
            print(json)
            let retCode = json["code"] as? Int ?? -2004
            let msg = json["message"] as? String ?? "未知错误"
            if retCode == 0 {
                return .success(data: json["data"] as? [String: Any] ?? [:])
            }
            return .failed(code: retCode, message: msg)
        } catch {
            return .failed(code: -2005, message: error.localizedDescription)
        }
    }

    private func makeNeedPhoneVerifyStatus(
        payload: [String: Any],
        fallbackMessage: String
    ) async -> BiliLoginStatus {
        guard
            let urlString = payload["url"] as? String,
            let url = URL(string: urlString),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let tmpCode = components.queryItems?.first(where: { $0.name == "tmp_token" })?.value,
            let requestId = components.queryItems?.first(where: { $0.name == "request_id" })?.value,
            let source = components.queryItems?.first(where: { $0.name == "source" })?.value
        else {
            return .failed(code: -2006, message: "手机号验证参数解析失败")
        }

        let infoURL = URL(string: "https://passport.bilibili.com/x/safecenter/user/info?tmp_code=\(tmpCode.biliUrlEncoded())")!
        var request = URLRequest(url: infoURL)
        request.httpMethod = "GET"
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int, code == 0,
                  let info = json["data"] as? [String: Any],
                  let accountInfo = info["account_info"] as? [String: Any]
            else {
                return .failed(code: -2007, message: "获取安全验证信息失败")
            }

            let telVerify = accountInfo["tel_verify"] as? Bool ?? false
            guard telVerify else {
                return .failed(code: -2008, message: "当前账号未支持手机号验证，请尝试其它登录方式")
            }
            let maskedTel = accountInfo["hide_tel"] as? String ?? "未能获取手机号"
            return .needPhoneVerify(
                context: BiliPhoneVerifyContext(
                    tmpCode: tmpCode,
                    requestId: requestId,
                    source: source,
                    refererURL: urlString,
                    maskedTel: maskedTel
                )
            )
        } catch {
            return .failed(code: -2009, message: "\(fallbackMessage)：\(error.localizedDescription)")
        }
    }
}

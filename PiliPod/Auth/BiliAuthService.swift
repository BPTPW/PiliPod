import Foundation
import Security
import CryptoKit

// MARK: - 1. 严格的 RFC3986 编码器
extension String {
    func biliUrlEncoded() -> String {
        let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        let allowed = CharacterSet(charactersIn: unreserved)
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

// MARK: - 2. 状态模型 (支持风控验证码反馈)
public enum BiliLoginStatus {
    case success(data: [String: Any])
    /// 如果返回此状态，拉起 WebView 供用户验证，验证后将 geetest 的返回值重新传入 login 函数
    case needGeetest(captchaKey: String, gt: String, challenge: String)
    case failed(code: Int, message: String)
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
    public let deviceName = "vivo"
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
    
    /// 仅密码登录（参考 loginByPwd）
    public func login(
        account: String,
        password: String,
        captchaKey: String? = nil,
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
            if let captchaKey = captchaKey, let geetest = geetestParams {
                params["captcha_key"] = captchaKey
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
            
            if code == 0 {
                // 登录成功，Token 都在 json["data"] 里
                return .success(data: json["data"] as? [String: Any] ?? [:])
            } else if code == -105 {
                // 风控拦截：人机验证拦截
                if let resData = json["data"] as? [String: Any],
                   let captchaKey = resData["captcha_key"] as? String,
                   let geetest = resData["geetest"] as? [String: Any],
                   let gt = geetest["gt"] as? String,
                   let challenge = geetest["challenge"] as? String {
                    return .needGeetest(captchaKey: captchaKey, gt: gt, challenge: challenge)
                }
                return .failed(code: code, message: "解析极验参数失败")
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
              let key = resData["key"] as? String else {
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
        return String((0..<length).map { _ in letters.randomElement()! })
    }
    
    private func rsaEncrypt(payload: String, publicKeyPEM: String) throws -> String {
        guard let dataToEncrypt = payload.data(using: .utf8) else { throw NSError(domain: "RSA", code: -1) }
        let keyString = publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
        
        guard let keyData = Data(base64Encoded: keyString) else { throw NSError(domain: "RSA", code: -2) }
        let options: [String: Any] = [ kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic ]
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
}

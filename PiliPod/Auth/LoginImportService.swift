//
//  LoginImportService.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

enum LoginImportService {
    static func importFrom(url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard
            let firstUser = json?.values.first as? [String: Any],
            let cookies = firstUser["cookies"] as? [String: Any]
        else {
            throw NSError(domain: "Invalid JSON", code: -1)
        }

        let biliCookie = BiliCookie(
            SESSDATA: cookies["SESSDATA"] as? String ?? "",
            bili_jct: cookies["bili_jct"] as? String ?? "",
            DedeUserID: cookies["DedeUserID"] as? String ?? "",
            sid: cookies["sid"] as? String,
            buvid3: cookies["buvid3"] as? String
        )

        LoginSession.shared.cookies = biliCookie
        LoginSession.shared.accessKey = firstUser["accessKey"] as? String
        LoginSession.shared.refresh = firstUser["refresh"] as? String
        LoginSession.shared.type = firstUser["type"] as? [Int]
        LoginSession.shared.isLogin = true

        saveToLocal(biliCookie)
    }

    static func saveToLocal(_ cookie: BiliCookie) {
        let data = try? JSONEncoder().encode(cookie)
        UserDefaults.standard.set(data, forKey: "bili_cookie")
        UserDefaults.standard.set(LoginSession.shared.accessKey, forKey: "bili_accessKey")
        UserDefaults.standard.set(LoginSession.shared.refresh, forKey: "bili_refresh")
        UserDefaults.standard.set(LoginSession.shared.type, forKey: "bili_type")
    }

    static func restore() {
        guard
            let data = UserDefaults.standard.data(forKey: "bili_cookie"),
            let cookie = try? JSONDecoder().decode(BiliCookie.self, from: data)
        else {
            return
        }

        LoginSession.shared.cookies = cookie
        LoginSession.shared.accessKey = UserDefaults.standard.string(forKey: "bili_accessKey")
        LoginSession.shared.refresh = UserDefaults.standard.string(forKey: "bili_refresh")
        LoginSession.shared.type = UserDefaults.standard.array(forKey: "bili_type") as? [Int]
        LoginSession.shared.isLogin = true
    }

    static func clearLoginState() {
        LoginSession.shared.cookies = nil
        LoginSession.shared.accessKey = nil
        LoginSession.shared.refresh = nil
        LoginSession.shared.type = nil
        LoginSession.shared.isLogin = false

        UserDefaults.standard.removeObject(forKey: "bili_cookie")
        UserDefaults.standard.removeObject(forKey: "bili_accessKey")
        UserDefaults.standard.removeObject(forKey: "bili_refresh")
        UserDefaults.standard.removeObject(forKey: "bili_type")
    }
}

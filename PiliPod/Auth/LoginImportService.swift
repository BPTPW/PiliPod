//
//  LoginImportService.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//
 
import Foundation

final class LoginImportService {

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
        LoginSession.shared.isLogin = true

        saveToLocal(biliCookie)
    }

    static func saveToLocal(_ cookie: BiliCookie) {
        let data = try? JSONEncoder().encode(cookie)
        UserDefaults.standard.set(data, forKey: "bili_cookie")
    }

    static func restore() {
        guard
            let data = UserDefaults.standard.data(forKey: "bili_cookie"),
            let cookie = try? JSONDecoder().decode(BiliCookie.self, from: data)
        else {
            return
        }

        LoginSession.shared.cookies = cookie
        LoginSession.shared.isLogin = true
    }
}

//
//  LoginSession.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Combine
import Foundation

final class LoginSession: ObservableObject {
    static let shared = LoginSession()

    @Published var cookies: BiliCookie?
    @Published var isLogin = false

    private init() {}

    var cookieString: String {
        guard let c = cookies else { return "" }

        var items: [String] = [
            "SESSDATA=\(c.SESSDATA)",
            "bili_jct=\(c.bili_jct)",
            "DedeUserID=\(c.DedeUserID)"
        ]

        if let sid = c.sid {
            items.append("sid=\(sid)")
        }

        if let buvid3 = c.buvid3 {
            items.append("buvid3=\(buvid3)")
        }

        return items.joined(separator: "; ")
    }
}

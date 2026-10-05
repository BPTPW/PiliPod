//
//  BiliCookie.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import Foundation

struct BiliCookie: Codable {
    let SESSDATA: String
    let bili_jct: String
    let DedeUserID: String
    let sid: String?
    let buvid3: String?
    var extraCookies: [String: String]? = nil

    var dictionary: [String: String] {
        var result = extraCookies ?? [:]
        result["SESSDATA"] = SESSDATA
        result["bili_jct"] = bili_jct
        result["DedeUserID"] = DedeUserID
        result["sid"] = sid
        result["buvid3"] = buvid3
        return result
    }
}

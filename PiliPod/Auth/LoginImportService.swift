import Foundation

enum LoginImportService {
    static func decode(_ data: Data) throws -> [BiliAccount] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], !json.isEmpty else {
            throw AccountStorageError.invalidAccount
        }
        return try json.keys.sorted().map { key in
            guard let user = json[key] as? [String: Any], let cookie = user["cookies"] as? [String: Any],
                  let sessdata = cookie["SESSDATA"] as? String, !sessdata.isEmpty,
                  let csrf = cookie["bili_jct"] as? String, !csrf.isEmpty,
                  let uid = cookie["DedeUserID"] as? String, uid == key, UInt64(uid).map({ $0 > 0 }) == true
            else { throw AccountStorageError.invalidAccount }
            guard let cookieStrings = cookie as? [String: String],
                  cookieStrings.allSatisfy({ !$0.key.contains(";") && !$0.value.contains(";") && !$0.value.contains("\r") && !$0.value.contains("\n") })
            else { throw AccountStorageError.invalidAccount }
            if let rawTypes = user["type"], !(rawTypes is NSNull) {
                guard let types = rawTypes as? [Int], types.allSatisfy({ (0...3).contains($0) }) else {
                    throw AccountStorageError.invalidAccount
                }
            }
            return BiliAccount(cookies: BiliCookie(SESSDATA: sessdata, bili_jct: csrf, DedeUserID: uid,
                sid: cookie["sid"] as? String, buvid3: cookie["buvid3"] as? String, extraCookies: cookieStrings),
                accessKey: user["accessKey"] as? String, refresh: user["refresh"] as? String, type: user["type"] as? [Int])
        }
    }
    static func encode(_ state: AccountState) throws -> Data {
        var payload: [String: Any] = [:]
        for account in state.accounts {
            let roles = AccountRole.allCases.enumerated().compactMap { index, role in
                state.assignments[role] == account.id ? index : nil
            }
            payload[account.id] = ["cookies": account.cookies.dictionary,
                "accessKey": account.accessKey.map { $0 as Any } ?? NSNull(),
                "refresh": account.refresh.map { $0 as Any } ?? NSNull(), "type": roles]
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
    @MainActor
    static func importFrom(url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        try LoginSession.shared.add(decode(Data(contentsOf: url)))
    }
    @MainActor
    static func restore() { LoginSession.shared.restore() }
    @MainActor
    static func clearLoginState() throws {
        let id = LoginSession.shared.selectedID(for: .main)
        if id != "0" { try LoginSession.shared.remove(id) }
    }
}

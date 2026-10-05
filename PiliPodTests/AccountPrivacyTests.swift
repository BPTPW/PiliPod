import Foundation
import Testing
@testable import PiliPod

private final class MemoryAccountVault: AccountVault {
    var data: Data?
    var failSave = false
    var failLoad = false
    func load() throws -> Data? {
        if failLoad { throw AccountStorageError.keychain(-1) }
        return data
    }
    func save(_ data: Data) throws {
        if failSave { throw AccountStorageError.keychain(-1) }
        self.data = data
    }
}

@MainActor
struct AccountPrivacyTests {
    @Test func usernamesPersistWithoutChangingAssignmentsOrCredentials() throws {
        let vault = MemoryAccountVault()
        let session = LoginSession(vault: vault)
        let original = account("1")
        try session.add([original, account("2")])
        let assignments = session.snapshot.assignments
        try session.updateUsername(" 用户名 ", for: original)
        let restored = LoginSession(vault: vault)
        restored.restore()
        #expect(restored.accounts.first { $0.id == "1" }?.displayName == "用户名（1）")
        #expect(restored.snapshot.assignments == assignments)
        #expect(restored.accounts.first { $0.id == "1" }?.accessKey == original.accessKey)
        #expect(restored.accounts.first { $0.id == "2" }?.displayName == "2")
    }

    @Test func usernameResponseCannotUpdateRemovedOrReauthenticatedAccount() throws {
        let session = LoginSession(vault: MemoryAccountVault())
        let old = account("1")
        try session.add([old])
        try session.remove("1")
        try session.updateUsername("旧用户名", for: old)
        #expect(session.accounts.isEmpty)
        let replacement = BiliAccount(cookies: BiliCookie(SESSDATA: "new-session", bili_jct: "new-csrf",
            DedeUserID: "1", sid: nil, buvid3: nil), accessKey: nil, refresh: nil, type: nil)
        try session.add([replacement])
        try session.updateUsername("旧用户名", for: old)
        #expect(session.accounts.first?.username == nil)
    }

    private func account(_ id: String, type: [Int]? = nil) -> BiliAccount {
        BiliAccount(cookies: BiliCookie(SESSDATA: "session-\(id)", bili_jct: "csrf-\(id)",
            DedeUserID: id, sid: nil, buvid3: nil), accessKey: "token-\(id)", refresh: "refresh-\(id)", type: type)
    }
    @Test func roleAssignmentsRemainIndependentAndSurviveRestore() throws {
        let vault = MemoryAccountVault()
        let session = LoginSession(vault: vault)
        try session.add([account("1")])
        try session.add([account("2")])
        try session.assign("2", to: .playback)
        try session.assign("0", to: .recommendation)
        let restored = LoginSession(vault: vault)
        restored.restore()
        #expect(restored.account(for: .main)?.id == "2")
        #expect(restored.account(for: .history)?.id == "1")
        #expect(restored.account(for: .recommendation) == nil)
        #expect(restored.account(for: .playback)?.accessKey == "token-2")
    }
    @Test func incognitoPreservesAssignmentsAndStopsHistory() throws {
        let session = LoginSession(vault: MemoryAccountVault())
        try session.add([account("1")])
        let assignments = session.snapshot.assignments
        try session.setIncognito(true)
        #expect(!session.shouldReportHistory)
        #expect(session.account(for: .playback)?.id == "1")
        #expect(session.snapshot.assignments == assignments)
        try session.setIncognito(false)
        #expect(session.shouldReportHistory)
        try session.assign("0", to: .history)
        #expect(!session.shouldReportHistory)
    }
    @Test func removalUsesAnonymousWithoutChangingOtherAccounts() throws {
        let session = LoginSession(vault: MemoryAccountVault())
        try session.add([account("1"), account("2")])
        try session.assign("2", to: .playback)
        try session.remove("1")
        #expect(!session.isLogin)
        #expect(!session.shouldReportHistory)
        #expect(session.account(for: .playback)?.id == "2")
        #expect(session.accounts.count == 1)
    }
    @Test func failedWriteLeavesWorkingSessionAndLegacyDataIntact() throws {
        let vault = MemoryAccountVault()
        let session = LoginSession(vault: vault)
        try session.add([account("1")])
        vault.failSave = true
        #expect(throws: AccountStorageError.self) { try session.assign("0") }
        #expect(session.account(for: .main)?.id == "1")
        let suite = "PiliPod.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(account("2").cookies), forKey: "bili_cookie")
        vault.data = nil
        session.restore(defaults: defaults)
        #expect(defaults.data(forKey: "bili_cookie") != nil)
        #expect(session.storageError != nil)
    }
    @Test func legacyMigrationMovesAllCredentialsToVault() throws {
        let suite = "PiliPod.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(account("1").cookies), forKey: "bili_cookie")
        defaults.set("legacy-token", forKey: "bili_accessKey")
        defaults.set("legacy-refresh", forKey: "bili_refresh")
        let vault = MemoryAccountVault()
        let session = LoginSession(vault: vault)
        session.restore(defaults: defaults)
        #expect(session.accessKey == "legacy-token")
        #expect(session.refresh == "legacy-refresh")
        #expect(defaults.data(forKey: "bili_cookie") == nil)
        #expect(vault.data != nil)
        for role in AccountRole.allCases { #expect(session.selectedID(for: role) == "1") }
    }
    @Test func importedRolesAndAllAccountsArePreserved() throws {
        let payload: [String: Any] = [
            "1": ["cookies": ["SESSDATA": "a", "bili_jct": "b", "DedeUserID": "1"], "type": [0, 1]],
            "2": ["cookies": ["SESSDATA": "c", "bili_jct": "d", "DedeUserID": "2"], "type": [3]]
        ]
        let decoded = try LoginImportService.decode(JSONSerialization.data(withJSONObject: payload))
        let session = LoginSession(vault: MemoryAccountVault())
        try session.add(decoded)
        #expect(session.accounts.count == 2)
        #expect(session.account(for: .main)?.id == "1")
        #expect(session.account(for: .history)?.id == "1")
        #expect(session.account(for: .recommendation) == nil)
        #expect(session.account(for: .playback)?.id == "2")
        #expect(throws: AccountStorageError.self) {
            try LoginImportService.decode(Data("{\"1\":{\"cookies\":{}}}".utf8))
        }
    }
    @Test func anonymousRequestRemovesCookiesAndDisablesCookieJar() throws {
        var request = URLRequest(url: try #require(URL(string: "https://api.bilibili.com/test")))
        AccountRequest.apply(account("1"), to: &request)
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("session-1") == true)
        AccountRequest.apply(nil, to: &request)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(!request.httpShouldHandleCookies)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }
    @Test func capturedCredentialsDoNotChangeAfterSwitching() throws {
        let session = LoginSession(vault: MemoryAccountVault())
        try session.add([account("1"), account("2")])
        let captured = try #require(session.account(for: .main))
        try session.assign("2")
        #expect(captured.cookies.bili_jct == "csrf-1")
        #expect(captured.cookieString.contains("session-1"))
        #expect(captured.accessKey == "token-1")
    }
    @Test func historyRequestUsesHistoryCSRFAndNeverExistsInIncognito() throws {
        var state = AccountState()
        state.add(account("1"), activate: true)
        state.add(account("2"), activate: true)
        let request = try #require(AccountRequest.historyRequest(state: state, aid: 3, cid: 4, progress: 5))
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("session-1") == true)
        #expect(request.url?.query?.contains("csrf=csrf-1") == true)
        #expect(request.httpMethod == "POST")
        state.incognito = true
        #expect(AccountRequest.historyRequest(state: state, aid: 3, cid: 4, progress: 5) == nil)
        state.incognito = false
        state.assignments[.history] = "0"
        #expect(AccountRequest.historyRequest(state: state, aid: 3, cid: 4, progress: 5) == nil)
    }
    @Test func signedAppRequestsKeepTokenAndCookieFromTheSameAccount() throws {
        let api = BiliAPI.shared
        let request = try #require(api.makeAppRequest(account: account("2"),
            baseURLString: "https://app.bilibili.com/x/v2/feed/index"))
        #expect(request.url?.query?.contains("access_key=token-2") == true)
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("session-2") == true)
        let anonymous = try #require(api.makeAppRequest(account: nil,
            baseURLString: "https://app.bilibili.com/x/v2/feed/index", parameters: ["access_key": "stale-token"]))
        #expect(anonymous.url?.query?.contains("access_key") == false)
        #expect(anonymous.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(!anonymous.httpShouldHandleCookies)
    }
    @Test func incognitoSearchDoesNotPersistOrEraseExistingHistory() throws {
        let suite = "PiliPod.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = SearchHistoryStore.record("old", in: [], incognito: false, defaults: defaults)
        let result = SearchHistoryStore.record("private", in: existing, incognito: true, defaults: defaults)
        #expect(result == ["old"])
        #expect(defaults.stringArray(forKey: "PiliPod.searchHistory") == ["old"])
        #expect(SearchHistoryStore.record("new", in: result, incognito: false, defaults: defaults) == ["new", "old"])
    }

    @Test func failedRestoreCannotOverwriteStoredAccounts() throws {
        let vault = MemoryAccountVault()
        let original = LoginSession(vault: vault)
        try original.add([account("1")])
        let saved = vault.data
        vault.failLoad = true
        let session = LoginSession(vault: vault)
        session.restore()
        #expect(throws: AccountStorageError.self) { try session.setIncognito(true) }
        #expect(vault.data == saved)
        vault.failLoad = false
        try session.setIncognito(true)
        #expect(session.account(for: .main)?.id == "1")
        #expect(session.incognito)
        let restored = LoginSession(vault: vault)
        restored.restore()
        #expect(restored.incognito)
        #expect(!restored.shouldReportHistory)
    }

}

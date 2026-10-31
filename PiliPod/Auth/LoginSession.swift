import Combine
import Foundation
import Security

enum AccountRole: String, Codable, CaseIterable, Identifiable {
    case main, history, recommendation, playback
    var id: String { rawValue }
    var title: String {
        switch self {
        case .main: "主账号"
        case .history: "记录观看"
        case .recommendation: "推荐"
        case .playback: "视频取流"
        }
    }
}

struct BiliAccount: Codable, Identifiable {
    let cookies: BiliCookie
    var accessKey: String?
    var refresh: String?
    var type: [Int]?
    var username: String? = nil
    var id: String { cookies.DedeUserID }
    var displayName: String {
        guard let name = username?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return id }
        return "\(name)（\(id)）"
    }
    var cookieString: String {
        cookies.dictionary.keys.sorted().map { "\($0)=\(cookies.dictionary[$0] ?? "")" }.joined(separator: "; ")
    }
}

struct AccountState: Codable {
    var accounts: [BiliAccount] = []
    var assignments: [AccountRole: String] = [:]
    var incognito = false
    func account(for role: AccountRole) -> BiliAccount? {
        guard let id = assignments[role], id != "0" else { return nil }
        return accounts.first { $0.id == id }
    }
    mutating func add(_ account: BiliAccount, activate: Bool) {
        var account = account
        if account.username == nil { account.username = accounts.first { $0.id == account.id }?.username }
        let wasEmpty = accounts.isEmpty
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        if wasEmpty {
            for role in AccountRole.allCases { assignments[role] = account.id }
        } else if activate { assignments[.main] = account.id }
    }
    mutating func remove(_ id: String) {
        accounts.removeAll { $0.id == id }
        for role in AccountRole.allCases where assignments[role] == id { assignments[role] = "0" }
    }
    var shouldReportHistory: Bool { !incognito && account(for: .history) != nil }
}

protocol AccountVault {
    func load() throws -> Data?
    func save(_ data: Data) throws
}
struct KeychainAccountVault: AccountVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "PiliPod.accounts.v1", kSecAttrAccount as String: "accounts"]
    }
    func load() throws -> Data? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AccountStorageError.keychain(status) }
        return result as? Data
    }
    func save(_ data: Data) throws {
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AccountStorageError.keychain(status) }
    }
}
enum AccountStorageError: LocalizedError {
    case keychain(OSStatus), invalidAccount
    var errorDescription: String? {
        switch self {
        case .keychain: "无法读写安全登录存储，请解锁设备后重试。"
        case .invalidAccount: "登录数据无效或账号不存在。"
        }
    }
}

final class LoginSession: ObservableObject {
    static let shared = LoginSession()
    @Published private(set) var revision = 0
    @Published private(set) var isLogin = false
    @Published private(set) var storageError: String?
    private let lock = NSRecursiveLock()
    private var state = AccountState()
    private var restoreFailed = false
    private let vault: AccountVault
    init(vault: AccountVault = KeychainAccountVault()) { self.vault = vault }
    var snapshot: AccountState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
    var accounts: [BiliAccount] { snapshot.accounts }
    var cookies: BiliCookie? { account(for: .main)?.cookies }
    var accessKey: String? { account(for: .main)?.accessKey }
    var refresh: String? { account(for: .main)?.refresh }
    var type: [Int]? { account(for: .main)?.type }
    var cookieString: String { account(for: .main)?.cookieString ?? "" }
    var incognito: Bool { snapshot.incognito }
    var shouldReportHistory: Bool { snapshot.shouldReportHistory }
    func account(for role: AccountRole) -> BiliAccount? { snapshot.account(for: role) }
    func selectedID(for role: AccountRole) -> String { snapshot.assignments[role] ?? "0" }
    // Save before publishing; failed writes leave the working session intact.
    @MainActor
    private func update(_ mutation: (inout AccountState) throws -> Void) throws {
        // Retry a failed read before writing, so an empty in-memory state cannot overwrite existing accounts.
        if restoreFailed {
            restore()
            guard !restoreFailed else { throw AccountStorageError.keychain(errSecNotAvailable) }
        }
        lock.lock()
        defer { lock.unlock() }
        var next = state
        try mutation(&next)
        try vault.save(JSONEncoder().encode(next))
        state = next
        storageError = nil
        isLogin = next.account(for: .main) != nil
        revision += 1
    }
    @MainActor
    func add(_ accounts: [BiliAccount], activate: Bool = true) throws {
        guard !accounts.isEmpty, accounts.allSatisfy({
            UInt64($0.id).map { $0 > 0 } == true && !$0.cookies.SESSDATA.isEmpty && !$0.cookies.bili_jct.isEmpty
        }) else { throw AccountStorageError.invalidAccount }
        try update { state in
            for (index, account) in accounts.enumerated() { state.add(account, activate: activate && index == 0) }
            if accounts.allSatisfy({ $0.type != nil }) {
                for (index, role) in AccountRole.allCases.enumerated() {
                    state.assignments[role] = accounts.first { $0.type?.contains(index) == true }?.id ?? "0"
                }
            }
        }
    }
    @MainActor
    func assign(_ id: String, to role: AccountRole? = nil) throws {
        try update { state in
            guard id == "0" || state.accounts.contains(where: { $0.id == id }) else { throw AccountStorageError.invalidAccount }
            for target in role.map({ [$0] }) ?? AccountRole.allCases { state.assignments[target] = id }
        }
    }
    @MainActor
    func remove(_ id: String) throws { try update { $0.remove(id) } }
    @MainActor
    func setIncognito(_ enabled: Bool) throws { try update { $0.incognito = enabled } }
    @MainActor
    func updateUsername(_ username: String, for account: BiliAccount) throws {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let current = accounts.first(where: { $0.id == account.id }),
              current.cookies.SESSDATA == account.cookies.SESSDATA,
              current.username != name else { return }
        try update { state in
            guard let index = state.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            state.accounts[index].username = name
        }
    }
    @MainActor
    func restore(defaults: UserDefaults = .standard) {
        restoreFailed = false
        storageError = nil
        do {
            if let data = try vault.load() {
                let restored = try JSONDecoder().decode(AccountState.self, from: data)
                lock.lock()
                state = restored
                lock.unlock()
                isLogin = restored.account(for: .main) != nil
                revision += 1
                clearLegacy(defaults)
            } else if let data = defaults.data(forKey: "bili_cookie") {
                let cookie = try JSONDecoder().decode(BiliCookie.self, from: data)
                try add([BiliAccount(cookies: cookie, accessKey: defaults.string(forKey: "bili_accessKey"),
                    refresh: defaults.string(forKey: "bili_refresh"), type: nil)])
                clearLegacy(defaults)
            }
        } catch {
            restoreFailed = true
            storageError = error.localizedDescription
        }
    }
    @MainActor
    private func clearLegacy(_ defaults: UserDefaults) {
        for key in ["bili_cookie", "bili_accessKey", "bili_refresh", "bili_type"] { defaults.removeObject(forKey: key) }
    }
}
enum AccountRequest {
    static func historyRequest(state: AccountState, aid: Int, cid: Int, progress: Int) -> URLRequest? {
        guard state.shouldReportHistory, let account = state.account(for: .history) else { return nil }
        var components = URLComponents(string: "https://api.bilibili.com/x/v2/history/report")
        components?.queryItems = [
            URLQueryItem(name: "aid", value: String(aid)), URLQueryItem(name: "cid", value: String(cid)),
            URLQueryItem(name: "progress", value: String(progress)), URLQueryItem(name: "platform", value: "web"),
            URLQueryItem(name: "csrf", value: account.cookies.bili_jct)
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        apply(account, to: &request)
        request.httpMethod = "POST"
        return request
    }

    static func apply(_ account: BiliAccount?, to request: inout URLRequest) {
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(account?.cookieString, forHTTPHeaderField: "Cookie")
    }
}

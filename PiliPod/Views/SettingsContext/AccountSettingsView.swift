import SwiftUI
import UniformTypeIdentifiers

struct AccountSettingsView: View {
    @ObservedObject private var session = LoginSession.shared
    @State private var showLogin = false
    @State private var errorMessage: String?
    @State private var pendingRemoval: String?
    @State private var exportDocument = JSONExportDocument(data: Data())
    @State private var showExport = false

    var body: some View {
        List {
            privacySection
            assignmentSection
            accountsSection
            if let storageError = session.storageError {
                Section { Text(storageError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("账号与隐私")
        .task(id: session.accounts.map(\.id)) { await refreshAccountNames() }
        .fullScreenCover(isPresented: $showLogin) { LoginPageView() }
        .fileExporter(isPresented: $showExport, document: exportDocument,
                      contentType: .json, defaultFilename: "pilipod_account.json") { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .alert("操作失败", isPresented: errorPresented) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("移除此账号？使用该账号的功能将切换为匿名。",
                            isPresented: removalPresented, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                if let id = pendingRemoval { perform { try session.remove(id) } }
                pendingRemoval = nil
            }
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("无痕模式", isOn: Binding(get: { session.incognito }, set: { enabled in
                perform { try session.setIncognito(enabled) }
            }))
        } footer: {
            Text("开启后不再上报观看记录，也不保存新的搜索历史。取流账号和主动点赞、收藏等操作仍然有效；服务端仍可能识别访问。关闭后恢复原来的账号分工。")
        }
    }

    private var assignmentSection: some View {
        Section {
            ForEach(AccountRole.allCases) { role in
                Picker(role.title, selection: assignmentBinding(role)) {
                    Text("0（匿名）").tag("0")
                    ForEach(session.accounts) { account in Text(account.displayName).tag(account.id) }
                }
            }
            Menu("快速统一切换") {
                Button("0（匿名）") { perform { try session.assign("0") } }
                ForEach(session.accounts) { account in
                    Button(account.displayName) { perform { try session.assign(account.id) } }
                }
            }
        } footer: {
            Text("主账号用于个人信息和互动；记录观看用于观看记录上报和历史列表，选择匿名时不上报；推荐用于推荐流；视频取流用于播放和缓存下载。")
        }
    }

    private var accountsSection: some View {
        Section("已登录账号") {
            ForEach(session.accounts) { account in
                HStack {
                    Label(account.displayName, systemImage: "person.crop.circle")
                    Spacer()
                    Button("移除", role: .destructive) { pendingRemoval = account.id }
                        .buttonStyle(.borderless)
                }
            }
            Button("添加账号", systemImage: "person.badge.plus") { showLogin = true }
            LoginImportView(onImported: {})
            Button("导出账号", systemImage: "square.and.arrow.up") {
                perform {
                    exportDocument = JSONExportDocument(data: try LoginImportService.encode(session.snapshot))
                    showExport = true
                }
            }
            .disabled(session.accounts.isEmpty)
        }
    }
    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    private var removalPresented: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }
    private func assignmentBinding(_ role: AccountRole) -> Binding<String> {
        Binding(get: { session.selectedID(for: role) }, set: { id in
            perform { try session.assign(id, to: role) }
        })
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
    private func refreshAccountNames() async {
        let auth = BiliAuthService()
        for account in session.accounts {
            guard !Task.isCancelled else { return }
            do {
                let name = try await auth.fetchAccountName(account)
                try Task.checkCancellation()
                try session.updateUsername(name, for: account)
            } catch {
                // Keep cached names (or the UID fallback) when offline or expired.
            }
        }
    }
}

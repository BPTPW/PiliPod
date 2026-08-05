import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct AboutView: View {
    private enum ImportTarget: String, Identifiable {
        case login
        case settings

        var id: String { rawValue }
    }

    @ObservedObject private var loginSession = LoginSession.shared
    @ObservedObject private var errorLog = ErrorLogService.shared
    @State private var activeImporter: ImportTarget?
    @State private var showImportSheet = false
    @State private var showExportSheet = false
    @State private var exportDocument = JSONExportDocument(data: Data())
    @State private var exportFilename = "PiliPod-export.json"
    @State private var exportErrorMessage: String?
    @State private var loginTransferMessage: String?
    @State private var settingsTransferMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    AppIconPreview()

                    Text(appName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("当前版本", value: versionDisplayText)
                Link(destination: sourceRepositoryURL) {
                    HStack {
                        Text("源代码仓库")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("BPTPW/PiliPod")
                            .foregroundStyle(.primary)
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }

            Section {
                NavigationLink {
                    ErrorLogView()
                } label: {
                    HStack {
                        Text("错误日志")
                            .foregroundStyle(.primary)
                        Spacer()
                        if !errorLog.entries.isEmpty {
                            Text("\(errorLog.entries.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("登录数据") {
                Button("导入登录信息") {
                    activeImporter = .login
                    showImportSheet = true
                }
                .foregroundStyle(.primary)

                Button("导出登录信息") {
                    prepareLoginExport()
                }
                .foregroundStyle(.primary)
                .disabled(!loginSession.isLogin)
            }

            Section {
                Button("导入设置数据") {
                    activeImporter = .settings
                    showImportSheet = true
                }
                .foregroundStyle(.primary)

                Button("导出设置数据") {
                    prepareSettingsExport()
                }
                .foregroundStyle(.primary)
            } header: {
                Text("设置数据")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .fileImporter(
            isPresented: $showImportSheet,
            allowedContentTypes: [.json]
        ) { result in
            handleImportResult(result, for: activeImporter)
            activeImporter = nil
            showImportSheet = false
        }
        .fileExporter(
            isPresented: $showExportSheet,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result {
                exportErrorMessage = error.localizedDescription
            }
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "未知错误")
        }
        .alert("登录数据", isPresented: Binding(
            get: { loginTransferMessage != nil },
            set: { if !$0 { loginTransferMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(loginTransferMessage ?? "未知错误")
        }
        .alert("设置数据", isPresented: Binding(
            get: { settingsTransferMessage != nil },
            set: { if !$0 { settingsTransferMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(settingsTransferMessage ?? "未知错误")
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "PiliPod"
    }

    private var versionDisplayText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version)+\(build)"
    }

    private var sourceRepositoryURL: URL {
        URL(string: "https://github.com/BPTPW/PiliPod/")!
    }

    private func prepareSettingsExport() {
        do {
            let data = try AppSettingsBackupService.exportData()
            exportDocument = JSONExportDocument(data: data)
            exportFilename = "PiliPod-settings.json"
            showExportSheet = true
        } catch {
            ErrorLogService.record(error, context: "导出设置数据")
            settingsTransferMessage = error.localizedDescription
        }
    }

    private func prepareLoginExport() {
        guard let cookies = loginSession.cookies else { return }

        let uid = cookies.DedeUserID
        let loginType: [Int] = loginSession.type ?? [0, 1, 2, 3]

        let cookieDict: [String: String] = [
            "SESSDATA": cookies.SESSDATA,
            "bili_jct": cookies.bili_jct,
            "DedeUserID": cookies.DedeUserID,
            "DedeUserID__ckMd5": "",
            "sid": cookies.sid ?? "",
            "buvid3": cookies.buvid3 ?? ""
        ]

        let userDict: [String: Any] = [
            "cookies": cookieDict,
            "accessKey": loginSession.accessKey ?? "",
            "refresh": loginSession.refresh ?? "",
            "type": loginType
        ]

        let payload: [String: Any] = [
            uid: userDict
        ]

        do {
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            exportDocument = JSONExportDocument(data: data)
            exportFilename = "bili_login_\(uid).json"
            showExportSheet = true
        } catch {
            ErrorLogService.record(error, context: "导出登录信息")
            exportErrorMessage = error.localizedDescription
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>, for target: ImportTarget?) {
        guard let target else { return }

        switch (target, result) {
        case let (.login, .success(url)):
            do {
                try LoginImportService.importFrom(url: url)
                loginTransferMessage = "登录信息已导入。"
            } catch {
                ErrorLogService.record(error, context: "导入登录信息")
                loginTransferMessage = error.localizedDescription
            }
        case let (.login, .failure(error)):
            ErrorLogService.record(error, context: "导入登录信息")
            loginTransferMessage = error.localizedDescription
        case let (.settings, .success(url)):
            do {
                try AppSettingsBackupService.importFrom(url: url)
                settingsTransferMessage = "设置已导入。当前打开的设置页可能需要重新进入后显示。"
            } catch {
                ErrorLogService.record(error, context: "导入设置数据")
                settingsTransferMessage = error.localizedDescription
            }
        case let (.settings, .failure(error)):
            ErrorLogService.record(error, context: "导入设置数据")
            settingsTransferMessage = error.localizedDescription
        }
    }
}

private struct AppIconPreview: View {
    var body: some View {
        Group {
#if canImport(UIKit)
            if let image = appIconImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
#else
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
#endif
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

#if canImport(UIKit)
    private var appIconImage: UIImage? {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = primary?["CFBundleIconFiles"] as? [String]

        for name in (files ?? []).reversed() {
            if let image = UIImage(named: name) {
                return image
            }
        }
        return nil
    }
#endif
}

private struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    AboutView()
}

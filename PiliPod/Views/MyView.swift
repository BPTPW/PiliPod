//
//  MyView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI
import UniformTypeIdentifiers

struct MyView: View {
    @StateObject private var viewModel = MyViewModel()
    @ObservedObject private var loginSession = LoginSession.shared
    @State private var showLoginSheet = false
    @State private var showExportSheet = false
    @State private var exportDocument = LoginExportDocument(data: Data())
    @State private var exportFilename = "login.json"
    @State private var exportErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                if let user = viewModel.user {
                    NavigationLink {
                        UserSpaceView(mid: Int(user.mid))
                    } label: {
                        AsyncImage(url: URL(string: user.face)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text(user.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("UID：\(String(user.mid))")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 72))
                        .foregroundStyle(.secondary)

                    Text(loginSession.isLogin ? "正在加载个人信息…" : "当前未登录")
                        .font(.headline)

                    Text("导入登录 JSON 后即可同步账号状态。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 12) {
                    LoginImportView {
                        Task {
                            await viewModel.loadUser()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    if loginSession.isLogin {
                        Button("导出登录数据") {
                            prepareLoginExport()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("退出登录") {
                            LoginImportService.clearLoginState()
                            viewModel.user = nil
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button("登录") {
                            showLoginSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("我的")
            .task {
                await viewModel.loadUser()
            }
            .fullScreenCover(isPresented: $showLoginSheet) {
                LoginPageView()
            }
            .onReceive(loginSession.$isLogin) { isLogin in
                if isLogin {
                    Task {
                        await viewModel.loadUser()
                    }
                } else {
                    viewModel.user = nil
                }
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
        }
    }

    private func prepareLoginExport() {
        guard let cookies = loginSession.cookies else { return }

        let uid = cookies.DedeUserID
        let payload: [String: Any] = [
            uid: [
                "cookies": [
                    "SESSDATA": cookies.SESSDATA,
                    "bili_jct": cookies.bili_jct,
                    "DedeUserID": cookies.DedeUserID,
                    "DedeUserID__ckMd5": "",
                    "sid": cookies.sid ?? "",
                    "buvid3": cookies.buvid3 ?? ""
                ],
                "accessKey": loginSession.accessKey ?? "",
                "refresh": loginSession.refresh ?? "",
                "type": loginSession.type ?? [0, 1, 2, 3]
            ]
        ]

        do {
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            exportDocument = LoginExportDocument(data: data)
            exportFilename = "bili_login_\(uid).json"
            showExportSheet = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    MyView()
}

private struct LoginExportDocument: FileDocument {
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

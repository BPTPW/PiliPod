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
                // 顶部按钮
                HStack {
                    Spacer()
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .frame(width: 20, height: 20)
                            .padding(10)
                    }
                    .tint(.primary)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 30)
                .padding(.top, 10)

                headerView
                    .padding(.horizontal, 30)

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

    @ViewBuilder
    private var headerView: some View {
        if let user = viewModel.user {
            NavigationLink {
                UserSpaceView(mid: Int(user.mid))
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    AsyncImage(url: URL(string: user.face)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        Text(user.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        HStack(spacing: 12) {
                            Text("硬币 \(formattedMoney(user.money))")
                            Text("经验 \(user.levelInfo.currentExp)/\(maxExperienceText(for: user))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ProgressView(value: experienceProgress(for: user))
                            .tint(Color("BiliPink"))
                            .progressViewStyle(.linear)
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(loginSession.isLogin ? "正在加载个人信息…" : "当前未登录")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("导入登录 JSON 后即可同步账号状态。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        if let stat = viewModel.stat {
            HStack {
                Spacer()
                statItem(value: stat.dynamicCount, title: "动态")
                Spacer()
                statItem(value: stat.following, title: "关注")
                Spacer()
                statItem(value: stat.follower, title: "粉丝")
                Spacer()
            }
            .padding(.top, 2)
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
            exportDocument = LoginExportDocument(data: data)
            exportFilename = "bili_login_\(uid).json"
            showExportSheet = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func maxExperienceText(for user: UserCard) -> String {
        if user.levelInfo.nextExp == "--" {
            return "--"
        }
        return user.levelInfo.nextExp
    }

    private func experienceProgress(for user: UserCard) -> Double {
        if user.levelInfo.nextExp == "--" {
            return 1
        }

        guard let nextExp = Double(user.levelInfo.nextExp) else {
            return 0
        }

        let minExp = Double(user.levelInfo.currentMin)
        let currentExp = Double(user.levelInfo.currentExp)
        let range = max(nextExp - minExp, 1)
        let progress = (currentExp - minExp) / range
        return min(max(progress, 0), 1)
    }

    private func formattedMoney(_ money: Double) -> String {
        if money.rounded() == money {
            return String(Int(money))
        }
        return money.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func statItem(value: Int, title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
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

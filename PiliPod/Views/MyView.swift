//
//  MyView.swift
//  PiliPod
//
//  Created by co on 2026/5/21.
//

import SwiftUI

struct MyView: View {
    @StateObject private var viewModel = MyViewModel()
    @ObservedObject private var loginSession = LoginSession.shared
    @State private var showLoginSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                if let user = viewModel.user {
                    AsyncImage(url: URL(string: user.face)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())

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
        }
    }
}

#Preview {
    MyView()
}

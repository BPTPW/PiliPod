//
//  LoginPageView.swift
//  PiliPod
//
//  Created by co on 2026/5/27.
//

import SwiftUI

struct LoginPageView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        NavigationStack {
            Group {
                Form {
                    Section {
                        TextField("账号", text: $viewModel.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密码", text: $viewModel.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        if let message = viewModel.errorMessage, !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button {
                            Task {
                                await viewModel.executeLoginFlow()
                            }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("登录")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { viewModel.phoneVerifyContext != nil },
                    set: { if !$0 { viewModel.phoneVerifyContext = nil } }
                )
            ) {
                if let context = viewModel.phoneVerifyContext {
                    PhoneVerifySheet(viewModel: viewModel, phoneText: context.maskedTel)
                }
            }
        }
        .sheet(item: $viewModel.geetestContext) { context in
            GeetestCaptchaSheet(
                gt: context.gt,
                challenge: context.challenge
            ) { result in
                Task {
                    if viewModel.phoneVerifyContext != nil {
                        await viewModel.submitPhoneVerifyGeetest(result)
                    } else {
                        await viewModel.submitGeetestResult(
                            result,
                            recaptchaToken: context.recaptchaToken
                        )
                    }
                }
            }
        }
        .onReceive(viewModel.$loginSucceeded) { succeeded in
            if succeeded {
                dismiss()
            }
        }
    }
}

#Preview {
    LoginPageView()
}

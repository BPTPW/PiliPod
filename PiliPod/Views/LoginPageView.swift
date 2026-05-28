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
            VStack(spacing: 16) {
                TextField("账号", text: $viewModel.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("密码", text: $viewModel.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

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
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)

                if let message = viewModel.errorMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("登录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
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
        .sheet(item: $viewModel.phoneVerifyContext) { context in
            PhoneVerifySheet(
                phoneText: context.maskedTel,
                isLoading: viewModel.isLoading,
                errorMessage: viewModel.phoneVerifyMessage,
                onSendCode: {
                    Task {
                        await viewModel.sendPhoneVerifySMS()
                    }
                },
                onSubmitCode: { code in
                    Task {
                        await viewModel.submitPhoneVerifyCode(code)
                    }
                }
            )
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

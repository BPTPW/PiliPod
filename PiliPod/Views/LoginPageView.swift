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
                
                HStack(spacing: 15){
                    Image(systemName: "person.fill")
                    TextField("账号", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.vertical,10)
                .padding(.horizontal,20)
                .glassEffect(.regular.interactive(),in: .capsule)

                HStack(spacing: 15){
                    Image(systemName: "lock.fill")
                    SecureField("密码", text: $viewModel.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.vertical,10)
                .padding(.horizontal,20)
                .glassEffect(.regular.interactive(),in: .capsule)

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
                            .foregroundStyle(.white)
                    }
                }
                .padding(.vertical,10)
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.interactive().tint(.blue),
                    in: .capsule
                )
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

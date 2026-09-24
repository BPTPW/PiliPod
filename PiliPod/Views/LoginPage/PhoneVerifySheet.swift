//
//  PhoneVerifySheet.swift
//  PiliPod
//
//  Created by co on 2026/5/28.
//

import SwiftUI

struct PhoneVerifySheet: View {
    @ObservedObject var viewModel: LoginViewModel
    @State var phoneText: String
    @State private var smsCode = ""
    @State private var tmpStr = ""
    @State private var sendCodeCountdown = 0
    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("", text: self.$phoneText)
                    .disabled(true)
                HStack {
                    TextField(smsCode, text: $tmpStr)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                        .onChange(of: smsCode) { newValue in
                            if newValue.count > 6 {
                                smsCode = String(newValue.prefix(6))
                            }
                        }
                    Divider()
                        .frame(height: 32)
                        .padding(.horizontal, 4)
                    Button {
                        Task {
                            await viewModel.sendPhoneVerifySMS()
                        }
                    } label: {
                        if sendCodeCountdown > 0 {
                            Text("\(sendCodeCountdown)")
                        } else {
                            Text("发送")
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(sendCodeCountdown > 0)
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8)
                }
            } footer: {
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task {
                        await viewModel.submitPhoneVerifyCode(smsCode)
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("验证并登录")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(viewModel.isLoading || smsCode.isEmpty)
            }
        }
        .navigationTitle("验证手机号")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.phoneVerifyMessage) { message in
            // 只有验证码发送成功才弹窗并开始冷却，其余提示保留在页脚
            guard let message, !message.isEmpty, viewModel.phoneVerifySMSSent else { return }
            viewModel.errorMessage = nil
            alertMessage = "验证码发送成功"
            startSendCodeCountdown()
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func startSendCodeCountdown() {
        sendCodeCountdown = 60
        Task { @MainActor in
            while sendCodeCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                sendCodeCountdown -= 1
            }
        }
    }
}

#Preview {
    NavigationStack {
        PhoneVerifySheet(viewModel: LoginViewModel(), phoneText: "139*****999")
    }
}

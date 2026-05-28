//
//  PhoneVerifySheet.swift
//  PiliPod
//
//  Created by co on 2026/5/28.
//

import SwiftUI

struct PhoneVerifySheet: View {
    let phoneText: String
    let isLoading: Bool
    let errorMessage: String?
    let onSendCode: () -> Void
    let onSubmitCode: (_ code: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var smsCode = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("本次登录需要验证手机号")
                    .font(.headline)

                Text(phoneText)
                    .font(.title3)

                TextField("请输入短信验证码", text: $smsCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)

                HStack(spacing: 12) {
                    Button("发送验证码") {
                        onSendCode()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)

                    Button("验证并登录") {
                        onSubmitCode(smsCode)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || smsCode.isEmpty)
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isLoading {
                    ProgressView()
                }

                Spacer()
            }
            .padding()
            .navigationTitle("手机号验证")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

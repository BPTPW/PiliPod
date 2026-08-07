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
            VStack(spacing: 20) {
                Text("需要验证手机号")
                    .font(.headline)

                Text(phoneText)
                    .font(.title3)

                HStack {
                    TextField("请输入短信验证码", text: $smsCode)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                    Button("发送验证码") {
                        onSendCode()
                    }
                    .padding(10)
                    .foregroundStyle(.primary)
                    .disabled(false)
                    .glassEffect(
                        .regular.interactive(),
                        in: .capsule
                    )
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .glassEffect(.regular.interactive(), in: .capsule)

                HStack(spacing: 12) {
                    Button {
                        onSubmitCode(smsCode)
                    } label: {
                        Text("验证并登录")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .disabled(isLoading || smsCode.isEmpty)
                    .foregroundStyle(.white)
                    .glassEffect(
                        .regular.interactive().tint(.blue),
                        in: .capsule
                    )
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
        }
    }
}

#Preview {
    PhoneVerifySheet(
        phoneText: "139*****999",
        isLoading: false,
        errorMessage: nil,
        onSendCode: {},
        onSubmitCode: { code in print("Submit code: \(code)") }
    )
}

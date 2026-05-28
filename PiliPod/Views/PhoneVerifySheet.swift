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

                HStack(){
                    TextField("请输入短信验证码", text: $smsCode)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                    Button("发送验证码") {
                        onSendCode()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.primary)
                    .disabled(false)
                    .glassEffect(
                        .regular.interactive(),
                        in: .capsule
                    )
                }
                .padding(.vertical,10)
                .padding(.horizontal,20)
                .glassEffect(.regular,in: .capsule)
               

                HStack(spacing: 12) {
                    Button("验证并登录") {
                        onSubmitCode(smsCode)
                    }
                    .disabled(isLoading || smsCode.isEmpty)
                    .frame(maxWidth:.infinity)
                    .padding(.vertical,10)
                    .buttonStyle(.plain)
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

#Preview {
    PhoneVerifySheet(
        phoneText: "139****9999",
        isLoading: false,
        errorMessage: nil,
        onSendCode: { },
        onSubmitCode: { code in print("Submit code: \(code)") }
    )
}

//
//  PhoneVerifySheet.swift
//  PiliPod
//
//  Created by co on 2026/5/28.
//

import SwiftUI

struct PhoneVerifySheet: View {
    @State var phoneText: String
    let isLoading: Bool
    let errorMessage: String?
    let onSendCode: () -> Void
    let onSubmitCode: (_ code: String) -> Void
    @State private var smsCode = ""

    var body: some View {
        NavigationStack {
            Group {
                Form {
                    Section {
                        TextField("", text: self.$phoneText)
                            .disabled(true)
                        HStack {
                            TextField("请输入短信验证码", text: $smsCode)
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
                            Button("发送验证码") {
                                onSendCode()
                            }
                                .foregroundStyle(.primary)
                                .disabled(false)
                                .buttonStyle(.borderless)
                            
                        }
                    } footer: {
                        if let error = errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button {  
                            onSubmitCode(smsCode)
                        } label: {
                            Text("验证并登录")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isLoading || smsCode.isEmpty)
                    }
                }

//                if isLoading {
//                    ProgressView()
//                }
            }
        }
        .navigationTitle("验证手机号")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PhoneVerifySheet(
            phoneText: "139*****999",
            isLoading: false,
            errorMessage: nil,
            onSendCode: {},
            onSubmitCode: { code in print("Submit code: \(code)") }
        )
    }
}

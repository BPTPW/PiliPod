import SwiftUI
import CoreImage.CIFilterBuiltins

struct LoginPageView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LoginViewModel()
    @State private var qrGeneration = UUID()
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("登录方式", selection: $viewModel.method) {
                        ForEach(LoginViewModel.Method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.isLoading)
                    loginFields
                    if viewModel.method != .qr { loginButton }
                    if let message = viewModel.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("登录")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
        .task { await viewModel.loadCountries() }
        .task(id: qrTaskID) {
            if viewModel.method == .qr { await viewModel.runQRCode() }
        }
        .onChange(of: viewModel.method) { _, _ in viewModel.errorMessage = nil }
        .onDisappear { operation?.cancel() }
        .sheet(item: $viewModel.geetestContext) { context in
            GeetestCaptchaSheet(gt: context.gt, challenge: context.challenge) { result in
                operation = Task {
                    if viewModel.phoneVerifyContext != nil {
                        await viewModel.submitPhoneVerifyGeetest(result)
                    } else if viewModel.method == .sms {
                        await viewModel.submitSMSCaptcha(result, token: context.recaptchaToken)
                    } else {
                        await viewModel.submitGeetestResult(result, recaptchaToken: context.recaptchaToken)
                    }
                }
            }
        }
        .sheet(item: $viewModel.phoneVerifyContext) { context in
            PhoneVerifySheet(phoneText: context.maskedTel, isLoading: viewModel.isLoading,
                errorMessage: viewModel.phoneVerifyMessage,
                onSendCode: { operation = Task { await viewModel.sendPhoneVerifySMS() } },
                onSubmitCode: { code in operation = Task { await viewModel.submitPhoneVerifyCode(code) } })
        }
        .onReceive(viewModel.$loginSucceeded) { if $0 { dismiss() } }
    }

    private var qrTaskID: String { viewModel.method.rawValue + qrGeneration.uuidString }

    @ViewBuilder private var loginFields: some View {
        switch viewModel.method {
        case .password: passwordFields
        case .sms: smsFields
        case .qr: qrFields
        case .cookie: cookieFields
        }
    }

    private var passwordFields: some View {
        VStack(spacing: 16) {
            TextField("账号", text: $viewModel.username).textContentType(.username)
            SecureField("密码", text: $viewModel.password).textContentType(.password)
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .textFieldStyle(.roundedBorder).disabled(viewModel.isLoading)
    }

    private var smsFields: some View {
        VStack(spacing: 16) {
            HStack {
                Picker("地区", selection: $viewModel.country) {
                    ForEach(viewModel.countries) { country in
                        Text("\(country.name) +\(country.dialCode)").tag(country)
                    }
                }
                TextField("手机号", text: $viewModel.phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
            }
            TextField("短信验证码", text: $viewModel.smsCode).keyboardType(.numberPad).textContentType(.oneTimeCode)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(viewModel.resendAt.timeIntervalSince(context.date))))
                Button(remaining > 0 ? "\(remaining) 秒后可重新发送" : "获取验证码") {
                    operation = Task { await viewModel.sendLoginSMS() }
                }
                .disabled(remaining > 0 || viewModel.isLoading)
            }
            Text(viewModel.smsMessage).font(.footnote).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder).disabled(viewModel.isLoading)
    }

    private var qrFields: some View {
        VStack(spacing: 16) {
            if let url = viewModel.qrURL, let image = qrImage(url) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 240, height: 240).padding(12).background(.white)
                    .accessibilityLabel("登录二维码，请使用哔哩哔哩扫码")
            }
            Text(viewModel.qrMessage).font(.callout)
            Button("刷新二维码", systemImage: "arrow.clockwise") { qrGeneration = UUID() }
        }
    }

    private var cookieFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("粘贴 Cookie（需包含 SESSDATA、bili_jct 和 DedeUserID）").font(.callout)
            TextEditor(text: $viewModel.cookieText).frame(minHeight: 160)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .privacySensitive().overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
            Text("Cookie 登录不包含 App 令牌，部分 App 接口可能不可用。").font(.footnote).foregroundStyle(.secondary)
        }
        .disabled(viewModel.isLoading)
    }

    private var loginButton: some View {
        Button { operation = Task { await viewModel.submitSelectedMethod() } } label: {
            HStack { if viewModel.isLoading { ProgressView() }; Text("登录") }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent).disabled(viewModel.isLoading)
    }

    private func qrImage(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
                from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: image)
    }
}
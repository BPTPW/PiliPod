//
//  GeetestCaptchaSheet.swift
//  PiliPod
//
//  Created by co on 2026/5/28.
//

import SwiftUI
import WebKit

struct GeetestValidateResult {
    let validate: String
    let challenge: String
    let seccode: String
}

struct GeetestCaptchaSheet: View {
    let gt: String
    let challenge: String
    let onSuccess: (GeetestValidateResult) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeetestWebView(
                gt: gt,
                challenge: challenge
            ) { result in
                onSuccess(result)
                dismiss()
            }
            .navigationTitle("人机验证")
        }
    }
}

private struct GeetestWebView: UIViewRepresentable {
    let gt: String
    let challenge: String
    let onSuccess: (GeetestValidateResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "success")
        contentController.add(context.coordinator, name: "error")
        contentController.add(context.coordinator, name: "log")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.preferences.javaScriptEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(htmlTemplate, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private var htmlTemplate: String {
        """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>body { margin: 0; padding: 12px; font-family: -apple-system; }</style>
          </head>
          <body>
            <div id="captcha"></div>
            <script src="https://static.geetest.com/static/js/fullpage.0.0.0.js"></script>
            <script>
              function R(name, data) {
                window.webkit.messageHandlers[name].postMessage(data);
              }
              function L(msg) { R("log", { message: String(msg) }); }

              async function boot() {
                try {
                  const response = await fetch("https://api.geetest.com/gettype.php?gt=\(gt)");
                  const text = await response.text();
                  L("gettype response: " + text);
                  if (!(text.startsWith("(") && text.endsWith(")"))) {
                    throw new Error("invalid gettype response");
                  }

                  const parsed = JSON.parse(text.substring(1, text.length - 1));
                  if (!parsed || parsed.status !== "success" || !parsed.data) {
                    throw new Error("geetest config status failed");
                  }

                  const cfg = Object.assign({}, parsed.data, {
                    gt: "\(gt)",
                    challenge: "\(challenge)",
                    offline: false,
                    new_captcha: true,
                    product: "bind",
                    width: "100%",
                    https: true,
                    protocol: "https://"
                  });

                  let t = Geetest(cfg)
                    .onSuccess(function() {
                      R("success", t.getValidate());
                    })
                    .onError(function(error) {
                      R("error", { message: String(error) });
                    });

                  t.onReady(function() {
                    t.verify();
                  });
                } catch (e) {
                  R("error", { message: (e && e.message) ? e.message : String(e) });
                }
              }

              boot();
            </script>
          </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onSuccess: (GeetestValidateResult) -> Void

        init(onSuccess: @escaping (GeetestValidateResult) -> Void) {
            self.onSuccess = onSuccess
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "log", let payload = message.body as? [String: Any] {
                print("Geetest log: \(payload["message"] as? String ?? "")")
                return
            }

            if message.name == "error", let payload = message.body as? [String: Any] {
                print("Geetest error: \(payload["message"] as? String ?? "")")
                return
            }

            guard message.name == "success",
                  let payload = message.body as? [String: Any]
            else {
                return
            }

            let validate = (payload["geetest_validate"] as? String)
                ?? (payload["validate"] as? String)
                ?? ""
            let challenge = (payload["geetest_challenge"] as? String)
                ?? (payload["challenge"] as? String)
                ?? ""
            let seccode = (payload["geetest_seccode"] as? String)
                ?? (payload["seccode"] as? String)
                ?? ""

            guard !validate.isEmpty, !challenge.isEmpty, !seccode.isEmpty else {
                print("Geetest success payload missing fields: \(payload)")
                return
            }

            onSuccess(GeetestValidateResult(
                validate: validate,
                challenge: challenge,
                seccode: seccode
            ))
        }
    }
}

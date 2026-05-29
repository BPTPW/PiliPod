//
//  ToastView.swift
//  PiliPod
//
//  Created by Codex on 2026/5/29.
//

import SwiftUI

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var duration: TimeInterval = 2
    var bottomPadding: CGFloat = 70

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    toastBody(message: message)
                        .padding(.horizontal, 24)
                        .padding(.bottom, bottomPadding)
                        .transition(
                            .offset(y: 10)
                                .combined(with: .opacity)
                        )
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(duration))
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.message = nil
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: message != nil)
    }

    @ViewBuilder
    private func toastBody(message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(
                .regular.interactive(),
                in: .capsule
            )
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

extension View {
    func toast(
        message: Binding<String?>,
        duration: TimeInterval = 2,
        bottomPadding: CGFloat = 110
    ) -> some View {
        modifier(
            ToastModifier(
                message: message,
                duration: duration,
                bottomPadding: bottomPadding
            )
        )
    }
}

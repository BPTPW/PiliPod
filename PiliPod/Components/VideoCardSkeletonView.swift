//
//  VideoCardSkeletonView.swift
//  PiliPod
//

import SwiftUI

/// 推荐流加载前的占位卡片，布局与 `VideoCardView` 保持一致，带有流光动效。
struct VideoCardSkeletonView: View {
    let thumbnailWidth: CGFloat

    private let cornerRadius: CGFloat = 18
    private var thumbnailHeight: CGFloat { thumbnailWidth * 10 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                placeholderBar(width: thumbnailWidth - 20, height: 14)
                placeholderBar(width: (thumbnailWidth - 20) * 0.6, height: 14)
                placeholderBar(width: (thumbnailWidth - 20) * 0.45, height: 11)
                placeholderBar(width: (thumbnailWidth - 20) * 0.35, height: 12)
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        )
        .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .frame(width: thumbnailWidth, alignment: .leading)
        .shimmering()
        .accessibilityHidden(true)
    }

    private func placeholderBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.systemGray5))
            .frame(width: max(width, 0), height: height)
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let size = proxy.size
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: Color.white.opacity(0.16), location: 0.5),
                            .init(color: .clear, location: 0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: size.width * 3, height: size.height * 3)
                    .offset(
                        x: -size.width + phase * size.width,
                        y: -size.height + phase * size.height
                    )
                    .blendMode(.plusLighter)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

#Preview {
    VideoCardSkeletonView(thumbnailWidth: 180)
        .padding()
}

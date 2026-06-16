import SwiftUI
#if canImport(UIKit)
import CoreImage.CIFilterBuiltins
import UIKit
#endif

struct VideoShareCardView: View {
#if canImport(UIKit)
    let coverImage: UIImage?
#endif
    let title: String
    let uploaderName: String
    let shareURL: URL

    private let cardCornerRadius: CGFloat = 30
    private let mediaCornerRadius: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.78),
                            Color.white.opacity(0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.18)),
                    in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 18) {
                coverSection

                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(uploaderName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    qrCodeSection
                }
            }
            .padding(18)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 18)
    }

    @ViewBuilder
    private var coverSection: some View {
#if canImport(UIKit)
        if let coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
        } else {
            placeholderCover
        }
#else
        placeholderCover
#endif
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color("BiliPink").opacity(0.75),
                        Color.blue.opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                Text("PiliPod")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(18)
            }
            .overlay {
                RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            }
    }

    private var qrCodeSection: some View {
#if canImport(UIKit)
        Group {
            if let qrImage = VideoShareCardRenderer.makeQRCodeImage(from: shareURL) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 88, height: 88)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.82))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                }
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        }
#else
        EmptyView()
#endif
    }
}

#if canImport(UIKit)
@MainActor
enum VideoShareCardRenderer {
    private static let qrContext = CIContext()

    static func renderImage(
        coverImage: UIImage?,
        title: String,
        uploaderName: String,
        shareURL: URL,
        width: CGFloat = 420
    ) -> UIImage? {
        let content = ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VideoShareCardView(
                coverImage: coverImage,
                title: title,
                uploaderName: uploaderName,
                shareURL: shareURL
            )
            .padding(18)
        }
        .frame(width: width)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = .init(width: width, height: nil)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    static func makeQRCodeImage(from url: URL, dimension: CGFloat = 112) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scale = max(dimension / outputImage.extent.width, dimension / outputImage.extent.height)
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = qrContext.createCGImage(transformedImage, from: transformedImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
#endif

#Preview {
#if canImport(UIKit)
    VideoShareCardView(
        coverImage: nil,
        title: "七里香 格温｜把想要的分享样式直接做成一张图",
        uploaderName: "还有下次的叭",
        shareURL: URL(string: "https://b23.tv/BV1WsD1BhEvt")!
    )
    .padding(18)
    .background(Color(.systemGroupedBackground))
#else
    Text("VideoShareCardView Preview")
#endif
}

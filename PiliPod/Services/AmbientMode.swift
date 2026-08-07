import AVFoundation
import SwiftUI

struct AmbientColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let black = AmbientColor(red: 0, green: 0, blue: 0)

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

struct AmbientPalette: Equatable, Sendable {
    let topLeading: AmbientColor
    let topTrailing: AmbientColor
    let bottomLeading: AmbientColor
    let bottomTrailing: AmbientColor

    static let fallback = AmbientPalette(
        topLeading: .black,
        topTrailing: .black,
        bottomLeading: .black,
        bottomTrailing: .black
    )
}

struct AmbientBackdropView: View {
    let palette: AmbientPalette

    var body: some View {
        GeometryReader { geometry in
            let diameter = max(geometry.size.width, geometry.size.height) * 1.25
            ZStack {
                Color.black
                ambientBlob(palette.topLeading.swiftUIColor, diameter: diameter)
                    .offset(x: -geometry.size.width * 0.28, y: -geometry.size.height * 0.28)
                ambientBlob(palette.topTrailing.swiftUIColor, diameter: diameter)
                    .offset(x: geometry.size.width * 0.28, y: -geometry.size.height * 0.28)
                ambientBlob(palette.bottomLeading.swiftUIColor, diameter: diameter)
                    .offset(x: -geometry.size.width * 0.28, y: geometry.size.height * 0.28)
                ambientBlob(palette.bottomTrailing.swiftUIColor, diameter: diameter)
                    .offset(x: geometry.size.width * 0.28, y: geometry.size.height * 0.28)
                Color.black.opacity(0.42)
            }
            .compositingGroup()
            .blur(radius: 28)
            .clipped()
        }
        .animation(.easeInOut(duration: 0.65), value: palette)
        .allowsHitTesting(false)
    }

    private func ambientBlob(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.95), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
            )
            .frame(width: diameter, height: diameter)
    }
}

enum AmbientPaletteAnalyzer {
    static func palette(from pixelBuffer: CVPixelBuffer) -> AmbientPalette? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let step = max(1, min(width, height) / 32)
        var samples = Array(repeating: ColorAccumulator(), count: 4)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let pixel = bytes.advanced(by: y * bytesPerRow + x * 4)
                let blue = Double(pixel[0]) / 255
                let green = Double(pixel[1]) / 255
                let red = Double(pixel[2]) / 255
                let luma = red * 0.2126 + green * 0.7152 + blue * 0.0722
                guard luma > 0.035, luma < 0.96 else { continue }
                let quadrant = (y >= height / 2 ? 2 : 0) + (x >= width / 2 ? 1 : 0)
                samples[quadrant].add(red: red, green: green, blue: blue, luma: luma)
            }
        }

        let colors = samples.map { $0.color }
        guard colors.contains(where: { $0 != .black }) else { return nil }
        return AmbientPalette(
            topLeading: colors[0],
            topTrailing: colors[1],
            bottomLeading: colors[2],
            bottomTrailing: colors[3]
        )
    }

    private struct ColorAccumulator {
        private var red = 0.0
        private var green = 0.0
        private var blue = 0.0
        private var weight = 0.0

        mutating func add(red: Double, green: Double, blue: Double, luma: Double) {
            let sampleWeight = 0.35 + luma
            self.red += red * sampleWeight
            self.green += green * sampleWeight
            self.blue += blue * sampleWeight
            weight += sampleWeight
        }

        var color: AmbientColor {
            guard weight > 0 else { return .black }
            return AmbientColor(
                red: min(1, max(0, red / weight * 1.12)),
                green: min(1, max(0, green / weight * 1.12)),
                blue: min(1, max(0, blue / weight * 1.12))
            )
        }
    }
}

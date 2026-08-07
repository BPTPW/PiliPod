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

    func differsVisibly(from other: AmbientPalette, threshold: Double = 0.035) -> Bool {
        let colors = [topLeading, topTrailing, bottomLeading, bottomTrailing]
        let otherColors = [other.topLeading, other.topTrailing, other.bottomLeading, other.bottomTrailing]
        return zip(colors, otherColors).contains { color, otherColor in
            abs(color.red - otherColor.red) > threshold
                || abs(color.green - otherColor.green) > threshold
                || abs(color.blue - otherColor.blue) > threshold
        }
    }
}

struct AmbientBackdropView: View {
    let palette: AmbientPalette
    let animationDuration: TimeInterval

    var body: some View {
        MeshGradient(
            width: 2,
            height: 2,
            points: [
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
                SIMD2<Float>(0, 1), SIMD2<Float>(1, 1)
            ],
            colors: [
                palette.topLeading.swiftUIColor,
                palette.topTrailing.swiftUIColor,
                palette.bottomLeading.swiftUIColor,
                palette.bottomTrailing.swiftUIColor
            ]
        )
        .animation(.easeInOut(duration: animationDuration), value: palette)
        .allowsHitTesting(false)
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

        let step = max(1, min(width, height) / 24)
        var samples = Array(repeating: ColorAccumulator(), count: 4)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let pixel = bytes.advanced(by: y * bytesPerRow + x * 4)
                let blue = Double(pixel[0]) / 255
                let green = Double(pixel[1]) / 255
                let red = Double(pixel[2]) / 255
                let luma = red * 0.2126 + green * 0.7152 + blue * 0.0722
                // The side areas are what the user sees beside the fitted
                // video. Give their source pixels substantially more weight
                // than the middle, while retaining pure white and black.
                let horizontalPosition = (Double(x) + 0.5) / Double(width)
                let edgeDistance = abs(horizontalPosition - 0.5) * 2
                let sideWeight = 0.20 + pow(edgeDistance, 2.2) * 3.8
                let quadrant = (y >= height / 2 ? 2 : 0) + (x >= width / 2 ? 1 : 0)
                samples[quadrant].add(
                    red: red,
                    green: green,
                    blue: blue,
                    weight: (0.30 + luma) * sideWeight
                )
            }
        }

        let colors = samples.map { $0.color }
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

        mutating func add(red: Double, green: Double, blue: Double, weight: Double) {
            self.red += red * weight
            self.green += green * weight
            self.blue += blue * weight
            self.weight += weight
        }

        var color: AmbientColor {
            guard weight > 0 else { return .black }
            let averageRed = red / weight
            let averageGreen = green / weight
            let averageBlue = blue / weight
            let luma = averageRed * 0.2126 + averageGreen * 0.7152 + averageBlue * 0.0722

            // A little extra saturation prevents averaging from turning vivid
            // scenes gray; contrast preserves pure white and black endpoints.
            func enhanced(_ component: Double) -> Double {
                let saturated = luma + (component - luma) * 1.55
                return min(1, max(0, (saturated - 0.5) * 1.18 + 0.5))
            }
            return AmbientColor(
                red: enhanced(averageRed),
                green: enhanced(averageGreen),
                blue: enhanced(averageBlue)
            )
        }
    }
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A music-detail presentation backed by the video's existing player session.
struct ListenVideoPlayerSheet: View {
    let player: MPVKitPlayer
    let coverURL: URL?
    let title: String
    let artist: String
    let segments: [ProgressSegment]
    let onDismiss: () -> Void
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var systemVolume = SystemVolumeController()
    @State private var volume: Double = 0.5
    @State private var artworkPalette = AmbientPalette.fallback
    @State private var dismissalOffset: CGFloat = 0
    @State private var isDismissing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismissPresentation

    private var snapshot: PlayerUIPlaybackSnapshot { player.uiSnapshot }

    static var presentationBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 99/255, green: 99/255, blue: 102/255), // 固定对应 Gray2
                Color(red: 58/255, green: 58/255, blue: 60/255),  // 固定对应 Gray4
                Color(red: 72/255, green: 72/255, blue: 74/255)   // 固定对应 Gray3
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ListenVideoDrawerSurface(
                    background: background,
                    topCornerRadius: 62
                )
                .frame(
                    width: geo.size.width,
                    height: geo.size.height + geo.safeAreaInsets.top
                )
                .offset(y: -geo.safeAreaInsets.top)

                let maximumArtworkSide = max(1, min(geo.size.width - 56, 360))
                let artworkSide = maximumArtworkSide * (snapshot.isPlaying ? 1 : 0.88)

                VStack(spacing: 0) {
                    Spacer(minLength: max(geo.safeAreaInsets.top + 10, 34))

                    Button(action: requestDismissal) {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.38))
                            .frame(width: 36, height: 5)
                            .frame(width: 72, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭听视频")

                    Spacer(minLength: 24)

                    ZStack {
                        Color.clear

                        coverArtwork
                            .frame(width: artworkSide, height: artworkSide)
                    }
                    .frame(width: maximumArtworkSide, height: maximumArtworkSide)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.18)
                            : .spring(response: 0.58, dampingFraction: 0.56),
                        value: snapshot.isPlaying
                    )

                    Spacer(minLength: 28)

                    VStack(alignment: .leading, spacing: 7) {
                        MarqueeTitle(text: title)
                            .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.white)

                        Text(artist.isEmpty ? "--" : artist)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.56))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 28)

                    ListenVideoProgressControl(
                        currentTime: snapshot.currentTime,
                        duration: snapshot.duration,
                        bufferedUntil: snapshot.bufferedUntil,
                        segments: segments,
                        onSeek: onSeek
                    )
                    .frame(width: maximumArtworkSide)
                    .padding(.top, 25)

                    HStack(spacing: 48) {
                        Button(action: {}) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 25, weight: .semibold))
                        }
                        .disabled(true)

                        ListenVideoPlayPauseButton(
                            isPlaying: snapshot.isPlaying,
                            action: onTogglePlayPause
                        )

                        Button(action: {}) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 25, weight: .semibold))
                        }
                        .disabled(true)
                    }
                    .foregroundStyle(Color.white)
                    .padding(.top, 36)

                    ListenVideoVolumeControl(volume: $volume)
                        .padding(.horizontal, 28)
                        .padding(.top, 36)

                    Spacer(minLength: max(geo.safeAreaInsets.bottom, 20))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Group {
                    if player.listenVideoAudioDebugEnabled {
                        ListenVideoAudioDebugOverlay(
                            energy: player.listenVideoAudioEnergy,
                            isPlaying: snapshot.isPlaying,
                            playbackTime: snapshot.currentTime,
                            envelopeTime: player.listenVideoAudioEnvelopeTime,
                            envelopeFrameCount: player.listenVideoAudioEnvelopeFrameCount
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, max(geo.safeAreaInsets.top + 12, 46))
                .padding(.leading, 14)
            }
            .offset(y: dismissalOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(dismissGesture(height: geo.size.height))
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            volume = systemVolume.currentVolume
        }
        .task(id: coverURL) {
            guard player.usesAVPlayer,
                  let coverURL,
                  let image = await SharedRemoteImageStore.shared.image(for: coverURL),
                  let palette = ArtworkPaletteAnalyzer.palette(from: image)
            else {
                artworkPalette = .fallback
                return
            }
            artworkPalette = palette
        }
    }

    private var coverArtwork: some View {
        ListenVideoArtwork(
            url: coverURL,
            addsShadow: snapshot.isPlaying
        )
    }

    @ViewBuilder
    private var background: some View {
        if player.usesAVPlayer {
            ListenVideoDynamicBackground(
                palette: artworkPalette,
                audioEnergy: player.listenVideoAudioEnergy,
                isPlaying: snapshot.isPlaying
            )
        } else {
            Self.presentationBackground
        }
    }

    private func dismissGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard value.translation.height > 0,
                      value.translation.height > abs(value.translation.width)
                else { return }
                dismissalOffset = value.translation.height
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height > height * 0.22
                    || value.predictedEndTranslation.height > height * 0.32

                guard shouldDismiss else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        dismissalOffset = 0
                    }
                    return
                }

                finishDismissal(from: dismissalOffset, height: height)
            }
    }

    private func requestDismissal() {
        finishDismissal(from: dismissalOffset, height: UIScreen.main.bounds.height)
    }

    private func finishDismissal(from currentOffset: CGFloat, height: CGFloat) {
        guard !isDismissing else { return }
        isDismissing = true

        let remainingDistance = max(height - currentOffset, 0)
        let duration = max(0.12, min(0.28, 0.28 * remainingDistance / max(height, 1)))

        withAnimation(.easeOut(duration: duration)) {
            dismissalOffset = height
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            onDismiss()
            dismissPresentation()
        }
    }

}

private struct ListenVideoAudioDebugOverlay: View {
    let energy: Float
    let isPlaying: Bool
    let playbackTime: TimeInterval
    let envelopeTime: TimeInterval?
    let envelopeFrameCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Audio Energy")
                .font(.system(size: 11, weight: .semibold))
            Text(String(format: "%.4f  (%d%%)", energy, Int(min(max(energy, 0), 1) * 100)))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
            Text(String(format: "player %.2fs", playbackTime))
                .font(.system(size: 10, design: .monospaced))
            if let envelopeTime {
                Text(String(format: "envelope %.2fs  delta %+.2fs", envelopeTime, envelopeTime - playbackTime))
                    .font(.system(size: 10, design: .monospaced))
            } else {
                Text("envelope loading")
                    .font(.system(size: 10, design: .monospaced))
            }
            Text("frames \(envelopeFrameCount)")
                .font(.system(size: 10, design: .monospaced))
            Text(isPlaying ? "playing" : "paused")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }
}

private struct ListenVideoPlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: animateToggle) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 42, weight: .semibold))
                .frame(width: 64, height: 64)
                .scaleEffect(scale)
                .contentTransition(.identity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "暂停" : "播放")
    }

    private func animateToggle() {
        withAnimation(.easeIn(duration: 0.12)) {
            scale = 0.5
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            action()
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.16)
                    : .spring(response: 0.32, dampingFraction: 0.56)
            ) {
                scale = 1
            }
        }
    }
}

private struct ListenVideoDrawerSurface<Background: View>: View {
    let background: Background
    let topCornerRadius: CGFloat

    var body: some View {
        background
            .clipShape(TopRoundedRectangle(cornerRadius: topCornerRadius))
    }
}

private struct ListenVideoDynamicBackground: View {
    let palette: AmbientPalette
    let audioEnergy: Float
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colors: [Color] {
        let source = palette == .fallback ? Self.fallbackPalette : palette
        return [
            source.topLeading.swiftUIColor,
            source.topTrailing.swiftUIColor,
            source.bottomLeading.swiftUIColor,
            source.bottomTrailing.swiftUIColor
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = reduceMotion || !isPlaying
                ? 0
                : context.date.timeIntervalSinceReferenceDate
            let phase = Float(time)
            let horizontalMotion = sin(phase * 0.72) * 0.16
            let verticalMotion = cos(phase * 0.56) * 0.14
            let highlight = reduceMotion || !isPlaying ? 0 : min(max(audioEnergy, 0), 1)
            let highlightDriftX = CGFloat(sin(phase * 0.42) * 120 + horizontalMotion * 300)
            let highlightDriftY = CGFloat(cos(phase * 0.34) * 100 + verticalMotion * 260)
            let highlightSize = 380 + CGFloat(highlight) * 100

            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0, 0), SIMD2<Float>(0.5 + horizontalMotion * 0.38, 0), SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 0.5 - verticalMotion * 0.42),
                    SIMD2<Float>(0.5 + horizontalMotion, 0.5 + verticalMotion),
                    SIMD2<Float>(1, 0.5 + verticalMotion * 0.55),
                    SIMD2<Float>(0, 1), SIMD2<Float>(0.5 - horizontalMotion * 0.58, 1), SIMD2<Float>(1, 1)
                ],
                colors: [
                    colors[0], colors[1], colors[0],
                    colors[2], colors[3], colors[1],
                    colors[2], colors[0], colors[3]
                ]
            )
            .scaleEffect(1.10)
            .blur(radius: 42, opaque: true)
            .overlay {
                RadialGradient(
                    colors: [
                        colors[1].opacity(0.08 + Double(highlight) * 0.50),
                        colors[3].opacity(0.03 + Double(highlight) * 0.18),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: highlightSize * 0.55
                )
                .frame(width: highlightSize, height: highlightSize)
                .offset(x: 118 + highlightDriftX, y: -106 + highlightDriftY)
                .blur(radius: 14)
            }
            .overlay(Color.black.opacity(0.31))
            .clipped()
            .allowsHitTesting(false)
        }
    }

    private static let fallbackPalette = AmbientPalette(
        topLeading: AmbientColor(red: 0.38, green: 0.18, blue: 0.30),
        topTrailing: AmbientColor(red: 0.16, green: 0.29, blue: 0.42),
        bottomLeading: AmbientColor(red: 0.12, green: 0.20, blue: 0.26),
        bottomTrailing: AmbientColor(red: 0.30, green: 0.20, blue: 0.16)
    )
}

private struct TopRoundedRectangle: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(max(cornerRadius, 0), min(rect.width, rect.height) / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#if canImport(UIKit)
private struct ListenVideoArtwork: View {
    let url: URL?
    let addsShadow: Bool

    @State private var artwork: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let artwork {
                let size = fittedSize(for: artwork.size, in: geo.size)

                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(
                        color: .black.opacity(addsShadow ? 0.28 : 0),
                        radius: addsShadow ? 22 : 0,
                        x: 0,
                        y: addsShadow ? 14 : 0
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url else {
                artwork = nil
                return
            }
            artwork = await SharedRemoteImageStore.shared.image(for: url)
        }
    }

    private func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let imageRatio = imageSize.width / imageSize.height
        let containerRatio = container.width / max(container.height, 1)
        if imageRatio > containerRatio {
            return CGSize(width: container.width, height: container.width / imageRatio)
        }
        return CGSize(width: container.height * imageRatio, height: container.height)
    }
}
#else
private struct ListenVideoArtwork: View {
    let url: URL?
    let addsShadow: Bool

    var body: some View { Color.clear }
}
#endif

private struct ListenVideoProgressControl: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedUntil: TimeInterval
    let segments: [ProgressSegment]
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double?
    @State private var dragStartProgress: Double?

    private var displayedProgress: Double {
        dragProgress ?? normalizedProgress(currentTime, duration: duration)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let scale: CGFloat = isDragging ? 1.055 : 1
            let opacity = isDragging ? 0.9 : 0.28

            VStack(spacing: 5) {
                VideoProgressTrack(
                    width: width,
                    height: isDragging ? 12 : 7,
                    playedProgress: displayedProgress,
                    bufferedProgress: normalizedProgress(bufferedUntil, duration: duration),
                    segments: segments,
                    playedColor: .white.opacity(isDragging ? 0.95 : 0.68),
                    showsKnob: false,
                    bufferedOpacity: isDragging ? 0.5 : 0.34,
                    style: .system,
                    knobOpacity: isDragging ? 1 : 0.86
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .frame(height: 22)

                HStack {
                    Text(formatTime(duration * displayedProgress))
                    Spacer()
                    Text("-\(formatTime(max(duration - duration * displayedProgress, 0)))")
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(opacity))
                .frame(width: width)
            }
            .scaleEffect(scale)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 54)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isDragging)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                }
                let base = dragStartProgress ?? dragProgress ?? normalizedProgress(currentTime, duration: duration)
                dragStartProgress = base
                dragProgress = min(max(base + value.translation.width / width, 0), 1)
            }
            .onEnded { value in
                let base = dragStartProgress ?? dragProgress ?? normalizedProgress(currentTime, duration: duration)
                let progress = min(max(base + value.translation.width / width, 0), 1)
                dragProgress = nil
                dragStartProgress = nil
                isDragging = false
                guard duration > 0 else { return }
                onSeek(duration * progress)
            }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct ListenVideoVolumeControl: View {
    @Binding var volume: Double

    @State private var systemVolume = SystemVolumeController()
    @State private var isDragging = false
    @State private var dragStartVolume: Double?

    var body: some View {
        GeometryReader { geo in
            let iconWidth: CGFloat = 18
            let spacing: CGFloat = 13
            let trackWidth = max(1, geo.size.width - iconWidth * 2 - spacing * 2)

            HStack(spacing: spacing) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: iconWidth)

                VideoProgressTrack(
                    width: trackWidth,
                    height: isDragging ? 10 : 6,
                    playedProgress: volume,
                    bufferedProgress: 0,
                    segments: [],
                    playedColor: .white.opacity(isDragging ? 0.95 : 0.68),
                    showsKnob: false,
                    bufferedOpacity: isDragging ? 0.5 : 0.34,
                    style: .system,
                    knobOpacity: isDragging ? 1 : 0.82
                )
                .frame(width: trackWidth, height: 22)
                .padding(.vertical, 4)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: iconWidth)
            }
            .scaleEffect(isDragging ? 1.055 : 1)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: trackWidth))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 32)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isDragging)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartVolume = volume
                }
                let base = dragStartVolume ?? volume
                let nextVolume = min(max(base + Double(value.translation.width / width), 0), 1)
                volume = nextVolume
                systemVolume.setVolume(nextVolume)
            }
            .onEnded { _ in
                dragStartVolume = nil
                isDragging = false
            }
    }
}

private struct MarqueeTitle: View {
    let text: String

    var body: some View {
        GeometryReader { geo in
            let estimatedWidth = CGFloat(text.count) * 18
            let isScrollable = estimatedWidth > geo.size.width
            let travel = max(estimatedWidth - geo.size.width, 0)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let cycle = 10.0
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                let progress = min(max((phase - 1) / (cycle - 2), 0), 1)

                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: isScrollable ? -travel * progress : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 28)
        .clipped()
        .accessibilityLabel(text)
    }
}

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
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var systemVolume = SystemVolumeController()
    @State private var volume: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snapshot: PlayerUIPlaybackSnapshot { player.uiSnapshot }

    static var presentationBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(.systemGray2),
                Color(.systemGray4),
                Color(.systemGray3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            GeometryReader { geo in
                let maximumArtworkSide = max(1, min(geo.size.width - 56, 360))
                let artworkSide = maximumArtworkSide * (snapshot.isPlaying ? 1 : 0.88)

                VStack(spacing: 0) {
                    Spacer(minLength: 36)

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
                            .foregroundStyle(.primary)

                        Text(artist.isEmpty ? "--" : artist)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.56))
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

                        Button(action: onTogglePlayPause) {
                            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .frame(width: 64, height: 64)
                        }
                        .accessibilityLabel(snapshot.isPlaying ? "暂停" : "播放")

                        Button(action: {}) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 25, weight: .semibold))
                        }
                        .disabled(true)
                    }
                    .foregroundStyle(.primary)
                    .padding(.top, 36)

                    ListenVideoVolumeControl(volume: $volume)
                        .padding(.horizontal, 28)
                        .padding(.top, 36)

                    Spacer(minLength: max(geo.safeAreaInsets.bottom, 20))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            volume = systemVolume.currentVolume
        }
    }

    private var coverArtwork: some View {
        ListenVideoArtwork(
            url: coverURL,
            addsShadow: snapshot.isPlaying
        )
    }

    private var background: some View { Self.presentationBackground }

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
                .foregroundStyle(.primary.opacity(opacity))
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
                    .foregroundStyle(.primary.opacity(0.72))
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
                    .foregroundStyle(.primary.opacity(0.72))
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

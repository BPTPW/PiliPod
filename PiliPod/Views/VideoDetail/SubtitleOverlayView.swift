import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let currentTime: TimeInterval
    let controlsVisible: Bool
    let isFullscreen: Bool

    private var currentCue: SubtitleCue? {
        guard !cues.isEmpty else { return nil }
        var lowerBound = 0
        var upperBound = cues.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if cues[middle].start <= currentTime {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        let candidateIndex = lowerBound - 1
        guard cues.indices.contains(candidateIndex) else { return nil }
        let candidate = cues[candidateIndex]
        return currentTime >= candidate.start && currentTime <= candidate.end ? candidate : nil
    }

    private var bottomOffset: CGFloat {
        guard controlsVisible else { return 14 }
        return isFullscreen ? 118 : 58
    }

    var body: some View {
        if let currentCue {
            Text(currentCue.text)
                .font(.system(size: isFullscreen ? 18 : 15, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                )
                .padding(.horizontal, isFullscreen ? 40 : 24)
                .padding(.bottom, bottomOffset)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .animation(.easeOut(duration: 0.08), value: currentCue.id)
                .animation(.easeOut(duration: 0.12), value: controlsVisible)
        }
    }
}

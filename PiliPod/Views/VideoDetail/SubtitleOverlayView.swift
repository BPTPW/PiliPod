import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let currentTime: TimeInterval
    let controlsVisible: Bool
    let isFullscreen: Bool
    let settings: SubtitleSettings

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
                .foregroundStyle(settings.usesGlassStyle ? .primary : settings.textColor.color)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .modifier(SubtitleBackgroundModifier(settings: settings))
                .padding(.horizontal, isFullscreen ? 40 : 24)
                .padding(.bottom, bottomOffset)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .animation(.easeOut(duration: 0.08), value: currentCue.id)
                .animation(.easeOut(duration: 0.12), value: controlsVisible)
        }
    }
}

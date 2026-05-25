import SwiftUI
import UIKit
import Combine

struct DanmakuEngineConfig: Sendable, Equatable {
    var blockLevel: Int = 0
    var blockScroll = false
    var blockTop = false
    var blockBottom = false
    var blockColorful = false
    var allowOverlapWhenMassive = false
    var forceAllScroll = false
    var topRegionRatio: Double = 1.0
    var bottomRegionRatio: Double = 1.0
    var opacity: Double = 1.0
    var fontWeightValue: Int = 6
    var strokeWidth: Double = 1.0
    var fontScale: Double = 1.0
    var fullscreenFontScale: Double = 1.2
    var scrollDuration: Double = 7.0
    var staticDuration: Double = 4.0
    var lineHeightMultiplier: Double = 1.6

    func clamped() -> DanmakuEngineConfig {
        var c = self
        c.blockLevel = min(max(c.blockLevel, 0), 10)
        c.topRegionRatio = min(max(c.topRegionRatio, 0.1), 1.0)
        c.bottomRegionRatio = min(max(c.bottomRegionRatio, 0.1), 1.0)
        c.opacity = min(max(c.opacity, 0.0), 1.0)
        c.fontWeightValue = min(max(c.fontWeightValue, 1), 9)
        c.strokeWidth = min(max(c.strokeWidth, 0.0), 5.0)
        c.fontScale = min(max(c.fontScale, 0.5), 2.5)
        c.fullscreenFontScale = min(max(c.fullscreenFontScale, 0.5), 2.5)
        c.scrollDuration = min(max(c.scrollDuration, 1.0), 30.0)
        c.staticDuration = min(max(c.staticDuration, 1.0), 30.0)
        c.lineHeightMultiplier = min(max(c.lineHeightMultiplier, 1.0), 3.0)
        return c
    }

    var uiFontWeight: UIFont.Weight {
        switch fontWeightValue {
        case 1: .ultraLight
        case 2: .thin
        case 3: .light
        case 4: .regular
        case 5: .medium
        case 6: .semibold
        case 7: .bold
        case 8: .heavy
        default: .black
        }
    }
}

extension DanmakuEngineConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case blockLevel
        case blockScroll
        case blockTop
        case blockBottom
        case blockColorful
        case allowOverlapWhenMassive
        case forceAllScroll
        case topRegionRatio
        case bottomRegionRatio
        case opacity
        case fontWeightValue
        case strokeWidth
        case fontScale
        case fullscreenFontScale
        case scrollDuration
        case staticDuration
        case lineHeightMultiplier
    }
}

enum DanmakuConfigStore {
    private static let key = "pili.danmaku.config.v1"

    static func load() -> DanmakuEngineConfig {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(DanmakuEngineConfig.self, from: data)
        else {
            return DanmakuEngineConfig().clamped()
        }
        return decoded.clamped()
    }

    static func save(_ config: DanmakuEngineConfig) {
        let clamped = config.clamped()
        guard let data = try? JSONEncoder().encode(clamped) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum DanmakuRenderKind: Sendable {
    case scroll
    case top
    case bottom
}

struct DanmakuPreparedItem: Identifiable {
    let id: Int64
    let appearTime: Double
    let kind: DanmakuRenderKind
    let text: String
    let color: Color
    let duration: Double
    let width: CGFloat
    let fontSize: CGFloat
    let zSeed: Int
}

struct DanmakuActiveItem: Identifiable {
    let id: Int64
    let kind: DanmakuRenderKind
    let text: String
    let color: Color
    let appearTime: Double
    let duration: Double
    let width: CGFloat
    let fontSize: CGFloat
    let line: Int
    let topY: CGFloat
    let lineHeight: CGFloat
    let zIndexValue: Double
}

@MainActor
final class DanmakuEngine: ObservableObject {
    @Published private(set) var activeItems: [DanmakuActiveItem] = []

    private var config: DanmakuEngineConfig
    private var items: [DanmakuPreparedItem] = []
    private var cursor = 0
    private var topLaneNextFree: [Double] = []
    private var bottomLaneNextFree: [Double] = []
    private var scrollLaneNextFree: [Double] = []
    private var containerWidth: CGFloat = 0
    private var containerHeight: CGFloat = 0
    private var lineHeight: CGFloat = 28
    private var maxPreparedFontSize: CGFloat = 18
    private var topLaneCount = 0
    private var bottomLaneCount = 0
    private var scrollLaneCount = 0

    init(config: DanmakuEngineConfig = DanmakuEngineConfig()) {
        self.config = config.clamped()
    }

    func updateConfig(_ config: DanmakuEngineConfig) {
        self.config = config.clamped()
    }

    func load(elements: [Bilibili_Community_Service_Dm_V1_DanmakuElem], config: DanmakuEngineConfig? = nil) {
        if let config {
            self.config = config.clamped()
        }
        items = prepareItems(from: elements)
        maxPreparedFontSize = items.map(\.fontSize).max() ?? 18
        cursor = 0
        activeItems = []
        topLaneNextFree = []
        bottomLaneNextFree = []
        scrollLaneNextFree = []
    }

    func reset() {
        cursor = 0
        activeItems = []
        topLaneNextFree = []
        bottomLaneNextFree = []
        scrollLaneNextFree = []
    }

    func updateLayout(width: CGFloat, height: CGFloat, isFullscreen: Bool = false) {
        guard width > 0, height > 0 else { return }
        containerWidth = width
        containerHeight = height

        let fullscreenRatio = config.fullscreenFontScale / max(config.fontScale, 0.01)
        let effectiveFontSize = isFullscreen ? (maxPreparedFontSize * CGFloat(fullscreenRatio)) : maxPreparedFontSize
        lineHeight = max(12, effectiveFontSize * CGFloat(config.lineHeightMultiplier))

        topLaneCount = max(1, Int((height * CGFloat(config.topRegionRatio)) / lineHeight))
        bottomLaneCount = max(1, Int((height * CGFloat(config.bottomRegionRatio)) / lineHeight))
        scrollLaneCount = max(1, Int((height * CGFloat(config.topRegionRatio)) / lineHeight))

        ensureLaneStorage()
    }

    func tick(currentTime: Double) {
        if containerWidth <= 0 || containerHeight <= 0 { return }

        activeItems.removeAll { currentTime >= $0.appearTime + $0.duration }

        while cursor < items.count {
            let item = items[cursor]
            if item.appearTime > currentTime { break }
            tryActivate(item: item, currentTime: currentTime)
            cursor += 1
        }
    }

    private func ensureLaneStorage() {
        if topLaneNextFree.count != topLaneCount {
            topLaneNextFree = Array(repeating: 0, count: topLaneCount)
        }
        if bottomLaneNextFree.count != bottomLaneCount {
            bottomLaneNextFree = Array(repeating: 0, count: bottomLaneCount)
        }
        if scrollLaneNextFree.count != scrollLaneCount {
            scrollLaneNextFree = Array(repeating: 0, count: scrollLaneCount)
        }
    }

    private func tryActivate(item: DanmakuPreparedItem, currentTime: Double) {
        switch item.kind {
        case .scroll:
            guard let lane = pickLane(nextFree: scrollLaneNextFree, at: item.appearTime, allowOverlap: config.allowOverlapWhenMassive) else {
                return
            }
            if !config.allowOverlapWhenMassive {
                scrollLaneNextFree[lane] = item.appearTime + scrollLaneCooldown(item: item)
            }
            let y = CGFloat(lane) * lineHeight
            activeItems.append(
                DanmakuActiveItem(
                    id: item.id,
                    kind: .scroll,
                    text: item.text,
                    color: item.color,
                    appearTime: item.appearTime,
                    duration: item.duration,
                    width: item.width,
                    fontSize: item.fontSize,
                    line: lane,
                    topY: y,
                    lineHeight: lineHeight,
                    zIndexValue: Double(item.zSeed)
                )
            )
        case .top:
            guard let lane = pickLane(nextFree: topLaneNextFree, at: item.appearTime, allowOverlap: config.allowOverlapWhenMassive) else {
                return
            }
            if !config.allowOverlapWhenMassive {
                topLaneNextFree[lane] = item.appearTime + item.duration
            }
            let y = CGFloat(lane) * lineHeight
            activeItems.append(
                DanmakuActiveItem(
                    id: item.id,
                    kind: .top,
                    text: item.text,
                    color: item.color,
                    appearTime: item.appearTime,
                    duration: item.duration,
                    width: item.width,
                    fontSize: item.fontSize,
                    line: lane,
                    topY: y,
                    lineHeight: lineHeight,
                    zIndexValue: Double(item.zSeed)
                )
            )
        case .bottom:
            guard let lane = pickLane(nextFree: bottomLaneNextFree, at: item.appearTime, allowOverlap: config.allowOverlapWhenMassive) else {
                return
            }
            if !config.allowOverlapWhenMassive {
                bottomLaneNextFree[lane] = item.appearTime + item.duration
            }
            let y = containerHeight - (CGFloat(lane + 1) * lineHeight)
            activeItems.append(
                DanmakuActiveItem(
                    id: item.id,
                    kind: .bottom,
                    text: item.text,
                    color: item.color,
                    appearTime: item.appearTime,
                    duration: item.duration,
                    width: item.width,
                    fontSize: item.fontSize,
                    line: lane,
                    topY: y,
                    lineHeight: lineHeight,
                    zIndexValue: Double(item.zSeed)
                )
            )
        }
    }

    private func pickLane(nextFree: [Double], at time: Double, allowOverlap: Bool) -> Int? {
        if allowOverlap { return nextFree.isEmpty ? nil : Int.random(in: 0 ..< nextFree.count) }
        for (idx, freeAt) in nextFree.enumerated() where freeAt <= time {
            return idx
        }
        return nil
    }

    private func scrollLaneCooldown(item: DanmakuPreparedItem) -> Double {
        let totalDistance = max(containerWidth + item.width, 1)
        let requiredProgress = min(max(item.width / totalDistance, 0), 1)
        let cooldown = item.duration * requiredProgress
        return max(0.05, cooldown)
    }

    private func prepareItems(from elements: [Bilibili_Community_Service_Dm_V1_DanmakuElem]) -> [DanmakuPreparedItem] {
        var prepared: [DanmakuPreparedItem] = []
        prepared.reserveCapacity(elements.count)

        let c = config.clamped()
        for (idx, elem) in elements.enumerated() {
            guard !elem.content.isEmpty else { continue }
            if elem.weight < Int32(c.blockLevel) { continue }

            let kind = renderKind(for: Int(elem.mode), forceAllScroll: c.forceAllScroll)
            if c.blockScroll && kind == .scroll { continue }
            if c.blockTop && kind == .top { continue }
            if c.blockBottom && kind == .bottom { continue }
            if c.blockColorful && elem.color != 16777215 { continue }

            let appear = max(0, Double(elem.progress) / 1000.0)
            let duration = (kind == .scroll) ? c.scrollDuration : c.staticDuration
            let fontSize = baseFontSize(for: Int(elem.fontsize)) * c.fontScale
            let width = textWidth(elem.content, fontSize: fontSize, weight: c.uiFontWeight)
            let color = colorFromRGB888(Int(elem.color))

            prepared.append(
                DanmakuPreparedItem(
                    id: elem.id,
                    appearTime: appear,
                    kind: kind,
                    text: elem.content,
                    color: color,
                    duration: duration,
                    width: width,
                    fontSize: CGFloat(fontSize),
                    zSeed: idx
                )
            )
        }

        prepared.sort { $0.appearTime < $1.appearTime }
        return prepared
    }

    private func renderKind(for mode: Int, forceAllScroll: Bool) -> DanmakuRenderKind {
        if forceAllScroll { return .scroll }
        switch mode {
        case 4: return .bottom
        case 5: return .top
        default: return .scroll
        }
    }

    private func baseFontSize(for protoFontSize: Int) -> Double {
        switch protoFontSize {
        case ..<25:
            return 12
        case 25..<36:
            return 17
        default:
            return 24
        }
    }

    private func textWidth(_ text: String, fontSize: Double, weight: UIFont.Weight) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(width)
    }

    private func colorFromRGB888(_ rgb: Int) -> Color {
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

struct DanmakuOverlayView: View {
    let currentTime: Double
    let isPlaying: Bool
    let elements: [Bilibili_Community_Service_Dm_V1_DanmakuElem]
    let config: DanmakuEngineConfig

    @StateObject private var engine = DanmakuEngine()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
                ZStack(alignment: .topLeading) {
                    ForEach(engine.activeItems) { item in
                        danmakuText(item)
                            .position(x: xPosition(for: item, containerWidth: geo.size.width), y: item.topY + item.lineHeight * 0.5)
                            .zIndex(item.zIndexValue)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .onAppear {
                    engine.updateConfig(config)
                    engine.load(elements: elements, config: config)
                    engine.updateLayout(width: geo.size.width, height: geo.size.height)
                }
                .onChange(of: elements) { _, newValue in
                    engine.load(elements: newValue, config: config)
                    engine.updateLayout(width: geo.size.width, height: geo.size.height)
                }
                .onChange(of: config) { _, newValue in
                    engine.updateConfig(newValue)
                    engine.load(elements: elements, config: newValue)
                    engine.updateLayout(width: geo.size.width, height: geo.size.height)
                }
                .onChange(of: geo.size) { _, newSize in
                    engine.updateLayout(width: newSize.width, height: newSize.height)
                }
                .onChange(of: currentTime) { _, newValue in
                    engine.tick(currentTime: newValue)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func xPosition(for item: DanmakuActiveItem, containerWidth: CGFloat) -> CGFloat {
        switch item.kind {
        case .scroll:
            let progress = min(max((currentTime - item.appearTime) / item.duration, 0), 1)
            let track = containerWidth + item.width
            let leftX = containerWidth - (track * progress)
            return leftX + item.width * 0.5
        case .top, .bottom:
            return containerWidth * 0.5
        }
    }

    private func danmakuText(_ item: DanmakuActiveItem) -> some View {
        ZStack {
            if config.strokeWidth > 0 {
                let s = config.strokeWidth
                let diagonal = s * 0.70710678
                let outlineOffsets: [(Double, Double)] = [
                    (s, 0), (-s, 0), (0, s), (0, -s),
                    (diagonal, diagonal), (-diagonal, diagonal),
                    (diagonal, -diagonal), (-diagonal, -diagonal)
                ]

                ForEach(0 ..< outlineOffsets.count, id: \.self) { idx in
                    Text(item.text)
                        .font(
                            .system(
                                size: item.fontSize,
                                weight: Font.Weight(config.uiFontWeight),
                                design: .default
                            )
                        )
                        .lineLimit(1)
                        .foregroundStyle(.black.opacity(config.opacity))
                        .offset(x: outlineOffsets[idx].0, y: outlineOffsets[idx].1)
                }
            }

            Text(item.text)
                .font(
                    .system(
                        size: item.fontSize,
                        weight: Font.Weight(config.uiFontWeight),
                        design: .default
                    )
                )
                .lineLimit(1)
                .foregroundStyle(item.color.opacity(config.opacity))
        }
    }
}

private extension Font.Weight {
    init(_ uiWeight: UIFont.Weight) {
        switch uiWeight {
        case .ultraLight: self = .ultraLight
        case .thin: self = .thin
        case .light: self = .light
        case .regular: self = .regular
        case .medium: self = .medium
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .heavy: self = .heavy
        default: self = .black
        }
    }
}

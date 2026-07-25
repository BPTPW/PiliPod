import SwiftUI
import UIKit
import CoreImage

struct DanmakuEngineConfig: Sendable, Equatable {
    var isEnabled = true
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
    var strokeWidth: Double = 0.8
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
        c.strokeWidth = min(max(c.strokeWidth, 0.0), 2.0)
        c.fontScale = min(max(c.fontScale, 0.5), 2.5)
        c.fullscreenFontScale = min(max(c.fullscreenFontScale, 0.5), 2.5)
        c.scrollDuration = min(max(c.scrollDuration, 1.0), 30.0)
        c.staticDuration = min(max(c.staticDuration, 1.0), 30.0)
        c.lineHeightMultiplier = min(max(c.lineHeightMultiplier, 1.0), 3.0)
        return c
    }

    var uiFontWeight: UIFont.Weight {
        switch fontWeightValue {
        case 1: .ultraLight; case 2: .thin; case 3: .light; case 4: .regular
        case 5: .medium; case 6: .semibold; case 7: .bold; case 8: .heavy
        default: .black
        }
    }
}

extension DanmakuEngineConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, blockLevel, blockScroll, blockTop, blockBottom, blockColorful
        case allowOverlapWhenMassive, forceAllScroll, topRegionRatio, bottomRegionRatio
        case opacity, fontWeightValue, strokeWidth, fontScale, fullscreenFontScale
        case scrollDuration, staticDuration, lineHeightMultiplier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        blockLevel = try c.decodeIfPresent(Int.self, forKey: .blockLevel) ?? 0
        blockScroll = try c.decodeIfPresent(Bool.self, forKey: .blockScroll) ?? false
        blockTop = try c.decodeIfPresent(Bool.self, forKey: .blockTop) ?? false
        blockBottom = try c.decodeIfPresent(Bool.self, forKey: .blockBottom) ?? false
        blockColorful = try c.decodeIfPresent(Bool.self, forKey: .blockColorful) ?? false
        allowOverlapWhenMassive = try c.decodeIfPresent(Bool.self, forKey: .allowOverlapWhenMassive) ?? false
        forceAllScroll = try c.decodeIfPresent(Bool.self, forKey: .forceAllScroll) ?? false
        topRegionRatio = try c.decodeIfPresent(Double.self, forKey: .topRegionRatio) ?? 1
        bottomRegionRatio = try c.decodeIfPresent(Double.self, forKey: .bottomRegionRatio) ?? 1
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        fontWeightValue = try c.decodeIfPresent(Int.self, forKey: .fontWeightValue) ?? 6
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 0.8
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1
        fullscreenFontScale = try c.decodeIfPresent(Double.self, forKey: .fullscreenFontScale) ?? 1.2
        scrollDuration = try c.decodeIfPresent(Double.self, forKey: .scrollDuration) ?? 7
        staticDuration = try c.decodeIfPresent(Double.self, forKey: .staticDuration) ?? 4
        lineHeightMultiplier = try c.decodeIfPresent(Double.self, forKey: .lineHeightMultiplier) ?? 1.6
    }
}

enum DanmakuConfigStore {
    private static let key = "pili.danmaku.config.v1"
    static func load() -> DanmakuEngineConfig {
        guard let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(DanmakuEngineConfig.self, from: data) else { return DanmakuEngineConfig().clamped() }
        return value.clamped()
    }
    static func save(_ config: DanmakuEngineConfig) {
        guard let data = try? JSONEncoder().encode(config.clamped()) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum DanmakuRenderKind { case scroll, top, bottom }

private struct DanmakuPreparedItem {
    let id: Int64
    let appearTime: Double
    let kind: DanmakuRenderKind
    let text: String
    let color: UIColor
    let duration: Double
    let width: CGFloat
    let fontSize: CGFloat
}

private struct DanmakuActiveItem {
    let item: DanmakuPreparedItem
    let topY: CGFloat
    let lineHeight: CGFloat
}

private struct DanmakuWindowStamp: Equatable {
    let count: Int
    let firstID: Int64
    let firstProgress: Int64
    let lastID: Int64
    let lastProgress: Int64

    init(_ elements: [Bilibili_Community_Service_Dm_V1_DanmakuElem]) {
        count = elements.count
        firstID = elements.first?.id ?? 0
        firstProgress = Int64(elements.first?.progress ?? 0)
        lastID = elements.last?.id ?? 0
        lastProgress = Int64(elements.last?.progress ?? 0)
    }
}

/// A bounded scheduler. Window replacement is incremental; config/layout/seek rebuild explicitly.
@MainActor
private final class DanmakuEngine {
    private var config: DanmakuEngineConfig
    private var itemsByID: [Int64: DanmakuPreparedItem] = [:]
    private var ordered: [DanmakuPreparedItem] = []
    private(set) var activeItems: [DanmakuActiveItem] = []
    private var attemptedIDs: Set<Int64> = []
    private var cursor = 0
    private var lastTick = 0.0
    private var width: CGFloat = 0
    private var height: CGFloat = 0
    private var lineHeight: CGFloat = 28
    private var topFree: [Double] = []
    private var bottomFree: [Double] = []
    private var scrollFree: [Double] = []

    init(config: DanmakuEngineConfig) { self.config = config.clamped() }

    func setConfig(_ value: DanmakuEngineConfig) { config = value.clamped() }

    func updateLayout(size: CGSize, isFullscreen: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let largest = ordered.map(\.fontSize).max() ?? 18
        let fullscreenRatio = config.fullscreenFontScale / max(config.fontScale, 0.01)
        let nextLineHeight = max(12, (isFullscreen ? largest * fullscreenRatio : largest) * config.lineHeightMultiplier)
        let nextTopCount = laneCount(height: size.height, lineHeight: nextLineHeight, ratio: config.topRegionRatio)
        let nextBottomCount = laneCount(height: size.height, lineHeight: nextLineHeight, ratio: config.bottomRegionRatio)
        guard width != size.width || height != size.height || lineHeight != nextLineHeight || topFree.count != nextTopCount || bottomFree.count != nextBottomCount else { return }
        width = size.width; height = size.height; lineHeight = nextLineHeight
        topFree = Array(repeating: 0, count: nextTopCount)
        bottomFree = Array(repeating: 0, count: nextBottomCount)
        scrollFree = Array(repeating: 0, count: nextTopCount)
    }

    func installWindow(_ elements: [Bilibili_Community_Service_Dm_V1_DanmakuElem], at currentTime: Double) {
        let prepared = prepare(elements)
        let nextByID = Dictionary(prepared.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let windowChanged = Set(itemsByID.keys) != Set(nextByID.keys)
        let newItems = nextByID.values.filter { itemsByID[$0.id] == nil }
        itemsByID = nextByID
        ordered = nextByID.values.sorted { lhs, rhs in
            lhs.appearTime == rhs.appearTime ? lhs.id < rhs.id : lhs.appearTime < rhs.appearTime
        }

        // A late protobuf response may contain items already on screen. Admit only live,
        // fully filtered items without resetting existing lanes or active labels.
        for item in newItems.sorted(by: { lhs, rhs in
            lhs.appearTime == rhs.appearTime ? lhs.id < rhs.id : lhs.appearTime < rhs.appearTime
        })
        where item.appearTime <= currentTime && currentTime < item.appearTime + item.duration {
            activate(item, at: currentTime)
            attemptedIDs.insert(item.id)
        }
        // updateUIView can run on every player-time observation. Advancing the
        // cursor here would skip items before CADisplayLink gets to activate them.
        // Rebase it only when a protobuf window actually changes.
        if windowChanged {
            cursor = ordered.partitioningIndex { $0.appearTime > lastTick }
        }
    }

    func rebuild(at time: Double) {
        activeItems.removeAll(); attemptedIDs.removeAll()
        topFree = Array(repeating: 0, count: topFree.count)
        bottomFree = Array(repeating: 0, count: bottomFree.count)
        scrollFree = Array(repeating: 0, count: scrollFree.count)
        let start = max(0, time - max(config.scrollDuration, config.staticDuration))
        for item in ordered where item.appearTime >= start && item.appearTime <= time {
            attemptedIDs.insert(item.id)
            // Replay the whole visible-duration horizon so lane occupancy stays
            // consistent even when an earlier static item has just expired.
            activate(item, at: time)
        }
        activeItems.removeAll { time >= $0.item.appearTime + $0.item.duration }
        lastTick = time
        cursor = ordered.partitioningIndex { $0.appearTime > time }
    }

    func tick(at time: Double) {
        guard width > 0, height > 0 else { return }
        activeItems.removeAll { time >= $0.item.appearTime + $0.item.duration }
        while cursor < ordered.count, ordered[cursor].appearTime <= time {
            let item = ordered[cursor]; cursor += 1
            guard !attemptedIDs.contains(item.id) else { continue }
            attemptedIDs.insert(item.id)
            guard time < item.appearTime + item.duration else { continue }
            activate(item, at: time)
        }
        lastTick = time
    }

    private func laneCount(height: CGFloat, lineHeight: CGFloat, ratio: Double) -> Int {
        max(1, Int(height * ratio / max(lineHeight, 1)))
    }

    private func activate(_ item: DanmakuPreparedItem, at _: Double) {
        let lanes: [Double]
        switch item.kind { case .scroll: lanes = scrollFree; case .top: lanes = topFree; case .bottom: lanes = bottomFree }
        guard !lanes.isEmpty else { return }
        let lane: Int
        if config.allowOverlapWhenMassive { lane = Int.random(in: 0 ..< lanes.count) }
        else if let available = lanes.firstIndex(where: { $0 <= item.appearTime }) { lane = available }
        else { return }
        if !config.allowOverlapWhenMassive {
            switch item.kind {
            case .scroll: scrollFree[lane] = item.appearTime + item.duration * min(max(item.width / max(width + item.width, 1), 0), 1)
            case .top: topFree[lane] = item.appearTime + item.duration
            case .bottom: bottomFree[lane] = item.appearTime + item.duration
            }
        }
        let y: CGFloat = item.kind == .bottom ? height - CGFloat(lane + 1) * lineHeight : CGFloat(lane) * lineHeight
        activeItems.append(DanmakuActiveItem(item: item, topY: y, lineHeight: lineHeight))
    }

    private func prepare(_ elements: [Bilibili_Community_Service_Dm_V1_DanmakuElem]) -> [DanmakuPreparedItem] {
        let c = config.clamped()
        var ids = Set<Int64>(); var result: [DanmakuPreparedItem] = []
        for element in elements where !element.content.isEmpty && ids.insert(element.id).inserted {
            guard element.weight >= Int32(c.blockLevel) else { continue }
            let kind = kind(for: Int(element.mode), forceScroll: c.forceAllScroll)
            guard !(c.blockScroll && kind == .scroll), !(c.blockTop && kind == .top), !(c.blockBottom && kind == .bottom), !(c.blockColorful && element.color != 16_777_215) else { continue }
            let fontSize = baseFontSize(Int(element.fontsize)) * c.fontScale
            let font = UIFont.systemFont(ofSize: fontSize, weight: c.uiFontWeight)
            let item = DanmakuPreparedItem(id: element.id, appearTime: max(0, Double(element.progress) / 1000), kind: kind, text: element.content, color: UIColor(rgb: Int(element.color)), duration: kind == .scroll ? c.scrollDuration : c.staticDuration, width: ceil((element.content as NSString).size(withAttributes: [.font: font]).width), fontSize: fontSize)
            result.append(item)
        }
        return result
    }

    private func kind(for mode: Int, forceScroll: Bool) -> DanmakuRenderKind { if forceScroll { return .scroll }; return mode == 4 ? .bottom : (mode == 5 ? .top : .scroll) }
    private func baseFontSize(_ value: Int) -> CGFloat { value < 25 ? 12 : (value < 36 ? 17 : 24) }
}

/// Renders an exterior alpha-mask outline, rather than stroking every glyph path.
private final class DanmakuOutlinedLabel: UILabel {
    var outlineWidth: CGFloat = 0
    var outlineColor: UIColor = .black
    private static let outlineContext = CIContext(options: nil)
    private var cachedOutline: UIImage?

    func invalidateOutlineCache() {
        cachedOutline = nil
    }

    override func drawText(in rect: CGRect) {
        guard outlineWidth > 0, let text = attributedText, rect.width > 0, rect.height > 0 else {
            super.drawText(in: rect)
            return
        }

        let canvas = CGRect(origin: .zero, size: bounds.size)
        if let cachedOutline {
            cachedOutline.draw(in: canvas)
            super.drawText(in: rect)
            return
        }

        let maskText = NSMutableAttributedString(attributedString: text)
        maskText.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: maskText.length))
        // Use UILabel itself for the mask. NSAttributedString.draw(in:) bypasses
        // UILabel's alignment and baseline layout, which‘ shifts centered text.
        let mask = UIGraphicsImageRenderer(size: canvas.size).image { _ in
            let maskLabel = UILabel(frame: canvas)
            maskLabel.attributedText = maskText
            maskLabel.textAlignment = textAlignment
            maskLabel.numberOfLines = numberOfLines
            maskLabel.lineBreakMode = lineBreakMode
            maskLabel.backgroundColor = .clear
            maskLabel.layer.render(in: UIGraphicsGetCurrentContext()!)
        }
        guard let input = CIImage(image: mask),
              let morphology = CIFilter(name: "CIMorphologyMaximum"),
              let colorMatrix = CIFilter(name: "CIColorMatrix")
        else {
            super.drawText(in: rect)
            return
        }

        morphology.setValue(input, forKey: kCIInputImageKey)
        morphology.setValue(outlineWidth * UIScreen.main.scale, forKey: kCIInputRadiusKey)
        guard let expanded = morphology.outputImage?.cropped(to: input.extent) else {
            super.drawText(in: rect)
            return
        }
        colorMatrix.setValue(expanded, forKey: kCIInputImageKey)
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: outlineColor.alphaComponent), forKey: "inputAVector")
        colorMatrix.setValue(CIVector(x: outlineColor.redComponent, y: outlineColor.greenComponent, z: outlineColor.blueComponent, w: 0), forKey: "inputBiasVector")
        if let image = colorMatrix.outputImage,
           let cgImage = Self.outlineContext.createCGImage(image, from: image.extent)
        {
            let outline = UIImage(cgImage: cgImage, scale: mask.scale, orientation: .up)
            cachedOutline = outline
            outline.draw(in: canvas)
        }
        super.drawText(in: rect)
    }
}

private extension UIColor {
    var redComponent: CGFloat { var red: CGFloat = 0; getRed(&red, green: nil, blue: nil, alpha: nil); return red }
    var greenComponent: CGFloat { var green: CGFloat = 0; getRed(nil, green: &green, blue: nil, alpha: nil); return green }
    var blueComponent: CGFloat { var blue: CGFloat = 0; getRed(nil, green: nil, blue: &blue, alpha: nil); return blue }
    var alphaComponent: CGFloat { var alpha: CGFloat = 0; getRed(nil, green: nil, blue: nil, alpha: &alpha); return alpha }
}

final class DanmakuUIKitOverlay: UIView {
    private let engine: DanmakuEngine
    private var displayLink: CADisplayLink?
    private var timeProvider: (() -> Double)?
    private var isPlayingProvider: (() -> Bool)?
    private var rateProvider: (() -> Double)?
    private var seekRevisionProvider: (() -> Int)?
    private var isFullscreen = false
    private var labels: [Int64: DanmakuOutlinedLabel] = [:]
    private var reusePool: [DanmakuOutlinedLabel] = []
    private var lastRate = 1.0
    private var lastSeekRevision = 0
    private var appliedConfig: DanmakuEngineConfig
    private var lastLaidOutSize: CGSize = .zero
    private var installedWindowStamp: DanmakuWindowStamp?

    init(config: DanmakuEngineConfig) { appliedConfig = config.clamped(); engine = DanmakuEngine(config: config); super.init(frame: .zero); isUserInteractionEnabled = false; clipsToBounds = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { displayLink?.invalidate() }

    func configure(player: MPVKitPlayer, elements: [Bilibili_Community_Service_Dm_V1_DanmakuElem], config: DanmakuEngineConfig, isFullscreen: Bool) {
        timeProvider = { player.currentTime }; isPlayingProvider = { player.isPlaying }; rateProvider = { player.playbackRate }; seekRevisionProvider = { player.playbackSeekRevision }
        let requiresRebuild = appliedConfig != config.clamped() || self.isFullscreen != isFullscreen
        self.isFullscreen = isFullscreen
        appliedConfig = config.clamped()
        engine.setConfig(config)
        let windowStamp = DanmakuWindowStamp(elements)
        if windowStamp != installedWindowStamp || requiresRebuild {
            engine.installWindow(elements, at: player.currentTime)
            installedWindowStamp = windowStamp
        }
        engine.updateLayout(size: bounds.size, isFullscreen: isFullscreen)
        if displayLink == nil || requiresRebuild {
            rebuild(at: player.currentTime)
            lastSeekRevision = player.playbackSeekRevision
        } else {
            syncLabels(at: player.currentTime, rate: player.playbackRate)
        }
        startDisplayLink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastLaidOutSize, let time = timeProvider?() else { return }
        lastLaidOutSize = bounds.size
        engine.updateLayout(size: bounds.size, isFullscreen: isFullscreen)
        rebuild(at: time)
    }

    private func startDisplayLink() { guard displayLink == nil else { return }; let link = CADisplayLink(target: self, selector: #selector(step)); link.add(to: .main, forMode: .common); displayLink = link }

    @objc private func step(_ link: CADisplayLink) {
        guard let time = timeProvider?(), let playing = isPlayingProvider?(), let rate = rateProvider?(), let seekRevision = seekRevisionProvider?() else { return }
        // MPV reports time at a different cadence than CADisplayLink. Existing
        // animations intentionally ignore that ordinary correction; a seek is the
        // only clock event that reconstructs their screen position.
        let didSeek = seekRevision != lastSeekRevision
        if didSeek || abs(rate - lastRate) > 0.001 { rebuild(at: time) }
        else if playing {
            resumeAnimations()
            engine.tick(at: time)
            syncLabels(at: time, rate: rate)
        }
        if !playing { pauseAnimations() }
        lastSeekRevision = seekRevision
        lastRate = max(rate, 0.01)
    }

    private func rebuild(at time: Double) { engine.rebuild(at: time); recycleAllLabels(); syncLabels(at: time, rate: max(rateProvider?() ?? 1, 0.01)) }

    private func syncLabels(at time: Double, rate: Double) {
        let active = engine.activeItems
        let ids = Set(active.map { $0.item.id })
        let expiredLabels = labels.filter { !ids.contains($0.key) }
        for (id, label) in expiredLabels {
            label.layer.removeAllAnimations()
            label.removeFromSuperview()
            labels.removeValue(forKey: id)
            reusePool.append(label)
        }
        for activeItem in active {
            let item = activeItem.item
            guard labels[item.id] == nil else { continue }
            let label = dequeueLabel()
            labels[item.id] = label
            addSubview(label)
            configure(label, for: item)
            position(label, for: activeItem, at: time, rate: rate)
        }
    }

    private func dequeueLabel() -> DanmakuOutlinedLabel { reusePool.popLast() ?? DanmakuOutlinedLabel() }
    private func recycleAllLabels() { for label in labels.values { label.layer.removeAllAnimations(); label.removeFromSuperview(); reusePool.append(label) }; labels.removeAll() }
    private func pauseAnimations() { for label in labels.values where label.layer.speed != 0 { let paused = label.layer.convertTime(CACurrentMediaTime(), from: nil); label.layer.speed = 0; label.layer.timeOffset = paused } }
    private func resumeAnimations() {
        for label in labels.values where label.layer.speed == 0 {
            let paused = label.layer.timeOffset
            label.layer.speed = 1
            label.layer.timeOffset = 0
            label.layer.beginTime = 0
            label.layer.beginTime = label.layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        }
    }

    private func configure(_ label: DanmakuOutlinedLabel, for item: DanmakuPreparedItem) {
        let config = appliedConfig
        let font = UIFont.systemFont(ofSize: item.fontSize * (isFullscreen ? config.fullscreenFontScale / max(config.fontScale, 0.01) : 1), weight: config.uiFontWeight)
        label.outlineWidth = config.strokeWidth
        label.outlineColor = UIColor.black.withAlphaComponent(config.opacity)
        label.attributedText = NSAttributedString(string: item.text, attributes: [.font: font, .foregroundColor: item.color.withAlphaComponent(config.opacity)])
        label.invalidateOutlineCache()
        label.textAlignment = .center; label.numberOfLines = 1
        let textSize = label.attributedText?.size() ?? .zero
        let padding = max(4, ceil(config.strokeWidth * 2))
        label.bounds = CGRect(x: 0, y: 0, width: ceil(textSize.width) + padding * 2, height: max(ceil(textSize.height) + padding * 2, 1))
    }

    private func position(_ label: DanmakuOutlinedLabel, for active: DanmakuActiveItem, at time: Double, rate: Double) {
        label.layer.removeAllAnimations(); label.layer.speed = 1; label.layer.timeOffset = 0
        let item = active.item; let y = active.topY + active.lineHeight / 2
        guard item.kind == .scroll else { label.center = CGPoint(x: bounds.midX, y: y); return }
        let progress = min(max((time - item.appearTime) / item.duration, 0), 1)
        let start = bounds.width - (bounds.width + label.bounds.width) * progress + label.bounds.width / 2
        let end = -label.bounds.width / 2
        label.center = CGPoint(x: end, y: y)
        let animation = CABasicAnimation(keyPath: "position.x"); animation.fromValue = start; animation.toValue = end; animation.duration = max((1 - progress) * item.duration / rate, 0.001); animation.timingFunction = CAMediaTimingFunction(name: .linear)
        label.layer.add(animation, forKey: "danmaku.scroll")
    }
}

struct DanmakuOverlayView: UIViewRepresentable {
    let player: MPVKitPlayer
    let elements: [Bilibili_Community_Service_Dm_V1_DanmakuElem]
    let config: DanmakuEngineConfig
    let isFullscreen: Bool

    func makeUIView(context: Context) -> DanmakuUIKitOverlay { DanmakuUIKitOverlay(config: config) }
    func updateUIView(_ uiView: DanmakuUIKitOverlay, context: Context) { uiView.isHidden = !config.isEnabled; guard config.isEnabled else { return }; uiView.configure(player: player, elements: elements, config: config, isFullscreen: isFullscreen) }
}

private extension UIColor {
    convenience init(rgb: Int) { self.init(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1) }
}

private extension Array {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Int { var low = 0; var high = count; while low < high { let mid = (low + high) / 2; if predicate(self[mid]) { high = mid } else { low = mid + 1 } }; return low }
}

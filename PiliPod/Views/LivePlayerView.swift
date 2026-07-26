//
//  LivePlayerView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/8.
//

import SwiftUI
#if canImport(UIKit)
import AVFAudio
import MediaPlayer
import UIKit
#endif

struct LivePlayerView: View {
    private enum DragInteractionMode {
        case none
        case brightnessAdjust
        case volumeAdjust
    }

    let roomId: String
    let streamURL: URL?
    let statusText: String
    let player: MPVKitPlayer
    let isFullscreen: Bool
    let safeAreaInsets: EdgeInsets

    @State private var dragInteractionMode: DragInteractionMode = .none
    @State private var isBrightnessAdjusting = false
    @State private var brightnessAdjustBaseValue: Double = 0
    @State private var brightnessPreviewValue: Double = 0
    @State private var isVolumeAdjusting = false
    @State private var volumeAdjustBaseValue: Double = 0
    @State private var volumePreviewValue: Double = 0
    @State private var systemVolumeControl = LivePlayerSystemVolumeController()

    private let verticalAdjustmentSensitivity: Double = 1.25

    private var topGestureExclusionHeight: CGFloat {
        isFullscreen ? max(18, safeAreaInsets.top + 8) : 14
    }

    private var bottomGestureExclusionHeight: CGFloat {
        isFullscreen ? max(18, safeAreaInsets.bottom + 8) : 14
    }

    var body: some View {
        GeometryReader { geo in
            let gestureHitAreaHeight = max(
                0,
                geo.size.height - topGestureExclusionHeight - bottomGestureExclusionHeight
            )

            ZStack {
                Group {
                    if let streamURL {
                        Group {
                            if player.usesAVPlayer {
                                AVPlayerSurfaceView(player: player)
                            } else {
                                MPVKitOpenGLPlayerView(player: player)
                            }
                        }
                            .task(id: streamURL.absoluteString) {
                                player.play(videoURL: streamURL)
                            }
                    } else {
                        ZStack {
                            Color.black
                            VStack(spacing: 8) {
                                Text(statusText)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }

                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .frame(height: gestureHitAreaHeight)
                    .simultaneousGesture(verticalAdjustmentGesture(containerSize: geo.size))
                    .allowsHitTesting(streamURL != nil && gestureHitAreaHeight > 0)

                if isBrightnessAdjusting {
                    valueHUD(systemName: "sun.max", value: brightnessPreviewValue)
                        .allowsHitTesting(false)
                }

                if isVolumeAdjusting {
                    valueHUD(
                        systemName: "speaker.wave.3",
                        value: volumePreviewValue,
                        variableValue: volumePreviewValue
                    )
                    .allowsHitTesting(false)
                }

                if let message = player.playbackError, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
                        .padding(20)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func verticalAdjustmentGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dy) > abs(dx) else { return }

                if dragInteractionMode == .brightnessAdjust {
                    let height = max(1, containerSize.height)
                    let delta = Double(-dy / height) * verticalAdjustmentSensitivity
                    let target = clampUnit(brightnessAdjustBaseValue + delta)
                    brightnessPreviewValue = target
                    setScreenBrightness(target)
                    return
                }

                if dragInteractionMode == .volumeAdjust {
                    let height = max(1, containerSize.height)
                    let delta = Double(-dy / height) * verticalAdjustmentSensitivity
                    let target = clampUnit(volumeAdjustBaseValue + delta)
                    volumePreviewValue = target
                    setSystemVolume(target)
                    return
                }

                if value.startLocation.x <= containerSize.width * 0.5 {
                    dragInteractionMode = .brightnessAdjust
                    isBrightnessAdjusting = true
                    brightnessAdjustBaseValue = currentScreenBrightness()
                    brightnessPreviewValue = brightnessAdjustBaseValue
                } else {
                    dragInteractionMode = .volumeAdjust
                    isVolumeAdjusting = true
                    volumeAdjustBaseValue = currentSystemVolume()
                    volumePreviewValue = volumeAdjustBaseValue
                }
            }
            .onEnded { _ in
                if isBrightnessAdjusting {
                    isBrightnessAdjusting = false
                }
                if isVolumeAdjusting {
                    isVolumeAdjusting = false
                }
                dragInteractionMode = .none
            }
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(0, value), 1)
    }

#if canImport(UIKit)
    private func currentScreenBrightness() -> Double {
        Double(UIScreen.main.brightness)
    }

    private func setScreenBrightness(_ value: Double) {
        UIScreen.main.brightness = CGFloat(clampUnit(value))
    }
#else
    private func currentScreenBrightness() -> Double { 0.5 }
    private func setScreenBrightness(_ value: Double) { _ = value }
#endif

    private func currentSystemVolume() -> Double {
        clampUnit(systemVolumeControl.currentVolume)
    }

    private func setSystemVolume(_ value: Double) {
        systemVolumeControl.setVolume(clampUnit(value))
    }

    private func valueHUD(
        systemName: String,
        value: Double,
        variableValue: Double? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemName, variableValue: variableValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            GeometryReader { valueGeo in
                let barWidth = max(1, valueGeo.size.width)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.24))
                        .frame(height: 4)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.95))
                        .frame(width: barWidth * clampUnit(value), height: 4)
                }
                .padding(.top, 2)
            }
            .frame(width: 100, height: 10)
        }
        .frame(height: 24, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.2)))
        .glassEffect(.clear, in: .capsule)
        .transition(.opacity)
    }
}

#Preview {
    LivePlayerView(
        roomId: "226000",
        streamURL: nil,
        statusText: "room id: 226000",
        player: MPVKitPlayer(),
        isFullscreen: false,
        safeAreaInsets: EdgeInsets()
    )
}

#if canImport(UIKit)
private struct LivePlayerSystemVolumeController {
    private let volumeView: MPVolumeView
    private let slider: UISlider?

    init() {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.isHidden = true
        volumeView = view
        slider = view.subviews.compactMap { $0 as? UISlider }.first
    }

    var currentVolume: Double {
        Double(AVAudioSession.sharedInstance().outputVolume)
    }

    func setVolume(_ value: Double) {
        slider?.setValue(Float(value), animated: false)
        slider?.sendActions(for: .valueChanged)
    }
}
#else
private struct LivePlayerSystemVolumeController {
    var currentVolume: Double { 0.5 }
    func setVolume(_ value: Double) {
        _ = value
    }
}
#endif

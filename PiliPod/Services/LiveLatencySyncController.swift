//
//  LiveLatencySyncController.swift
//  PiliPod
//

import Foundation
import Observation

/// Tunables for live catch-up. Everything is expressed in seconds of media and
/// is derived from the 3s HLS segment length Bilibili live streams use.
struct LiveLatencySyncConfiguration: Equatable {
    /// Minimum spacing between samples; the player publishes snapshots at ~30Hz.
    var sampleInterval: TimeInterval = 0.5
    /// Time constant of the exponential moving average over `ahead`. Long enough
    /// to flatten the 3s sawtooth caused by whole segments arriving at once.
    var smoothingTimeConstant: TimeInterval = 4
    /// Samples (post reset) required before the controller may speed up.
    var warmUpDuration: TimeInterval = 3
    /// Catch-up starts once the smoothed buffer margin exceeds this.
    var engageAhead: TimeInterval = 4
    /// Catch-up ends once the smoothed margin falls to this. Must be below
    /// `engageAhead`; the gap is the hysteresis band.
    var disengageAhead: TimeInterval = 3.5
    /// If the instantaneous margin drops below this, return to 1.0x at once.
    var safetyFloorAhead: TimeInterval = 3.0
    /// A rate is only used if the margin predicted after `lookahead` seconds at
    /// that rate stays above this value.
    var projectedFloorAhead: TimeInterval = 2.0
    var lookahead: TimeInterval = 5
    /// Minimum time between two speed-ups, and after any return to 1.0x before
    /// the next speed-up. Returning to 1.0x is never delayed by this.
    var minimumDwell: TimeInterval = 5
    /// Ascending ladder of rates; the first entry is normal speed.
    var rateLadder: [Double] = [1.0, 1.1, 1.25]
    /// Smoothed margin at which each ladder step above 1.0x becomes eligible.
    var rateThresholds: [TimeInterval] = [4, 7]
}

struct LiveLatencySyncDiagnostics: Equatable {
    enum Phase: Equatable {
        /// Paused, buffering or no stream: playback rate is held at 1.0x.
        case inactive
        case warmingUp
        case steady
        case catchingUp
        /// Margin got too small; held at 1.0x until the dwell time elapses.
        case safetyHold
    }

    var phase: Phase = .inactive
    var rawAhead: TimeInterval = 0
    var smoothedAhead: TimeInterval?
    var targetRate: Double = 1.0
    var rateChangeCount = 0
    var safetyResetCount = 0
    var lastRateChangeUptime: TimeInterval?
}

/// Keeps a live stream close to its newest content by nudging playback rate.
///
/// The input is `ahead = bufferedUntil - currentTime`, i.e. how much already
/// downloaded media is left before playback would run dry. Large `ahead` means
/// playback is lagging behind the newest segment; small `ahead` means catching
/// up further risks stalling.
@MainActor
@Observable
final class LiveLatencySyncController {
    private(set) var diagnostics = LiveLatencySyncDiagnostics()

    @ObservationIgnored private let configuration: LiveLatencySyncConfiguration
    @ObservationIgnored private var smoothedAhead: TimeInterval?
    @ObservationIgnored private var lastSampleUptime: TimeInterval?
    @ObservationIgnored private var activeSince: TimeInterval?
    @ObservationIgnored private var lastRateChangeUptime: TimeInterval?
    @ObservationIgnored private var currentRate = 1.0

    init(configuration: LiveLatencySyncConfiguration = LiveLatencySyncConfiguration()) {
        self.configuration = configuration
    }

    /// Clears all state; call when the stream, pause state or quality changes.
    func reset() {
        smoothedAhead = nil
        lastSampleUptime = nil
        activeSince = nil
        lastRateChangeUptime = nil
        currentRate = 1.0
        diagnostics = LiveLatencySyncDiagnostics(
            rateChangeCount: diagnostics.rateChangeCount,
            safetyResetCount: diagnostics.safetyResetCount
        )
    }

    /// Feeds one player snapshot. Returns the rate to apply when it differs
    /// from the one previously returned, otherwise `nil`.
    func update(
        currentTime: TimeInterval,
        bufferedUntil: TimeInterval,
        isPlaying: Bool,
        isBuffering: Bool,
        now: TimeInterval
    ) -> Double? {
        guard isPlaying, !isBuffering, bufferedUntil > currentTime else {
            return holdAtNormalSpeed(phase: .inactive, now: now)
        }

        // Safety is checked on every snapshot, before throttling or smoothing.
        let rawAhead = bufferedUntil - currentTime
        diagnostics.rawAhead = rawAhead
        if rawAhead < configuration.safetyFloorAhead {
            let changed = currentRate != 1.0
            if changed { diagnostics.safetyResetCount += 1 }
            lastRateChangeUptime = now
            diagnostics.phase = .safetyHold
            return applyRate(1.0, now: now, changed: changed)
        }

        if let lastSampleUptime, now - lastSampleUptime < configuration.sampleInterval {
            return nil
        }
        let elapsed = lastSampleUptime.map { now - $0 } ?? 0
        lastSampleUptime = now
        if activeSince == nil { activeSince = now }

        let smoothed: TimeInterval
        if let previous = smoothedAhead {
            let alpha = 1 - exp(-elapsed / configuration.smoothingTimeConstant)
            smoothed = previous + (rawAhead - previous) * alpha
        } else {
            smoothed = rawAhead
        }
        smoothedAhead = smoothed
        diagnostics.rawAhead = rawAhead
        diagnostics.smoothedAhead = smoothed

        guard now - (activeSince ?? now) >= configuration.warmUpDuration else {
            diagnostics.phase = .warmingUp
            return nil
        }

        let dwellElapsed = lastRateChangeUptime.map { now - $0 >= configuration.minimumDwell } ?? true
        let target = targetRate(smoothed: smoothed, dwellElapsed: dwellElapsed)
        diagnostics.phase = target > 1.0 ? .catchingUp : (dwellElapsed ? .steady : .safetyHold)
        if target == currentRate { return nil }
        return applyRate(target, now: now, changed: true)
    }

    private func targetRate(smoothed: TimeInterval, dwellElapsed: Bool) -> Double {
        let ladder = configuration.rateLadder
        guard ladder.count > 1 else { return 1.0 }

        // Slowing down is always allowed immediately.
        if currentRate > 1.0 {
            if smoothed <= configuration.disengageAhead { return 1.0 }
            // Inside the hysteresis band keep the current step, but step down
            // when the projected margin would get too thin.
            var rate = currentRate
            while rate > 1.0, projectedAhead(smoothed, rate: rate) < configuration.projectedFloorAhead {
                rate = ladder.last(where: { $0 < rate }) ?? 1.0
            }
            if rate == currentRate, dwellElapsed,
               let stepIndex = ladder.firstIndex(of: rate),
               stepIndex + 1 < ladder.count,
               stepIndex < configuration.rateThresholds.count,
               smoothed > configuration.rateThresholds[stepIndex],
               projectedAhead(smoothed, rate: ladder[stepIndex + 1]) >= configuration.projectedFloorAhead
            {
                return ladder[stepIndex + 1]
            }
            return rate
        }

        // Enter at the lowest step; later updates climb one step per dwell.
        guard dwellElapsed,
              smoothed > configuration.engageAhead,
              projectedAhead(smoothed, rate: ladder[1]) >= configuration.projectedFloorAhead
        else { return 1.0 }
        return ladder[1]
    }

    private func projectedAhead(_ ahead: TimeInterval, rate: Double) -> TimeInterval {
        ahead - (rate - 1.0) * configuration.lookahead
    }

    private func holdAtNormalSpeed(phase: LiveLatencySyncDiagnostics.Phase, now: TimeInterval) -> Double? {
        smoothedAhead = nil
        lastSampleUptime = nil
        activeSince = nil
        if diagnostics.phase != phase { diagnostics.phase = phase }
        if diagnostics.smoothedAhead != nil { diagnostics.smoothedAhead = nil }
        guard currentRate != 1.0 else { return nil }
        lastRateChangeUptime = now
        return applyRate(1.0, now: now, changed: true)
    }

    private func applyRate(_ rate: Double, now: TimeInterval, changed: Bool) -> Double? {
        diagnostics.targetRate = rate
        guard changed, rate != currentRate else { return nil }
        currentRate = rate
        lastRateChangeUptime = now
        diagnostics.lastRateChangeUptime = now
        diagnostics.rateChangeCount += 1
        return rate
    }
}

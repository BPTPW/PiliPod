//
//  LiveLatencySyncControllerTests.swift
//  PiliPodTests
//

import Foundation
@testable import PiliPod
import Testing

@MainActor
struct LiveLatencySyncControllerTests {
    private let currentTime: TimeInterval = 100

    /// Feeds a constant `ahead` every 0.1s and returns every rate change with its time.
    private func drive(
        _ controller: LiveLatencySyncController,
        ahead: (TimeInterval) -> TimeInterval,
        from start: TimeInterval = 0,
        duration: TimeInterval,
        isPlaying: Bool = true,
        isBuffering: Bool = false
    ) -> [(time: TimeInterval, rate: Double)] {
        var changes: [(TimeInterval, Double)] = []
        var t = start
        while t <= start + duration {
            if let rate = controller.update(
                currentTime: currentTime,
                bufferedUntil: currentTime + ahead(t),
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                now: t
            ) {
                changes.append((t, rate))
            }
            t += 0.1
        }
        return changes
    }

    @Test func steadyStateNeverChangesRate() {
        let controller = LiveLatencySyncController()
        // 3s sawtooth around a ~3.5s mean, as whole segments arrive.
        let changes = drive(controller, ahead: { 2 + $0.truncatingRemainder(dividingBy: 3) }, duration: 60)
        #expect(changes.isEmpty)
    }

    @Test func largeLagSpeedsUpOneStepAtATime() {
        let controller = LiveLatencySyncController()
        let changes = drive(controller, ahead: { _ in 8 }, duration: 20)
        #expect(changes.map(\.rate) == [1.1, 1.25])
        // Warm-up first, then at least the dwell time between steps.
        #expect(changes[0].time >= 3)
        #expect(changes[1].time - changes[0].time >= 5)
    }

    @Test func nothingHappensDuringWarmUp() {
        let controller = LiveLatencySyncController()
        let changes = drive(controller, ahead: { _ in 20 }, duration: 2.5)
        #expect(changes.isEmpty)
    }

    @Test func lowInstantMarginReturnsToNormalImmediately() {
        let controller = LiveLatencySyncController()
        _ = drive(controller, ahead: { _ in 8 }, duration: 5)
        _ = controller.update(
            currentTime: currentTime,
            bufferedUntil: currentTime + 8,
            isPlaying: true,
            isBuffering: false,
            now: 6
        )
        let rate = controller.update(
            currentTime: currentTime,
            bufferedUntil: currentTime + 2.99,
            isPlaying: true,
            isBuffering: false,
            now: 6.01
        )
        #expect(rate == 1.0)
        #expect(controller.diagnostics.safetyResetCount == 1)
        #expect(controller.diagnostics.phase == .safetyHold)
        #expect((controller.diagnostics.smoothedAhead ?? 0) > 4)
    }

    @Test func catchUpStartsOnlyAboveFourSmoothedSeconds() {
        let controller = LiveLatencySyncController()
        #expect(drive(controller, ahead: { _ in 4 }, duration: 10).isEmpty)
        let changes = drive(controller, ahead: { _ in 4.2 }, from: 10.1, duration: 10)
        #expect(changes.map(\.rate) == [1.1])
    }

    @Test func marginInsideHysteresisBandKeepsRate() {
        let controller = LiveLatencySyncController()
        _ = drive(controller, ahead: { _ in 5.6 }, duration: 6)
        #expect(controller.diagnostics.targetRate == 1.1)
        // 3.8s is below the engage threshold but above the disengage threshold.
        let changes = drive(controller, ahead: { _ in 3.8 }, from: 6.1, duration: 30)
        #expect(changes.isEmpty)
        #expect(controller.diagnostics.targetRate == 1.1)
    }

    @Test func pauseAndBufferingResetRateAndRequireWarmUp() {
        let controller = LiveLatencySyncController()
        _ = drive(controller, ahead: { _ in 8 }, duration: 6)
        let paused = controller.update(
            currentTime: currentTime,
            bufferedUntil: currentTime + 8,
            isPlaying: false,
            isBuffering: false,
            now: 6.2
        )
        #expect(paused == 1.0)
        #expect(controller.diagnostics.phase == .inactive)

        let resumed = drive(controller, ahead: { _ in 8 }, from: 7, duration: 2.5)
        #expect(resumed.isEmpty)
    }

    @Test func catchUpConvergesWithoutFlappingOrRunningDry() {
        let controller = LiveLatencySyncController()
        var rate = 1.0
        var ahead = 8.5
        var minAhead = ahead
        var changes = 0
        var t = 0.0
        let dt = 0.1
        while t < 120 {
            // Media is consumed at `rate`, arrives at 1x.
            ahead += (1 - rate) * dt
            minAhead = min(minAhead, ahead)
            if let new = controller.update(
                currentTime: currentTime,
                bufferedUntil: currentTime + ahead,
                isPlaying: true,
                isBuffering: false,
                now: t
            ) {
                rate = new
                changes += 1
            }
            t += dt
        }
        #expect(rate == 1.0)
        #expect(minAhead > 2)
        #expect(ahead < 5)
        #expect(changes <= 4)
    }
}

import Foundation
import Observation

/// One attempt, measured with a monotonic clock from the playback-link request.
@Observable
@MainActor
final class LiveStartupDiagnostics {
    struct Event: Identifiable, Equatable {
        let id: Int
        let label: String
        let elapsed: TimeInterval
        let duration: TimeInterval
    }

    private let startedAt = ProcessInfo.processInfo.systemUptime
    private(set) var events: [Event] = []
    private(set) var streamFormat: String?
    private(set) var firstFrameTime: TimeInterval?

    func mark(_ label: String) {
        guard firstFrameTime == nil else { return }
        let elapsed = max(ProcessInfo.processInfo.systemUptime - startedAt, 0)
        events.append(Event(id: events.count, label: label, elapsed: elapsed,
                            duration: max(elapsed - (events.last?.elapsed ?? 0), 0)))
    }

    func selectFormat(_ format: String) {
        streamFormat = format
    }

    func recordFirstFrame() {
        guard firstFrameTime == nil else { return }
        mark("首帧可显示")
        firstFrameTime = events.last?.elapsed
    }
}

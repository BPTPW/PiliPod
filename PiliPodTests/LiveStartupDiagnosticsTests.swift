import Foundation
@testable import PiliPod
import Testing

@MainActor
struct LiveStartupDiagnosticsTests {
    @Test func firstFrameFreezesTimelineAndTotal() throws {
        let diagnostics = LiveStartupDiagnostics()
        diagnostics.selectFormat("fmp4")
        diagnostics.mark("开始获取播放链接")
        diagnostics.mark("播放器准备完成")
        diagnostics.recordFirstFrame()
        let events = diagnostics.events
        let total = try #require(diagnostics.firstFrameTime)
        diagnostics.recordFirstFrame()
        diagnostics.mark("播放器准备完成")
        #expect(diagnostics.events == events)
        #expect(diagnostics.firstFrameTime == total)
        #expect(diagnostics.streamFormat == "fmp4")
        #expect(events.last?.label == "首帧可显示")
        #expect(abs(events.reduce(0) { $0 + $1.duration } - total) < 0.000001)
    }

    @Test func eachAttemptHasIndependentTimelineAndFormat() {
        let first = LiveStartupDiagnostics()
        first.selectFormat("fmp4")
        first.recordFirstFrame()
        let second = LiveStartupDiagnostics()
        #expect(second.firstFrameTime == nil)
        #expect(second.events.isEmpty)
        #expect(second.streamFormat == nil)
        second.selectFormat("ts")
        second.mark("开始获取播放链接")
        #expect(second.events.first?.id == 0)
        #expect(second.streamFormat == "ts")
        #expect(first.streamFormat == "fmp4")
    }
}

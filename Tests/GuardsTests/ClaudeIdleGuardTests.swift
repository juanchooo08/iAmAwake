import Foundation
import Testing

import AwakeCore
@testable import Guards

private final class MockActivity: ClaudeActivityReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _active: Bool
    init(active: Bool) { _active = active }
    var active: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _active }
        set { lock.lock(); _active = newValue; lock.unlock() }
    }
    func isActive() -> Bool { active }
}

private let limit = TimeInterval(PreferencesSnapshot.claudeIdleSeconds)
private let idleVerdict = GuardVerdict.mustDisarm(.claudeIdle(afterSeconds: PreferencesSnapshot.claudeIdleSeconds))

private func makeGuard(active: Bool, enabled: Bool = true)
    -> (ClaudeIdleGuard, MockActivity, FakeClock, ManualScheduler) {
    let activity = MockActivity(active: active)
    let clock = FakeClock()
    let scheduler = ManualScheduler()
    let g = ClaudeIdleGuard(
        reader: activity,
        preferences: PreferencesSnapshot(claudeGuardEnabled: enabled),
        clock: clock,
        scheduler: scheduler
    )
    return (g, activity, clock, scheduler)
}

@Suite("ClaudeIdleGuard")
struct ClaudeIdleGuardTests {
    @Test func idleLongerThanLimitDisarms() {
        let (g, _, clock, _) = makeGuard(active: false)
        clock.advance(limit - 1)
        #expect(g.currentVerdict == .ok)
        clock.advance(1)
        #expect(g.currentVerdict == idleVerdict)
    }

    @Test func activityResetsTheCount() {
        let (g, activity, clock, _) = makeGuard(active: true)
        clock.advance(limit * 3)
        #expect(g.currentVerdict == .ok)
        activity.active = false
        clock.advance(limit - 1)
        #expect(g.currentVerdict == .ok)
    }

    @Test func armingRestartsTheCount() {
        let (g, _, clock, _) = makeGuard(active: false)
        clock.advance(limit * 2)
        #expect(g.currentVerdict == idleVerdict)
        g.didArm()
        #expect(g.currentVerdict == .ok)
    }

    @Test func disabledNeverDisarms() {
        let (g, _, clock, _) = makeGuard(active: false, enabled: false)
        clock.advance(limit * 10)
        #expect(g.currentVerdict == .ok)
    }

    @Test func pollingEmitsWhenTheLimitPasses() {
        let (g, _, clock, scheduler) = makeGuard(active: false)
        let recorder = VerdictRecorder()
        g.start(onVerdict: recorder.sink)
        clock.advance(limit)
        scheduler.fire()
        #expect(recorder.last == idleVerdict)
        g.stop()
    }
}

@Suite("ClaudeSessionMarkerReader")
struct ClaudeSessionMarkerReaderTests {
    @Test func freshMarkerIsActiveStaleOrMissingIsNot() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-markers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = ClaudeSessionMarkerReader(directory: dir, staleAfter: 1200)

        #expect(reader.isActive() == false)  // directorio inexistente

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let marker = dir.appendingPathComponent("session")
        FileManager.default.createFile(atPath: marker.path, contents: nil)
        #expect(reader.isActive())

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-1300)], ofItemAtPath: marker.path)
        #expect(reader.isActive() == false)
    }
}

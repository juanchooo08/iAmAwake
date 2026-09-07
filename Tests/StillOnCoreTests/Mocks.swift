import Foundation
@testable import StillOnCore

final class MockInhibitor: SleepInhibiting, @unchecked Sendable {
    var isEngaged = false
    var engageCount = 0
    var disengageCount = 0
    var errorToThrow: StillOnError?

    func engage() async throws {
        engageCount += 1
        if let e = errorToThrow { throw e }
        isEngaged = true
    }
    func disengage() async {
        disengageCount += 1
        isEngaged = false
    }
}

final class MockLid: LidSleepControlling, @unchecked Sendable {
    var disabledCalls: [Bool] = []
    var heartbeatCount = 0
    var errorToThrow: StillOnError?
    var heartbeatError: StillOnError?
    var state: HelperInstallState = .ready(protocolVersion: Wire.protocolVersion)

    var installState: HelperInstallState { get async { state } }

    func setClamshellSleepDisabled(_ disabled: Bool) async throws {
        if let e = errorToThrow, disabled { throw e }
        disabledCalls.append(disabled)
    }
    func heartbeat() async throws {
        heartbeatCount += 1
        if let e = heartbeatError { throw e }
    }
}

final class MockGuard: Guarding, @unchecked Sendable {
    let identifier: GuardID
    var currentVerdict: GuardVerdict
    var appliedPrefs: PreferencesSnapshot?
    var stopped = false
    private var callback: (@Sendable (GuardVerdict) -> Void)?

    init(_ id: GuardID, verdict: GuardVerdict = .ok) {
        self.identifier = id
        self.currentVerdict = verdict
    }
    func start(onVerdict: @escaping @Sendable (GuardVerdict) -> Void) { callback = onVerdict }
    func stop() { stopped = true }
    func apply(_ prefs: PreferencesSnapshot) { appliedPrefs = prefs }
    func emit(_ v: GuardVerdict) { currentVerdict = v; callback?(v) }
}

final class MockPreferences: PreferencesStoring, @unchecked Sendable {
    var snapshot = PreferencesSnapshot()
    func update(_ transform: @Sendable (inout PreferencesSnapshot) -> Void) {
        transform(&snapshot)
        snapshot = snapshot.clamped()
    }
    var changes: AsyncStream<PreferencesSnapshot> { AsyncStream { $0.finish() } }
}

final class MockNotifier: Notifying, @unchecked Sendable {
    var disarmReasons: [DisarmReason] = []
    var failures: [StillOnError] = []
    var authRequested = false

    func requestAuthorizationIfNeeded() async { authRequested = true }
    func notifyDisarmed(reason: DisarmReason) async { disarmReasons.append(reason) }
    func notifyFailure(_ error: StillOnError) async { failures.append(error) }
}

struct FixedClock: ClockProviding {
    let now: Date
    init(_ t: TimeInterval = 0) { now = Date(timeIntervalSince1970: t) }
}

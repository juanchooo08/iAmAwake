import Foundation
import AwakeCore

/// Desarma cuando ninguna sesion de Claude Code trabajo durante
/// `PreferencesSnapshot.claudeIdleSeconds`.
///
/// Reglas:
/// 1. `claudeGuardEnabled == false` → `.ok` siempre.
/// 2. Cada consulta al lector que da activo reinicia la cuenta.
/// 3. Armar tambien la reinicia (`didArm`): se puede armar antes de lanzar la
///    sesion y hay margen para empezar.
/// 4. Inactiva por mas del margen → `.mustDisarm(.claudeIdle)`.
///
/// La actividad no tiene evento propio, asi que se consulta cada
/// `pollInterval` con un `DelayScheduling`, igual que el margen de la red.
public final class ClaudeIdleGuard: Guarding, @unchecked Sendable {
    public let identifier: GuardID = .claude

    private let reader: ClaudeActivityReading
    private let clock: ClockProviding
    private let scheduler: DelayScheduling
    private let pollInterval: TimeInterval
    private let box: GuardBox<TimeInterval>
    private let lock = NSLock()
    private var lastActive: Date

    public init(
        reader: ClaudeActivityReading,
        preferences: PreferencesSnapshot,
        clock: ClockProviding = SystemClock(),
        scheduler: DelayScheduling = DispatchDelayScheduler(),
        pollInterval: TimeInterval = 60
    ) {
        self.reader = reader
        self.clock = clock
        self.scheduler = scheduler
        self.pollInterval = pollInterval
        self.lastActive = clock.now
        self.box = GuardBox(value: 0, prefs: preferences, evaluate: Self.evaluate)
    }

    public var currentVerdict: GuardVerdict { box.verdict(for: idleSeconds()) }

    public func start(onVerdict: @escaping @Sendable (GuardVerdict) -> Void) {
        guard box.begin(onVerdict: onVerdict) else { return }
        poll()
    }

    public func stop() {
        guard box.end() else { return }
        scheduler.cancelPending()
    }

    public func apply(_ prefs: PreferencesSnapshot) {
        if let (callback, verdict) = box.apply(prefs) {
            callback(verdict)
        }
    }

    public func didArm() {
        lock.lock()
        lastActive = clock.now
        lock.unlock()
    }

    // MARK: - Privado

    private func poll() {
        if let (callback, verdict) = box.update(value: idleSeconds()) {
            callback(verdict)
        }
        scheduler.schedule(after: pollInterval) { [weak self] in
            guard let self, self.box.isRunning else { return }
            self.poll()
        }
    }

    private func idleSeconds() -> TimeInterval {
        let active = reader.isActive()
        lock.lock()
        defer { lock.unlock() }
        if active { lastActive = clock.now }
        return max(clock.now.timeIntervalSince(lastActive), 0)
    }

    static let evaluate: @Sendable (TimeInterval, PreferencesSnapshot) -> GuardVerdict = {
        idle, prefs in
        guard prefs.claudeGuardEnabled else { return .ok }
        let limit = PreferencesSnapshot.claudeIdleSeconds
        guard idle >= TimeInterval(limit) else { return .ok }
        return .mustDisarm(.claudeIdle(afterSeconds: limit))
    }
}

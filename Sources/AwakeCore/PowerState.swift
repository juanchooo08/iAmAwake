import Foundation

/// Fuente unica de verdad. Nadie mas muta el estado armado/desarmado.
@MainActor
public final class PowerState: ObservableObject {
    @Published public private(set) var status: ArmState = .disarmed
    @Published public private(set) var lastError: AwakeError?

    private let inhibitor: SleepInhibiting
    private let lid: LidSleepControlling
    private let guards: [Guarding]
    private let preferences: PreferencesStoring
    private let notifier: Notifying
    private let clock: ClockProviding

    private var verdicts: [GuardID: GuardVerdict] = [:]

    public init(
        inhibitor: SleepInhibiting,
        lid: LidSleepControlling,
        guards: [Guarding],
        preferences: PreferencesStoring,
        notifier: Notifying,
        clock: ClockProviding = SystemClock()
    ) {
        self.inhibitor = inhibitor
        self.lid = lid
        self.guards = guards
        self.preferences = preferences
        self.notifier = notifier
        self.clock = clock
        for g in guards { verdicts[g.identifier] = g.currentVerdict }
    }

    // MARK: - Intenciones

    public func toggle() async {
        if status.isArmed { await requestDisarm(reason: .user) } else { await requestArm() }
    }

    public func requestArm() async {
        guard !status.isArmed else { return }

        if let blocking = firstBlockingReason() {
            status = blockedState(for: blocking)
            await notifier.notifyDisarmed(reason: blocking)
            return
        }

        do {
            try await inhibitor.engage()
        } catch let error as AwakeError {
            await fail(error)
            return
        } catch {
            await fail(.assertionFailed(0))
            return
        }

        // El cierre de tapa depende del daemon. Si no esta, seguimos armados
        // pero degradados: el usuario tiene que enterarse (requisito 8).
        do {
            try await lid.setClamshellSleepDisabled(true)
            lastError = nil
        } catch let error as AwakeError {
            lastError = error
            await notifier.notifyFailure(error)
        } catch {
            lastError = .helperUnavailable
            await notifier.notifyFailure(.helperUnavailable)
        }

        status = .armed
    }

    public func requestDisarm(reason: DisarmReason) async {
        let wasArmed = status.isArmed
        await inhibitor.disengage()
        try? await lid.setClamshellSleepDisabled(false)

        switch reason {
        case .user, .appTerminating:
            status = .disarmed
        case .lowBattery, .thermal:
            status = blockedState(for: reason)
        case .assertionFailure(let e):
            status = .failed(e)
            lastError = e
        }

        if wasArmed, reason != .user, reason != .appTerminating {
            await notifier.notifyDisarmed(reason: reason)
        }
    }

    /// Una guarda cambio de opinion.
    public func report(_ verdict: GuardVerdict, from id: GuardID) async {
        verdicts[id] = verdict

        if case .mustDisarm(let reason) = verdict, status.isArmed {
            await requestDisarm(reason: reason)
            return
        }

        // La condicion se normalizo: salimos del estado bloqueado pero NO
        // rearmamos solos. Rearmar tras un corte termico produce ciclos.
        if verdict == .ok, isBlocked(status), firstBlockingReason() == nil {
            status = .disarmed
        }
    }

    /// La llama el timer del AppDelegate mientras estamos armados.
    public func heartbeatTick() async {
        guard status.isArmed else { return }
        do {
            try await lid.heartbeat()
            if lastError == .helperUnavailable { lastError = nil }
        } catch let error as AwakeError {
            lastError = error
            await notifier.notifyFailure(error)
        } catch {
            lastError = .helperUnavailable
        }
    }

    public func applyPreferences(_ snapshot: PreferencesSnapshot) async {
        let clamped = snapshot.clamped()
        for g in guards {
            g.apply(clamped)
            verdicts[g.identifier] = g.currentVerdict
        }
        if status.isArmed, let blocking = firstBlockingReason() {
            await requestDisarm(reason: blocking)
        }
    }

    // MARK: - Helpers

    private func firstBlockingReason() -> DisarmReason? {
        for g in guards {
            if let reason = (verdicts[g.identifier] ?? .ok).blockingReason { return reason }
        }
        return nil
    }

    private func blockedState(for reason: DisarmReason) -> ArmState {
        switch reason {
        case .lowBattery(let p): return .blockedLowBattery(percent: p)
        case .thermal(let l): return .blockedThermal(l)
        case .assertionFailure(let e): return .failed(e)
        case .user, .appTerminating: return .disarmed
        }
    }

    private func isBlocked(_ s: ArmState) -> Bool {
        switch s {
        case .blockedLowBattery, .blockedThermal, .failed: return true
        case .armed, .disarmed: return false
        }
    }

    private func fail(_ error: AwakeError) async {
        await inhibitor.disengage()
        try? await lid.setClamshellSleepDisabled(false)
        status = .failed(error)
        lastError = error
        await notifier.notifyFailure(error)
    }
}

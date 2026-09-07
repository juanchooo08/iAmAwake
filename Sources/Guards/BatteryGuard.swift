import Foundation
import StillOnCore

/// Desarma cuando la bateria cae al umbral configurado.
///
/// Reglas, en este orden:
/// 1. `batteryGuardEnabled == false` → `.ok` siempre.
/// 2. `isOnAC == true` → `.ok` siempre. Desarmar enchufado no protege nada.
/// 3. Con bateria y `percent <= batteryThreshold` → `.mustDisarm(.lowBattery)`.
///
/// El lector se inyecta por `init`. Este tipo nunca instancia `IOPowerSourcesReader`
/// por su cuenta: los tests le pasan un mock y no tocan IOKit.
public final class BatteryGuard: Guarding, @unchecked Sendable {
    public let identifier: GuardID = .battery

    private let reader: PowerSourceReading
    private let box: GuardBox<PowerSnapshot>

    public init(reader: PowerSourceReading, preferences: PreferencesSnapshot) {
        self.reader = reader
        self.box = GuardBox(value: reader.snapshot, prefs: preferences, evaluate: Self.evaluate)
    }

    public var currentVerdict: GuardVerdict { box.verdict(for: reader.snapshot) }

    public func start(onVerdict: @escaping @Sendable (GuardVerdict) -> Void) {
        guard box.begin(onVerdict: onVerdict) else { return }
        let box = self.box
        reader.startMonitoring { snapshot in
            if let (callback, verdict) = box.update(value: snapshot) {
                callback(verdict)
            }
        }
    }

    public func stop() {
        guard box.end() else { return }
        reader.stopMonitoring()
    }

    public func apply(_ prefs: PreferencesSnapshot) {
        if let (callback, verdict) = box.apply(prefs) {
            callback(verdict)
        }
    }

    static let evaluate: @Sendable (PowerSnapshot, PreferencesSnapshot) -> GuardVerdict = {
        snapshot, prefs in
        guard prefs.batteryGuardEnabled else { return .ok }
        guard !snapshot.isOnAC else { return .ok }
        guard snapshot.percent <= prefs.batteryThreshold else { return .ok }
        return .mustDisarm(.lowBattery(percent: snapshot.percent))
    }
}

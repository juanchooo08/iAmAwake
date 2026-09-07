import Foundation
import StillOnCore

/// Desarma cuando el nivel termico alcanza el techo configurado.
///
/// Reglas:
/// 1. `thermalGuardEnabled == false` → `.ok` siempre.
/// 2. `level >= thermalCeiling` → `.mustDisarm(.thermal(level))`.
/// 3. Si no → `.ok`.
///
/// `ThermalLevel` es `Comparable` sobre su `rawValue` ordenado
/// nominal < fair < serious < critical, asi que la comparacion es directa.
public final class ThermalGuard: Guarding, @unchecked Sendable {
    public let identifier: GuardID = .thermal

    private let reader: ThermalReading
    private let box: GuardBox<ThermalLevel>

    public init(reader: ThermalReading, preferences: PreferencesSnapshot) {
        self.reader = reader
        self.box = GuardBox(value: reader.level, prefs: preferences, evaluate: Self.evaluate)
    }

    public var currentVerdict: GuardVerdict { box.verdict(for: reader.level) }

    public func start(onVerdict: @escaping @Sendable (GuardVerdict) -> Void) {
        guard box.begin(onVerdict: onVerdict) else { return }
        let box = self.box
        reader.startMonitoring { level in
            if let (callback, verdict) = box.update(value: level) {
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

    static let evaluate: @Sendable (ThermalLevel, PreferencesSnapshot) -> GuardVerdict = {
        level, prefs in
        guard prefs.thermalGuardEnabled else { return .ok }
        guard level >= prefs.thermalCeiling else { return .ok }
        return .mustDisarm(.thermal(level))
    }
}

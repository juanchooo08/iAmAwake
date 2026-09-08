import Foundation
import AwakeCore

/// Persistencia de `PreferencesSnapshot` en `UserDefaults`.
///
/// Cada campo se guarda como un primitivo suelto (no un blob `Codable`) para que
/// un valor corrupto o de una version vieja degrade a su default en vez de tirar
/// abajo el snapshot entero.
public final class UserDefaultsPreferencesStore: PreferencesStoring, @unchecked Sendable {

    public static let suiteName = "dev.local.iamawake"

    enum Key {
        static let batteryThreshold = "batteryThreshold"
        static let thermalCeiling = "thermalCeiling"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let curtainHotkeyKeyCode = "curtainHotkeyKeyCode"
        static let curtainHotkeyModifiers = "curtainHotkeyModifiers"
        static let batteryGuardEnabled = "batteryGuardEnabled"
        static let thermalGuardEnabled = "thermalGuardEnabled"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var current: PreferencesSnapshot
    private var continuations: [UUID: AsyncStream<PreferencesSnapshot>.Continuation] = [:]

    /// - Parameter defaults: inyectable para que los tests usen una suite efimera.
    ///   El default es la suite real del usuario.
    public init(defaults: UserDefaults? = nil) {
        let store = defaults ?? UserDefaults(suiteName: Self.suiteName) ?? .standard
        self.defaults = store
        self.current = Self.load(from: store)
    }

    public var snapshot: PreferencesSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func update(_ transform: @Sendable (inout PreferencesSnapshot) -> Void) {
        lock.lock()
        var next = current
        transform(&next)
        next = next.clamped()
        current = next
        Self.persist(next, to: defaults)
        let targets = Array(continuations.values)
        lock.unlock()

        for continuation in targets { continuation.yield(next) }
    }

    /// Cada acceso devuelve un stream independiente; todos reciben todos los eventos.
    public var changes: AsyncStream<PreferencesSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    /// Cierra los streams abiertos. Util en tests y al apagar la app.
    public func finish() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets { continuation.finish() }
    }

    // MARK: - Serializacion

    private static func load(from defaults: UserDefaults) -> PreferencesSnapshot {
        let fallback = PreferencesSnapshot()

        var snapshot = PreferencesSnapshot(
            batteryThreshold: int(defaults, Key.batteryThreshold) ?? fallback.batteryThreshold,
            thermalCeiling: thermal(defaults) ?? fallback.thermalCeiling,
            hotkey: hotkey(defaults) ?? fallback.hotkey,
            curtainHotkey: combo(defaults, Key.curtainHotkeyKeyCode, Key.curtainHotkeyModifiers)
                ?? fallback.curtainHotkey,
            batteryGuardEnabled: bool(defaults, Key.batteryGuardEnabled) ?? fallback.batteryGuardEnabled,
            thermalGuardEnabled: bool(defaults, Key.thermalGuardEnabled) ?? fallback.thermalGuardEnabled
        )
        snapshot = snapshot.clamped()
        return snapshot
    }

    private static func persist(_ snapshot: PreferencesSnapshot, to defaults: UserDefaults) {
        defaults.set(snapshot.batteryThreshold, forKey: Key.batteryThreshold)
        defaults.set(snapshot.thermalCeiling.rawValue, forKey: Key.thermalCeiling)
        defaults.set(Int(snapshot.hotkey.keyCode), forKey: Key.hotkeyKeyCode)
        defaults.set(Int(snapshot.hotkey.modifiers), forKey: Key.hotkeyModifiers)
        defaults.set(Int(snapshot.curtainHotkey.keyCode), forKey: Key.curtainHotkeyKeyCode)
        defaults.set(Int(snapshot.curtainHotkey.modifiers), forKey: Key.curtainHotkeyModifiers)
        defaults.set(snapshot.batteryGuardEnabled, forKey: Key.batteryGuardEnabled)
        defaults.set(snapshot.thermalGuardEnabled, forKey: Key.thermalGuardEnabled)
    }

    /// Solo acepta numeros reales. Un `String`, un `Data` o un diccionario dan `nil`
    /// (a diferencia de `defaults.integer(forKey:)`, que devuelve 0 silenciosamente).
    private static func int(_ defaults: UserDefaults, _ key: String) -> Int? {
        guard let raw = defaults.object(forKey: key) else { return nil }
        if let number = raw as? NSNumber, !(raw is String) { return number.intValue }
        return nil
    }

    private static func bool(_ defaults: UserDefaults, _ key: String) -> Bool? {
        guard let raw = defaults.object(forKey: key) else { return nil }
        if let number = raw as? NSNumber, !(raw is String) { return number.boolValue }
        return nil
    }

    private static func thermal(_ defaults: UserDefaults) -> ThermalLevel? {
        guard let raw = int(defaults, Key.thermalCeiling) else { return nil }
        return ThermalLevel(rawValue: raw)
    }

    private static func hotkey(_ defaults: UserDefaults) -> HotkeyCombo? {
        combo(defaults, Key.hotkeyKeyCode, Key.hotkeyModifiers)
    }

    private static func combo(
        _ defaults: UserDefaults,
        _ codeKey: String,
        _ modsKey: String
    ) -> HotkeyCombo? {
        guard let code = int(defaults, codeKey),
              let mods = int(defaults, modsKey),
              code >= 0, code <= Int(UInt32.max),
              mods >= 0, mods <= Int(UInt32.max)
        else { return nil }
        return HotkeyCombo(keyCode: UInt32(code), modifiers: UInt32(mods))
    }
}

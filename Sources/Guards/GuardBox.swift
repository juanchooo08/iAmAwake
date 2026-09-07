import Foundation
import StillOnCore

/// Estado mutable compartido por `BatteryGuard` y `ThermalGuard`.
///
/// Los dos guards siguen el mismo patron: leer una fuente, comparar contra un
/// umbral de `PreferencesSnapshot`, emitir veredicto. Lo unico que cambia es el
/// tipo de la lectura y la funcion de evaluacion, asi que eso es lo unico que se
/// parametriza aca.
///
/// Serializa con `NSLock` porque `Guarding` es `Sendable` y los callbacks de
/// IOKit / NotificationCenter llegan en hilos arbitrarios. Ninguna mutacion
/// invoca al cliente con el lock tomado: los metodos devuelven el trabajo
/// pendiente y el llamante lo ejecuta afuera.
final class GuardBox<Value: Sendable>: @unchecked Sendable {
    typealias Evaluator = @Sendable (Value, PreferencesSnapshot) -> GuardVerdict
    typealias Emission = (callback: @Sendable (GuardVerdict) -> Void, verdict: GuardVerdict)

    private let lock = NSLock()
    private let evaluate: Evaluator

    private var value: Value
    private var prefs: PreferencesSnapshot
    private var onVerdict: (@Sendable (GuardVerdict) -> Void)?
    private var lastVerdict: GuardVerdict

    init(value: Value, prefs: PreferencesSnapshot, evaluate: @escaping Evaluator) {
        self.value = value
        self.prefs = prefs
        self.evaluate = evaluate
        self.lastVerdict = evaluate(value, prefs)
    }

    /// Evalua contra un valor recien leido de la fuente. Se usa cuando nadie
    /// llamo a `start()` todavia: sin esto el box informaria el valor con el que
    /// se construyo, y una guarda que dice `.ok` con la bateria al 1% no sirve.
    func verdict(for freshValue: Value) -> GuardVerdict {
        lock.lock()
        defer { lock.unlock() }
        value = freshValue
        return evaluate(freshValue, prefs)
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return onVerdict != nil
    }

    /// Registra el callback. Devuelve `false` si ya estaba corriendo, para que el
    /// guard no vuelva a suscribirse a la fuente (`start` es idempotente).
    func begin(onVerdict: @escaping @Sendable (GuardVerdict) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.onVerdict == nil else { return false }
        self.onVerdict = onVerdict
        // El veredicto vigente es la linea base: `start` no emite por si solo.
        // Quien necesite el estado inicial usa `currentVerdict`.
        self.lastVerdict = evaluate(value, prefs)
        return true
    }

    /// Suelta el callback. Devuelve `false` si ya estaba detenido.
    func end() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard onVerdict != nil else { return false }
        onVerdict = nil
        return true
    }

    func update(value newValue: Value) -> Emission? {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
        return pendingEmissionLocked()
    }

    func apply(_ newPrefs: PreferencesSnapshot) -> Emission? {
        lock.lock()
        defer { lock.unlock() }
        prefs = newPrefs
        return pendingEmissionLocked()
    }

    /// Emite solo cuando el veredicto cambia de verdad. Un cambio de fuente que
    /// no cruza el umbral no despierta a `PowerState`, y un mismo veredicto
    /// repetido no puede realimentar un bucle de desarme.
    private func pendingEmissionLocked() -> Emission? {
        let verdict = evaluate(value, prefs)
        guard verdict != lastVerdict, let callback = onVerdict else {
            lastVerdict = verdict
            return nil
        }
        lastVerdict = verdict
        return (callback, verdict)
    }
}

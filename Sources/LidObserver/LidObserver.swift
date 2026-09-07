import AwakeCore
import Foundation

/// Convierte el ruido del IORegistry en transiciones limpias de tapa.
///
/// Dos responsabilidades, las dos por las que existe esta clase y no se habla
/// directo con IOKit:
///
/// 1. **Dedupe.** La notificacion de interes dispara ante cualquier cambio de
///    propiedad de `IOPMrootDomain`, no solo la tapa. Se relee y se emite solo
///    si el valor cambio de verdad.
/// 2. **Sin cache mentiroso.** `state` relee la fuente cada vez. Un getter que
///    devuelve el ultimo valor visto miente justo cuando importa: cuando nadie
///    llamo a `startMonitoring` todavia.
public final class LidObserver: LidObserving, @unchecked Sendable {
    private let source: ClamshellSource
    private let lock = NSLock()
    private var lastKnown: LidState
    private var onChange: (@Sendable (LidState) -> Void)?

    public init(source: ClamshellSource) {
        self.source = source
        self.lastKnown = source.read() ?? .open
    }

    /// Relee la fuente. Si el IORegistry no contesta, cae al ultimo valor visto
    /// en vez de inventar `.open`: inventar `.open` haria que la animacion de
    /// apertura dispare sola.
    public var state: LidState {
        guard let fresh = source.read() else { return snapshotLastKnown() }
        return fresh
    }

    public func startMonitoring(onChange: @escaping @Sendable (LidState) -> Void) {
        lock.lock()
        self.onChange = onChange
        self.lastKnown = source.read() ?? lastKnown
        lock.unlock()

        source.subscribe { [weak self] in self?.handleAnyChange() }
    }

    public func stopMonitoring() {
        source.unsubscribe()
        lock.lock()
        onChange = nil
        lock.unlock()
    }

    // MARK: - Privado

    /// Sincrona a proposito: Swift 6 prohibe `NSLock.lock()` dentro de una funcion
    /// async, y esto lo llama un callback de C.
    private func handleAnyChange() {
        guard let fresh = source.read() else { return }
        guard let sink = takeSinkIfChanged(fresh) else { return }
        sink(fresh)
    }

    private func takeSinkIfChanged(_ fresh: LidState) -> (@Sendable (LidState) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        guard fresh != lastKnown else { return nil }
        lastKnown = fresh
        return onChange
    }

    private func snapshotLastKnown() -> LidState {
        lock.lock()
        defer { lock.unlock() }
        return lastKnown
    }
}

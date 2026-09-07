import Foundation
import Testing

import AwakeCore
@testable import LidObserver

/// Doble de la frontera con el IORegistry. Nunca toca IOKit.
private final class MockSource: ClamshellSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _value: LidState?
    private var sink: (@Sendable () -> Void)?
    private(set) var unsubscribeCount = 0
    private(set) var readCount = 0

    init(_ value: LidState?) { self._value = value }

    var value: LidState? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }

    func read() -> LidState? {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        return _value
    }

    func subscribe(_ onAnyChange: @escaping @Sendable () -> Void) {
        lock.lock(); sink = onAnyChange; lock.unlock()
    }

    func unsubscribe() {
        lock.lock(); sink = nil; unsubscribeCount += 1; lock.unlock()
    }

    /// Simula una notificacion de interes de `IOPMrootDomain`.
    func fire() {
        lock.lock(); let s = sink; lock.unlock()
        s?()
    }
}

/// Caja para juntar las emisiones sin condiciones de carrera.
private final class Sink: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LidState] = []
    var all: [LidState] { lock.lock(); defer { lock.unlock() }; return values }
    func record(_ v: LidState) { lock.lock(); values.append(v); lock.unlock() }
}

@Suite("LidObserver — dedupe de notificaciones")
struct LidObserverTests {

    @Test func emiteSoloCuandoElValorCambioDeVerdad() {
        let source = MockSource(.open)
        let sut = LidObserver(source: source)
        let sink = Sink()
        sut.startMonitoring { sink.record($0) }

        source.value = .closed
        source.fire()
        source.value = .open
        source.fire()

        #expect(sink.all == [.closed, .open])
    }

    @Test func notificacionesSinCambioNoEmitenNada() {
        // IOPMrootDomain dispara ante cualquier propiedad, no solo la tapa.
        // Si esto emitiera, la animacion aparecería sola cada dos por tres.
        let source = MockSource(.open)
        let sut = LidObserver(source: source)
        let sink = Sink()
        sut.startMonitoring { sink.record($0) }

        for _ in 0..<10 { source.fire() }

        #expect(sink.all.isEmpty)
    }

    @Test func elMismoValorRepetidoEmiteUnaSolaVez() {
        let source = MockSource(.open)
        let sut = LidObserver(source: source)
        let sink = Sink()
        sut.startMonitoring { sink.record($0) }

        source.value = .closed
        source.fire()
        source.fire()
        source.fire()

        #expect(sink.all == [.closed])
    }

    @Test func stateReleeLaFuenteYNoDevuelveUnCacheViejo() {
        // Mismo bug que tuvo BatteryGuard: un getter que contesta con lo ultimo
        // que vio miente justo cuando nadie llamo a startMonitoring todavia.
        let source = MockSource(.open)
        let sut = LidObserver(source: source)

        source.value = .closed
        #expect(sut.state == .closed)
        #expect(source.readCount >= 2, "tiene que releer, no contestar de memoria")
    }

    @Test func siLaFuenteNoContestaSeQuedaEnElUltimoValorConocido() {
        // Una Mac sin tapa no publica la propiedad. Inventar `.open` haria
        // disparar la animacion de apertura sola.
        let source = MockSource(.closed)
        let sut = LidObserver(source: source)
        source.value = nil

        #expect(sut.state == .closed)
    }

    @Test func sinPropiedadDesdeElArranqueAsumeAbierta() {
        let sut = LidObserver(source: MockSource(nil))
        #expect(sut.state == .open)
    }

    @Test func unaFuenteMudaNoEmite() {
        let source = MockSource(.open)
        let sut = LidObserver(source: source)
        let sink = Sink()
        sut.startMonitoring { sink.record($0) }

        source.value = nil
        source.fire()

        #expect(sink.all.isEmpty)
    }

    @Test func stopMonitoringSueltaLaFuenteYCortaLasEmisiones() {
        let source = MockSource(.open)
        let sut = LidObserver(source: source)
        let sink = Sink()
        sut.startMonitoring { sink.record($0) }

        sut.stopMonitoring()
        source.value = .closed
        source.fire()

        #expect(source.unsubscribeCount == 1)
        #expect(sink.all.isEmpty)
    }

    @Test func startMonitoringResincronizaAntesDeEscuchar() {
        // La tapa pudo cambiar entre el init y el start. Si no resincronizara,
        // la primera notificacion real emitiria un valor que ya era viejo.
        let source = MockSource(.open)
        let sut = LidObserver(source: source)
        source.value = .closed

        let sink = Sink()
        sut.startMonitoring { sink.record($0) }
        source.fire()

        #expect(sink.all.isEmpty, "ya estaba cerrada al empezar a escuchar")
    }
}

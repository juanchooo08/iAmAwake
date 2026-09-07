import Foundation
import Testing

import AwakeCore
@testable import Overlay

private final class FakeClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { _now = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return _now }
    func advance(_ seconds: TimeInterval) { lock.lock(); _now += seconds; lock.unlock() }
}

@MainActor
@Suite("LidSessionTracker — cuanto estuvo cerrada")
struct LidSessionTrackerTests {

    @Test func cerrarNoReportaDuracion() {
        let sut = LidSessionTracker(clock: FakeClock())
        let t = sut.transition(to: .closed, armed: true)
        #expect(t.to == .closed)
        #expect(t.closedFor == nil)
        #expect(t.wasArmed)
    }

    @Test func abrirDevuelveElTiempoQueEstuvoCerrada() {
        let clock = FakeClock()
        let sut = LidSessionTracker(clock: clock)

        _ = sut.transition(to: .closed, armed: true)
        clock.advance(2820)  // 47 min
        let t = sut.transition(to: .open, armed: true)

        #expect(t.closedFor == 2820)
    }

    @Test func abrirSinHaberCerradoNoInventaDuracion() {
        // Pasa al arrancar la app con la tapa ya abierta.
        let sut = LidSessionTracker(clock: FakeClock())
        #expect(sut.transition(to: .open, armed: true).closedFor == nil)
    }

    @Test func laSegundaAperturaNoRepiteLaDuracionDeLaPrimera() {
        // Este es el bug que motivo extraer esta clase: si `closedAt` no se
        // limpia, la segunda apertura reporta el tiempo acumulado desde la
        // primera vez que se cerro.
        let clock = FakeClock()
        let sut = LidSessionTracker(clock: clock)

        _ = sut.transition(to: .closed, armed: true)
        clock.advance(60)
        #expect(sut.transition(to: .open, armed: true).closedFor == 60)

        clock.advance(3600)
        #expect(sut.transition(to: .open, armed: true).closedFor == nil)
    }

    @Test func ciclosSucesivosCuentanCadaUnoPorSuCuenta() {
        let clock = FakeClock()
        let sut = LidSessionTracker(clock: clock)

        _ = sut.transition(to: .closed, armed: true)
        clock.advance(120)
        #expect(sut.transition(to: .open, armed: true).closedFor == 120)

        clock.advance(999)
        _ = sut.transition(to: .closed, armed: true)
        clock.advance(30)
        #expect(sut.transition(to: .open, armed: true).closedFor == 30)
    }

    @Test func desarmadoIgualSeMideParaNoMentirSiSeArmaDespues() {
        let clock = FakeClock()
        let sut = LidSessionTracker(clock: clock)

        _ = sut.transition(to: .closed, armed: false)
        clock.advance(10)
        let t = sut.transition(to: .open, armed: false)

        #expect(t.closedFor == 10)
        #expect(!t.wasArmed, "la duracion se mide igual; quien decide mostrarla es OverlayCopy")
    }
}

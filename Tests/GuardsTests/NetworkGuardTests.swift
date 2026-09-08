import Foundation
import Testing

import AwakeCore
@testable import Guards

private final class MockReachability: NetworkReachabilityReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _online: Bool
    private var sink: (@Sendable (Bool) -> Void)?
    private(set) var stopCount = 0

    init(online: Bool) { _online = online }

    var isOnline: Bool { lock.lock(); defer { lock.unlock() }; return _online }

    func startMonitoring(onChange: @escaping @Sendable (Bool) -> Void) {
        lock.lock(); sink = onChange; lock.unlock()
    }

    func stopMonitoring() { lock.lock(); sink = nil; stopCount += 1; lock.unlock() }

    /// Simula que NWPathMonitor reporta un cambio.
    func report(online: Bool) {
        lock.lock(); _online = online; let s = sink; lock.unlock()
        s?(online)
    }
}

/// Temporizador manual: nada corre hasta que el test lo dispara.
private final class ManualScheduler: DelayScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (@Sendable () -> Void)?
    private(set) var lastDelay: TimeInterval?
    private(set) var cancelCount = 0

    func schedule(after seconds: TimeInterval, _ body: @escaping @Sendable () -> Void) {
        lock.lock(); pending = body; lastDelay = seconds; lock.unlock()
    }

    func cancelPending() {
        lock.lock(); pending = nil; cancelCount += 1; lock.unlock()
    }

    func fire() {
        lock.lock(); let b = pending; pending = nil; lock.unlock()
        b?()
    }
}

private final class FakeClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return _now }
    func advance(_ s: TimeInterval) { lock.lock(); _now += s; lock.unlock() }
}

private final class Verdicts: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [GuardVerdict] = []
    var all: [GuardVerdict] { lock.lock(); defer { lock.unlock() }; return items }
    var last: GuardVerdict? { all.last }
    func record(_ v: GuardVerdict) { lock.lock(); items.append(v); lock.unlock() }
}

private func makeSUT(
    online: Bool = true,
    grace: Int = 300,
    enabled: Bool = true
) -> (NetworkGuard, MockReachability, ManualScheduler, FakeClock, Verdicts) {
    let reader = MockReachability(online: online)
    let scheduler = ManualScheduler()
    let clock = FakeClock()
    let prefs = PreferencesSnapshot(networkGuardEnabled: enabled, networkGraceSeconds: grace)
    let sut = NetworkGuard(reader: reader, preferences: prefs, clock: clock, scheduler: scheduler)
    let verdicts = Verdicts()
    sut.start { verdicts.record($0) }
    return (sut, reader, scheduler, clock, verdicts)
}

@Suite("NetworkGuard — desarmar cuando se cae la red")
struct NetworkGuardTests {

    @Test func onlineNoDesarmaNunca() {
        let (sut, _, _, _, _) = makeSUT()
        #expect(sut.currentVerdict == .ok)
    }

    @Test func caidaDentroDelMargenNoDesarma() {
        // Un salto de WiFi no tiene que costarte la sesion.
        let (sut, reader, _, clock, verdicts) = makeSUT(grace: 300)
        reader.report(online: false)
        clock.advance(299)

        #expect(sut.currentVerdict == .ok)
        #expect(verdicts.all.allSatisfy { $0 == .ok })
    }

    @Test func alCumplirseElMargenDesarma() {
        let (sut, reader, scheduler, clock, verdicts) = makeSUT(grace: 300)
        reader.report(online: false)
        clock.advance(300)
        scheduler.fire()

        #expect(sut.currentVerdict == .mustDisarm(.networkLost(afterSeconds: 300)))
        #expect(verdicts.last == .mustDisarm(.networkLost(afterSeconds: 300)))
    }

    @Test func elMargenSeProgramaCompletoAlCaerse() {
        let (sut, reader, scheduler, _, _) = makeSUT(grace: 300)
        reader.report(online: false)
        #expect(scheduler.lastDelay == 300)
        #expect(sut.currentVerdict == .ok, "todavia no vencio")
    }

    @Test func volverAConectarseCancelaElMargen() {
        let (sut, reader, scheduler, clock, _) = makeSUT(grace: 300)
        reader.report(online: false)
        clock.advance(120)
        reader.report(online: true)

        #expect(scheduler.cancelCount >= 1)
        #expect(sut.currentVerdict == .ok)
    }

    @Test func reconectarReiniciaLaCuentaDesdeCero() {
        // Si no se reiniciara, una segunda caida corta desarmaria enseguida.
        let (sut, reader, _, clock, _) = makeSUT(grace: 300)
        reader.report(online: false)
        clock.advance(290)
        reader.report(online: true)
        reader.report(online: false)
        clock.advance(100)

        #expect(sut.currentVerdict == .ok)
    }

    @Test func reportesRepetidosDeCaidaNoRegalanOtroMargenEntero() {
        // NWPathMonitor puede repetir `unsatisfied` al cambiar de interfaz.
        // Si cada uno reiniciara la cuenta, el margen no venceria jamas.
        let (sut, reader, _, clock, _) = makeSUT(grace: 300)
        reader.report(online: false)
        clock.advance(200)
        reader.report(online: false)
        clock.advance(100)

        #expect(sut.currentVerdict == .mustDisarm(.networkLost(afterSeconds: 300)))
    }

    @Test func desactivadaNoDesarmaAunqueLaRedEsteCaidaHaceHoras() {
        let (sut, reader, scheduler, clock, _) = makeSUT(grace: 300, enabled: false)
        reader.report(online: false)
        clock.advance(3600)
        scheduler.fire()

        #expect(sut.currentVerdict == .ok)
    }

    @Test func margenCeroDesarmaApenasSeCae() {
        let (sut, reader, _, _, verdicts) = makeSUT(grace: 0)
        reader.report(online: false)

        #expect(sut.currentVerdict == .mustDisarm(.networkLost(afterSeconds: 0)))
        #expect(verdicts.last == .mustDisarm(.networkLost(afterSeconds: 0)))
    }

    @Test func bajarElMargenConLaRedYaCaidaDesarmaSinEsperar() {
        let (sut, reader, _, clock, _) = makeSUT(grace: 900)
        reader.report(online: false)
        clock.advance(300)
        #expect(sut.currentVerdict == .ok)

        sut.apply(PreferencesSnapshot(networkGuardEnabled: true, networkGraceSeconds: 60))
        #expect(sut.currentVerdict == .mustDisarm(.networkLost(afterSeconds: 60)))
    }

    @Test func arrancarYaSinRedCuentaDesdeElArranque() {
        let (sut, _, scheduler, clock, _) = makeSUT(online: false, grace: 300)
        #expect(sut.currentVerdict == .ok, "recien arranca, todavia no vencio el margen")

        clock.advance(300)
        scheduler.fire()
        #expect(sut.currentVerdict == .mustDisarm(.networkLost(afterSeconds: 300)))
    }

    @Test func stopSueltaElLectorYCancelaElMargen() {
        let (sut, reader, scheduler, _, _) = makeSUT()
        reader.report(online: false)
        sut.stop()

        #expect(reader.stopCount == 1)
        #expect(scheduler.cancelCount >= 1)
    }
}

import Foundation
import StillOnCore
import Testing

@testable import HelperClient

/// La decision del dead man's switch, sin I/O y con tiempo simulado.
///
/// Es la parte del sistema cuyo fallo se paga con la bateria del usuario en 0,
/// asi que se testea sola, sin sockets, sin `pmset` y sin esperas reales.
@Suite struct DeadManTimerTests {

    private func makeTimer(timeout: TimeInterval = 30) -> (DeadManTimer, MutableClock) {
        let clock = MutableClock()
        return (DeadManTimer(timeout: timeout, clock: clock), clock)
    }

    @Test func testStartsIdle() {
        let (timer, _) = makeTimer()
        #expect(timer.state == .idle)
        #expect(!(timer.isArmed))
        #expect(!(timer.hasExpired))
        #expect(timer.timeRemaining == nil)
    }

    @Test func testIdleTimerNeverExpires() {
        let (timer, clock) = makeTimer()
        clock.advance(3600)
        #expect(timer.state == .idle)
    }

    @Test func testAliveRightAfterArming() {
        let (timer, _) = makeTimer()
        timer.arm()
        #expect(timer.isArmed)
        #expect(timer.state == .alive)
        #expect(abs((timer.timeRemaining ?? 0) - (30)) < 0.001)
    }

    @Test func testStillAliveJustBeforeTheTimeout() {
        let (timer, clock) = makeTimer()
        timer.arm()
        clock.advance(29.9)
        #expect(timer.state == .alive)
    }

    @Test func testExpiresExactlyAtTheTimeout() {
        let (timer, clock) = makeTimer()
        timer.arm()
        clock.advance(30)
        // Ante la duda se revierte: el costo de revertir de mas es que la Mac
        // duerma; el de revertir de menos es una bateria en 0.
        #expect(timer.state == .expired)
        #expect(timer.hasExpired)
        #expect(abs((timer.timeRemaining ?? -1) - (0)) < 0.001)
    }

    @Test func testExpiresAfterTheTimeout() {
        let (timer, clock) = makeTimer()
        timer.arm()
        clock.advance(31)
        #expect(timer.hasExpired)
    }

    @Test func testActivityPostponesExpiry() {
        let (timer, clock) = makeTimer()
        timer.arm()
        // Cuatro heartbeats de 10 s: el default de la app. Nunca debe vencer.
        for _ in 0..<4 {
            clock.advance(10)
            #expect(timer.state == .alive)
            timer.noteActivity()
        }
        clock.advance(29)
        #expect(timer.state == .alive)
        clock.advance(1)
        #expect(timer.state == .expired)
    }

    @Test func testActivityDoesNotArmAnIdleTimer() {
        let (timer, clock) = makeTimer()
        timer.noteActivity()
        #expect(timer.state == .idle)
        clock.advance(100)
        #expect(timer.state == .idle)
    }

    @Test func testActivityAfterExpiryDoesNotResurrect() {
        let (timer, clock) = makeTimer()
        timer.arm()
        clock.advance(45)
        #expect(timer.hasExpired)
        // El daemon ya revirtio y llamo a `disarm()`. Un heartbeat tardio no
        // puede volver a armar por su cuenta: eso lo decide un `arm` explicito.
        timer.disarm()
        timer.noteActivity()
        #expect(timer.state == .idle)
    }

    @Test func testDisarmIsIdempotent() {
        let (timer, _) = makeTimer()
        timer.arm()
        timer.disarm()
        timer.disarm()
        #expect(timer.state == .idle)
    }

    @Test func testRearmingResetsTheClock() {
        let (timer, clock) = makeTimer()
        timer.arm()
        clock.advance(29)
        timer.arm()
        clock.advance(29)
        #expect(timer.state == .alive)
    }

    @Test func testUsesTheWireTimeoutByDefault() {
        let timer = DeadManTimer(clock: MutableClock())
        #expect(timer.timeout == Wire.heartbeatTimeout)
    }

    @Test func testTheWireHeartbeatIntervalFitsInsideTheTimeout() {
        // Si esto se rompe, la app no alcanza a mandar un solo latido antes de
        // que el daemon revierta: la configuracion seria autodestructiva.
        #expect(Wire.heartbeatInterval * 2 < Wire.heartbeatTimeout)
    }
}

import StillOnCore
import Foundation
import Testing

@testable import Guards

@Suite struct BatteryGuardTests {

    @Test func testIdentifierIsBattery() {
        let guardUnderTest = BatteryGuard(
            reader: MockPowerSource(.onBattery(50)),
            preferences: .batteryPrefs(threshold: 20)
        )
        #expect(guardUnderTest.identifier == .battery)
    }

    // MARK: - Umbral

    @Test func testBelowThresholdOnBatteryMustDisarmWithThatPercent() {
        let guardUnderTest = BatteryGuard(
            reader: MockPowerSource(.onBattery(12)),
            preferences: .batteryPrefs(threshold: 20)
        )
        #expect(guardUnderTest.currentVerdict == .mustDisarm(.lowBattery(percent: 12)))
    }

    @Test func testExactlyAtThresholdMustDisarm() {
        let guardUnderTest = BatteryGuard(
            reader: MockPowerSource(.onBattery(20)),
            preferences: .batteryPrefs(threshold: 20)
        )
        #expect(guardUnderTest.currentVerdict == .mustDisarm(.lowBattery(percent: 20)))
    }

    @Test func testAboveThresholdIsOK() {
        let guardUnderTest = BatteryGuard(
            reader: MockPowerSource(.onBattery(21)),
            preferences: .batteryPrefs(threshold: 20)
        )
        #expect(guardUnderTest.currentVerdict == .ok)
    }

    // MARK: - AC y deshabilitado

    @Test func testOnACBelowThresholdIsOK() {
        let guardUnderTest = BatteryGuard(
            reader: MockPowerSource(.onAC(3)),
            preferences: .batteryPrefs(threshold: 20)
        )
        #expect(guardUnderTest.currentVerdict == .ok)
    }

    @Test func testDisabledGuardIsOKEvenAtOnePercentOnBattery() {
        let guardUnderTest = BatteryGuard(
            reader: MockPowerSource(.onBattery(1)),
            preferences: .batteryPrefs(threshold: 20, enabled: false)
        )
        #expect(guardUnderTest.currentVerdict == .ok)
    }

    // MARK: - apply

    @Test func testApplyRaisesThresholdAndReevaluates() {
        let reader = MockPowerSource(.onBattery(30))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 20))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        #expect(guardUnderTest.currentVerdict == .ok)

        guardUnderTest.apply(.batteryPrefs(threshold: 40))

        #expect(guardUnderTest.currentVerdict == .mustDisarm(.lowBattery(percent: 30)))
        #expect(recorder.verdicts == [.mustDisarm(.lowBattery(percent: 30))])
    }

    @Test func testApplyLoweringThresholdClearsTheBlock() {
        let reader = MockPowerSource(.onBattery(15))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 20))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        guardUnderTest.apply(.batteryPrefs(threshold: 10))

        #expect(guardUnderTest.currentVerdict == .ok)
        #expect(recorder.verdicts == [.ok])
    }

    @Test func testApplyDisablingGuardClearsTheBlock() {
        let reader = MockPowerSource(.onBattery(5))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 20))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        guardUnderTest.apply(.batteryPrefs(threshold: 20, enabled: false))

        #expect(guardUnderTest.currentVerdict == .ok)
        #expect(recorder.verdicts == [.ok])
    }

    // MARK: - Callbacks

    @Test func testCallbackFiresWhenSnapshotCrossesThreshold() {
        let reader = MockPowerSource(.onBattery(80))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 20))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        #expect(reader.isMonitoring)
        #expect(recorder.count == 0, "start no debe emitir por si solo")

        reader.emit(.onBattery(10))

        #expect(recorder.verdicts == [.mustDisarm(.lowBattery(percent: 10))])
    }

    @Test func testPluggingInWhileBlockedEmitsOK() {
        let reader = MockPowerSource(.onBattery(10))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 20))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        reader.emit(.onAC(10))

        #expect(recorder.verdicts == [.ok])
        #expect(guardUnderTest.currentVerdict == .ok)
    }

    /// Un cambio de fuente produce EXACTAMENTE un veredicto. Repetir el mismo
    /// estado no vuelve a emitir: eso es lo que evita el bucle de desarme.
    @Test func testOneSourceChangeYieldsExactlyOneVerdictAndNoLoop() {
        let reader = MockPowerSource(.onBattery(80))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 20))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        reader.emit(.onBattery(15))
        #expect(recorder.count == 1)

        // Mismo veredicto repetido varias veces: silencio.
        reader.emit(.onBattery(15))
        reader.emit(.onBattery(15))
        #expect(recorder.count == 1)

        // Un cambio que no cruza el umbral tampoco emite.
        let quiet = MockPowerSource(.onBattery(80))
        let quietGuard = BatteryGuard(reader: quiet, preferences: .batteryPrefs(threshold: 20))
        let quietRecorder = VerdictRecorder()
        quietGuard.start(onVerdict: quietRecorder.sink)
        quiet.emit(.onBattery(70))
        quiet.emit(.onBattery(60))
        #expect(quietRecorder.count == 0)
    }

    @Test func testStopEndsCallbacksAndUnsubscribesTheReader() {
        let reader = MockPowerSource(.onBattery(80))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 20))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        guardUnderTest.stop()
        #expect(!(reader.isMonitoring))

        reader.emit(.onBattery(2))
        #expect(recorder.count == 0)

        // stop() es idempotente: no vuelve a desregistrar.
        guardUnderTest.stop()
        #expect(reader.stopCount == 1)
    }

    @Test func testStartIsIdempotent() {
        let reader = MockPowerSource(.onBattery(80))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 20))
        let first = VerdictRecorder()
        let second = VerdictRecorder()
        guardUnderTest.start(onVerdict: first.sink)
        guardUnderTest.start(onVerdict: second.sink)

        reader.emit(.onBattery(5))

        #expect(first.count == 1, "el segundo start no debe reemplazar al callback vivo")
        #expect(second.count == 0)
    }

    /// El guard nunca instancia el lector real: se apaga por completo con el mock.
    @Test func testGuardOnlyTalksToTheInjectedReader() {
        let reader = MockPowerSource(.onAC(100))
        let guardUnderTest = BatteryGuard(reader: reader, preferences: .batteryPrefs(threshold: 50))
        #expect(guardUnderTest.currentVerdict == .ok)
        reader.emit(.onBattery(1))
        #expect(guardUnderTest.currentVerdict == .mustDisarm(.lowBattery(percent: 1)))
    }
}

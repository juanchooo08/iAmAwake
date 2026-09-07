import StillOnCore
import Foundation
import Testing

@testable import Guards

@Suite struct ThermalGuardTests {

    @Test func testIdentifierIsThermal() {
        let guardUnderTest = ThermalGuard(
            reader: MockThermal(.nominal),
            preferences: .thermalPrefs(ceiling: .serious)
        )
        #expect(guardUnderTest.identifier == .thermal)
    }

    @Test func testBelowCeilingIsOK() {
        let guardUnderTest = ThermalGuard(
            reader: MockThermal(.fair),
            preferences: .thermalPrefs(ceiling: .serious)
        )
        #expect(guardUnderTest.currentVerdict == .ok)
    }

    @Test func testExactlyAtCeilingMustDisarm() {
        let guardUnderTest = ThermalGuard(
            reader: MockThermal(.serious),
            preferences: .thermalPrefs(ceiling: .serious)
        )
        #expect(guardUnderTest.currentVerdict == .mustDisarm(.thermal(.serious)))
    }

    @Test func testAboveCeilingMustDisarmWithTheActualLevel() {
        let guardUnderTest = ThermalGuard(
            reader: MockThermal(.critical),
            preferences: .thermalPrefs(ceiling: .serious)
        )
        #expect(guardUnderTest.currentVerdict == .mustDisarm(.thermal(.critical)))
    }

    @Test func testDisabledGuardIsOKEvenAtCritical() {
        let guardUnderTest = ThermalGuard(
            reader: MockThermal(.critical),
            preferences: .thermalPrefs(ceiling: .fair, enabled: false)
        )
        #expect(guardUnderTest.currentVerdict == .ok)
    }

    /// Cubre el orden completo de `ThermalLevel: Comparable`.
    @Test func testFullOrderingAgainstEveryCeiling() {
        let levels: [ThermalLevel] = [.nominal, .fair, .serious, .critical]
        for ceiling in levels {
            for level in levels {
                let guardUnderTest = ThermalGuard(
                    reader: MockThermal(level),
                    preferences: .thermalPrefs(ceiling: ceiling)
                )
                let expected: GuardVerdict =
                    level >= ceiling ? .mustDisarm(.thermal(level)) : .ok
                #expect(guardUnderTest.currentVerdict == expected, "nivel \(level) contra techo \(ceiling)")
            }
        }
    }

    // MARK: - apply

    @Test func testApplyLoweringCeilingReevaluates() {
        let reader = MockThermal(.fair)
        let guardUnderTest = ThermalGuard(reader: reader, preferences: .thermalPrefs(ceiling: .serious))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        #expect(guardUnderTest.currentVerdict == .ok)

        guardUnderTest.apply(.thermalPrefs(ceiling: .fair))

        #expect(guardUnderTest.currentVerdict == .mustDisarm(.thermal(.fair)))
        #expect(recorder.verdicts == [.mustDisarm(.thermal(.fair))])
    }

    @Test func testApplyRaisingCeilingClearsTheBlock() {
        let reader = MockThermal(.serious)
        let guardUnderTest = ThermalGuard(reader: reader, preferences: .thermalPrefs(ceiling: .serious))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        guardUnderTest.apply(.thermalPrefs(ceiling: .critical))

        #expect(guardUnderTest.currentVerdict == .ok)
        #expect(recorder.verdicts == [.ok])
    }

    // MARK: - Callbacks

    @Test func testCallbackFiresOnceWhenLevelCrossesCeiling() {
        let reader = MockThermal(.nominal)
        let guardUnderTest = ThermalGuard(reader: reader, preferences: .thermalPrefs(ceiling: .serious))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        reader.emit(.fair)  // sigue por debajo del techo: silencio
        #expect(recorder.count == 0)

        reader.emit(.serious)
        #expect(recorder.verdicts == [.mustDisarm(.thermal(.serious))])

        reader.emit(.serious)  // repetido: no vuelve a emitir
        #expect(recorder.count == 1)
    }

    @Test func testStopEndsCallbacks() {
        let reader = MockThermal(.nominal)
        let guardUnderTest = ThermalGuard(reader: reader, preferences: .thermalPrefs(ceiling: .serious))
        let recorder = VerdictRecorder()
        guardUnderTest.start(onVerdict: recorder.sink)

        guardUnderTest.stop()
        #expect(!(reader.isMonitoring))

        reader.emit(.critical)
        #expect(recorder.count == 0)

        guardUnderTest.stop()
        #expect(reader.stopCount == 1)
    }

    // MARK: - Mapeo del lector real (puro, no toca el sistema)

    @Test func testThermalStateMapping() {
        #expect(ProcessInfoThermalReader.map(.nominal) == .nominal)
        #expect(ProcessInfoThermalReader.map(.fair) == .fair)
        #expect(ProcessInfoThermalReader.map(.serious) == .serious)
        #expect(ProcessInfoThermalReader.map(.critical) == .critical)
    }
}

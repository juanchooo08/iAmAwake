import Foundation
import Testing

@testable import MenuBar
import AwakeCore

@Suite struct StatusPresentationTests {
    private static let allStates: [ArmState] = [
        .disarmed,
        .armed,
        .blockedLowBattery(percent: 12),
        .blockedThermal(.critical),
        .failed(.helperUnavailable),
    ]

    // MARK: - Los cinco estados, uno por uno

    @Test func testDisarmed() {
        let p = StatusPresentation(state: .disarmed)
        #expect(p.symbolName == "moon.zzz")
        #expect(p.tooltip == "Desarmado")
        #expect(p.accessibilityDescription == "Desarmado")
        #expect(p.toggleTitle == "Armar")
        #expect(!(p.statusLine.isEmpty))
    }

    @Test func testArmed() {
        let p = StatusPresentation(state: .armed)
        #expect(p.symbolName == "bolt.fill")
        #expect(p.tooltip == "Armado — la Mac no dormirá")
        #expect(p.accessibilityDescription == "Armado — la Mac no dormirá")
        #expect(p.toggleTitle == "Desarmar")
    }

    @Test func testBlockedLowBatteryCarriesPercent() {
        let p = StatusPresentation(state: .blockedLowBattery(percent: 7))
        #expect(p.symbolName == "battery.25")
        #expect(p.tooltip == "Desarmado por batería baja (7 %)")
        #expect(p.accessibilityDescription == "Desarmado por batería baja (7 %)")
        #expect(p.toggleTitle == "Armar")
        #expect(p.statusLine.contains("7 %"))

        // El porcentaje realmente varia con el estado, no esta hardcodeado.
        let other = StatusPresentation(state: .blockedLowBattery(percent: 42))
        #expect(p.tooltip != other.tooltip)
    }

    @Test func testBlockedThermal() {
        let p = StatusPresentation(state: .blockedThermal(.serious))
        #expect(p.symbolName == "thermometer.high")
        #expect(p.tooltip.hasPrefix("Desarmado por temperatura"))
        #expect(p.accessibilityDescription == "Desarmado por temperatura")
        #expect(p.toggleTitle == "Armar")
        #expect(p.statusLine.contains("alta"))

        let critical = StatusPresentation(state: .blockedThermal(.critical))
        #expect(critical.statusLine.contains("critica"))
        #expect(p.statusLine != critical.statusLine)
    }

    @Test func testFailedCarriesErrorDetail() {
        let p = StatusPresentation(state: .failed(.hotkeyRegistrationFailed(-9878)))
        #expect(p.symbolName == "exclamationmark.triangle")
        #expect(p.tooltip.hasPrefix("Error: "))
        #expect(p.tooltip.contains("-9878"))
        #expect(p.accessibilityDescription == p.tooltip)
        #expect(p.toggleTitle == "Armar")

        let other = StatusPresentation(state: .failed(.helperUnavailable))
        #expect(p.tooltip != other.tooltip)
    }

    // MARK: - Invariantes entre estados

    /// Requisito: cuatro iconos de estado + uno de error, todos distintos.
    @Test func testNoTwoStatesShareASymbol() {
        let symbols = Self.allStates.map { StatusPresentation(state: $0).symbolName }
        #expect(symbols.count == 5)
        #expect(Set(symbols).count == 5, "Simbolos repetidos: \(symbols)")
    }

    @Test func testEveryStateHasADistinctTooltipAndStatusLine() {
        let tooltips = Self.allStates.map { StatusPresentation(state: $0).tooltip }
        #expect(Set(tooltips).count == 5, "Tooltips repetidos: \(tooltips)")

        let lines = Self.allStates.map { StatusPresentation(state: $0).statusLine }
        #expect(Set(lines).count == 5, "Lineas de estado repetidas: \(lines)")
    }

    @Test func testNoPresentationFieldIsEmpty() {
        for state in Self.allStates {
            let p = StatusPresentation(state: state)
            #expect(!(p.symbolName.isEmpty), "\(state)")
            #expect(!(p.accessibilityDescription.isEmpty), "\(state)")
            #expect(!(p.tooltip.isEmpty), "\(state)")
            #expect(!(p.toggleTitle.isEmpty), "\(state)")
            #expect(!(p.statusLine.isEmpty), "\(state)")
        }
    }

    /// Solo `.armed` ofrece desarmar; los cuatro restantes ofrecen armar.
    @Test func testToggleTitleFollowsArmedness() {
        for state in Self.allStates {
            let expected = state.isArmed ? "Desarmar" : "Armar"
            #expect(StatusPresentation(state: state).toggleTitle == expected, "\(state)")
        }
    }

    @Test func testErrorDescriptionsAreAllDistinct() {
        let errors: [AwakeError] = [
            .assertionFailed(1),
            .helperUnavailable,
            .helperRefused("boom"),
            .helperVersionMismatch(expected: 2, got: 1),
            .hotkeyRegistrationFailed(-9878),
            .notificationPermissionDenied,
        ]
        let texts = errors.map { StatusText.describe($0) }
        #expect(Set(texts).count == errors.count)
        #expect(texts.allSatisfy { !$0.isEmpty })
    }

    @Test func testThermalLevelDescriptionsAreAllDistinct() {
        let levels: [ThermalLevel] = [.nominal, .fair, .serious, .critical]
        #expect(Set(levels.map { StatusText.describe($0) }).count == 4)
    }
}

@Suite("StatusPresentation — latido del icono")
struct StatusPresentationPulseTests {
    @Test func soloLateArmado() {
        #expect(StatusPresentation(state: .armed).pulses)
    }

    @Test func ningunOtroEstadoLate() {
        // Un icono que late bloqueado o en error sugiere que esta trabajando
        // cuando justamente no lo esta.
        let quietos: [ArmState] = [
            .disarmed,
            .blockedLowBattery(percent: 12),
            .blockedThermal(.critical),
            .failed(.helperUnavailable),
        ]
        for state in quietos {
            #expect(!StatusPresentation(state: state).pulses, "\(state) no deberia latir")
        }
    }
}

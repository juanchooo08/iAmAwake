import Foundation
import Testing
@testable import AwakeCore

@Suite("PowerState — maquina de estados")
@MainActor
struct PowerStateTests {

    private struct Rig {
        let state: PowerState
        let inhibitor: MockInhibitor
        let lid: MockLid
        let battery: MockGuard
        let thermal: MockGuard
        let notifier: MockNotifier
    }

    private func makeRig(
        battery: GuardVerdict = .ok,
        thermal: GuardVerdict = .ok
    ) -> Rig {
        let inhibitor = MockInhibitor()
        let lid = MockLid()
        let b = MockGuard(.battery, verdict: battery)
        let t = MockGuard(.thermal, verdict: thermal)
        let notifier = MockNotifier()
        let state = PowerState(
            inhibitor: inhibitor, lid: lid, guards: [b, t],
            preferences: MockPreferences(), notifier: notifier, clock: FixedClock()
        )
        return Rig(state: state, inhibitor: inhibitor, lid: lid,
                   battery: b, thermal: t, notifier: notifier)
    }

    // MARK: - Armado

    @Test func testArranca_desarmado() {
        #expect(makeRig().state.status == .disarmed)
    }

    @Test func testArmar_activaLasDosDefensas() async {
        let r = makeRig()
        await r.state.requestArm()

        #expect(r.state.status == .armed)
        #expect(r.inhibitor.engageCount == 1)
        #expect(r.lid.disabledCalls == [true], "el cierre de tapa depende del daemon")
        #expect(r.state.lastError == nil)
    }

    @Test func testArmarDosVeces_noDuplica() async {
        let r = makeRig()
        await r.state.requestArm()
        await r.state.requestArm()
        #expect(r.inhibitor.engageCount == 1)
    }

    @Test func testNoArma_siUnaGuardaBloquea() async {
        let r = makeRig(battery: .mustNotArm(.lowBattery(percent: 12)))
        await r.state.requestArm()

        #expect(r.state.status == .blockedLowBattery(percent: 12))
        #expect(r.inhibitor.engageCount == 0, "no debe tocar IOKit si ya sabe que no puede armar")
        #expect(r.lid.disabledCalls.isEmpty)
        #expect(r.notifier.disarmReasons.count == 1)
    }

    // MARK: - Errores (requisito 8: nunca fallar en silencio)

    @Test func testFalloDeIOKit_quedaEnFailedYNotifica() async {
        let r = makeRig()
        r.inhibitor.errorToThrow = .assertionFailed(-536870212)
        await r.state.requestArm()

        #expect(r.state.status == .failed(.assertionFailed(-536870212)))
        #expect(r.state.lastError == .assertionFailed(-536870212))
        #expect(r.notifier.failures == [.assertionFailed(-536870212)])
        #expect(r.inhibitor.disengageCount == 1, "debe limpiar lo que alcanzo a crear")
    }

    @Test func testDaemonAusente_armaDegradadoYAvisa() async {
        let r = makeRig()
        r.lid.errorToThrow = .helperUnavailable
        await r.state.requestArm()

        #expect(r.state.status == .armed, "las assertions igual sirven con la tapa abierta")
        #expect(r.state.lastError == .helperUnavailable)
        #expect(r.notifier.failures == [.helperUnavailable], "el usuario tiene que enterarse de que el cierre de tapa NO esta cubierto")
    }

    // MARK: - Guardas

    @Test func testGuardaDesarmaEstandoArmado() async {
        let r = makeRig()
        await r.state.requestArm()
        await r.state.report(.mustDisarm(.lowBattery(percent: 19)), from: .battery)

        #expect(r.state.status == .blockedLowBattery(percent: 19))
        #expect(r.inhibitor.disengageCount == 1)
        #expect(r.lid.disabledCalls == [true, false], "hay que devolver el interruptor de tapa")
        #expect(r.notifier.disarmReasons == [.lowBattery(percent: 19)])
    }

    @Test func testGuardaTermicaDesarma() async {
        let r = makeRig()
        await r.state.requestArm()
        await r.state.report(.mustDisarm(.thermal(.critical)), from: .thermal)

        #expect(r.state.status == .blockedThermal(.critical))
        #expect(r.notifier.disarmReasons == [.thermal(.critical)])
    }

    @Test func testNoRearmaSolo_cuandoLaCondicionSeNormaliza() async {
        let r = makeRig()
        await r.state.requestArm()
        r.battery.currentVerdict = .mustDisarm(.lowBattery(percent: 15))
        await r.state.report(.mustDisarm(.lowBattery(percent: 15)), from: .battery)
        #expect(r.state.status == .blockedLowBattery(percent: 15))

        r.battery.currentVerdict = .ok
        await r.state.report(.ok, from: .battery)

        #expect(r.state.status == .disarmed, "vuelve a desarmado, NO a armado")
        #expect(r.inhibitor.engageCount == 1, "rearmar solo produce ciclos de arme/desarme")
    }

    @Test func testSigueBloqueado_siLaOtraGuardaTodaviaBloquea() async {
        let r = makeRig()
        await r.state.requestArm()
        r.thermal.currentVerdict = .mustDisarm(.thermal(.serious))
        await r.state.report(.mustDisarm(.thermal(.serious)), from: .thermal)
        r.battery.currentVerdict = .mustDisarm(.lowBattery(percent: 10))
        await r.state.report(.mustDisarm(.lowBattery(percent: 10)), from: .battery)

        r.battery.currentVerdict = .ok
        await r.state.report(.ok, from: .battery)

        #expect(r.state.status != .disarmed, "la termica sigue bloqueando")
    }

    // MARK: - Desarme manual

    @Test func testDesarmeManual_noNotifica() async {
        let r = makeRig()
        await r.state.requestArm()
        await r.state.requestDisarm(reason: .user)

        #expect(r.state.status == .disarmed)
        #expect(r.notifier.disarmReasons.isEmpty, "el usuario ya sabe que lo desarmo el")
    }

    @Test func testToggle() async {
        let r = makeRig()
        await r.state.toggle()
        #expect(r.state.status == .armed)
        await r.state.toggle()
        #expect(r.state.status == .disarmed)
    }

    @Test func testCierreDeApp_devuelveElInterruptor() async {
        let r = makeRig()
        await r.state.requestArm()
        await r.state.requestDisarm(reason: .appTerminating)

        #expect(r.lid.disabledCalls.last == false,
                "si la app se va sin revertir, la bateria se drena a 0 con la tapa cerrada")
        #expect(r.notifier.disarmReasons.isEmpty)
    }

    // MARK: - Heartbeat

    @Test func testHeartbeat_soloEstandoArmado() async {
        let r = makeRig()
        await r.state.heartbeatTick()
        #expect(r.lid.heartbeatCount == 0)

        await r.state.requestArm()
        await r.state.heartbeatTick()
        #expect(r.lid.heartbeatCount == 1)
    }

    @Test func testHeartbeatQueFalla_registraElError() async {
        let r = makeRig()
        await r.state.requestArm()
        r.lid.heartbeatError = .helperRefused("daemon caido")
        await r.state.heartbeatTick()

        #expect(r.state.lastError == .helperRefused("daemon caido"))
        #expect(r.notifier.failures == [.helperRefused("daemon caido")])
    }

    @Test func testHeartbeatOK_limpiaElErrorDeDaemonAusente() async {
        let r = makeRig()
        r.lid.errorToThrow = .helperUnavailable
        await r.state.requestArm()
        #expect(r.state.lastError == .helperUnavailable)

        r.lid.errorToThrow = nil
        await r.state.heartbeatTick()
        #expect(r.state.lastError == nil, "el daemon volvio, el aviso ya no aplica")
    }

    // MARK: - Preferencias

    @Test func testCambioDePreferencias_llegaALasGuardas() async {
        let r = makeRig()
        var prefs = PreferencesSnapshot()
        prefs.batteryThreshold = 35
        await r.state.applyPreferences(prefs)

        #expect(r.battery.appliedPrefs?.batteryThreshold == 35)
        #expect(r.thermal.appliedPrefs?.batteryThreshold == 35)
    }

    @Test func testSubirElUmbral_desarmaSiElNuevoValorYaBloquea() async {
        let r = makeRig()
        await r.state.requestArm()
        #expect(r.state.status == .armed)

        r.battery.currentVerdict = .mustDisarm(.lowBattery(percent: 30))
        var prefs = PreferencesSnapshot()
        prefs.batteryThreshold = 40
        await r.state.applyPreferences(prefs)

        #expect(r.state.status == .blockedLowBattery(percent: 30))
    }

    @Test func testPreferenciasFueraDeRango_seClampean() async {
        let r = makeRig()
        var prefs = PreferencesSnapshot()
        prefs.batteryThreshold = 999
        prefs.thermalCeiling = .nominal
        await r.state.applyPreferences(prefs)

        #expect(r.battery.appliedPrefs?.batteryThreshold == 50)
        #expect(r.battery.appliedPrefs?.thermalCeiling == .fair, "nominal como techo dispararia siempre")
    }
}

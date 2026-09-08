import Foundation
import Testing
@testable import AwakeCore

/// Flujo completo con dobles de todo lo que toca el sistema: ni IOKit, ni pmset,
/// ni la barra de menu, ni el daemon real.
@Suite("Flujo end-to-end")
@MainActor
struct EndToEndTests {

    // MARK: - El camino feliz

    @Test func armarActivaLasDosDefensasEnOrden() async {
        let h = Harness()
        await h.start()
        await h.tapMenuToggle()

        #expect(h.state.status == .armed)
        #expect(h.log.all == [Effect.engage, Effect.lidOn, Effect.notify("arm.ok")],
                "primero las assertions, despues el interruptor de tapa, y recien ahi el aviso")
        #expect(h.presenter.last == .armed)
    }

    @Test func elHeartbeatSoloLateEstandoArmado() async {
        let h = Harness()
        await h.start()

        await h.heartbeatTick()
        #expect(!h.log.all.contains(Effect.heartbeat), "desarmado no hay nada que sostener")

        await h.tapMenuToggle()
        await h.heartbeatTick()
        await h.heartbeatTick()
        #expect(h.log.all.filter { $0 == Effect.heartbeat }.count == 2)
    }

    @Test func desarmeManualRevierteTodo() async {
        let h = Harness()
        await h.start()
        await h.tapMenuToggle()
        h.log.clear()
        await h.tapMenuToggle()

        #expect(h.state.status == .disarmed)
        #expect(h.log.all == [Effect.disengage, Effect.lidOff, Effect.notify("disarm.user")],
                "revertir primero, avisar despues")
        #expect(h.deliverer.payloads.map(\.identifier) == ["arm.ok", "disarm.user"])
    }

    // MARK: - El flujo que motiva el proyecto

    @Test func bateriaBajaDesarmaSolaYDevuelveElInterruptorDeTapa() async {
        let h = Harness(battery: .battery(80))
        await h.start()
        await h.tapMenuToggle()
        #expect(h.state.status == .armed)

        // Tapa cerrada: nadie toca nada, el estado se sostiene solo.
        await h.heartbeatTick()
        await h.heartbeatTick()
        #expect(h.state.status == .armed)

        h.log.clear()
        h.batterySource.emit(.battery(19))   // umbral default = 20
        await h.pump()

        #expect(h.state.status == .blockedLowBattery(percent: 19))
        #expect(h.log.all == [Effect.disengage, Effect.lidOff, Effect.notify("disarm.lowBattery")],
                "soltar las assertions, devolver la tapa, y recien ahi avisar")
        #expect(h.presenter.last == .blockedLowBattery(percent: 19))
    }

    @Test func laNotificacionDeBateriaExplicaElMotivo() async {
        let h = Harness(battery: .battery(80))
        await h.start()
        await h.tapMenuToggle()
        h.batterySource.emit(.battery(12))
        await h.pump()

        let body = h.deliverer.payloads.last?.body ?? ""
        #expect(body.contains("12"), "tiene que decir con cuanta bateria se desarmo")
        #expect(!body.isEmpty)
    }

    @Test func temperaturaAltaDesarmaIgual() async {
        let h = Harness()
        await h.start()
        await h.tapMenuToggle()
        h.log.clear()

        h.thermalSource.emit(.serious)       // techo default = .serious
        await h.pump()

        #expect(h.state.status == .blockedThermal(.serious))
        #expect(h.log.all == [Effect.disengage, Effect.lidOff, Effect.notify("disarm.thermal")])
    }

    @Test func noSeRearmaSolaCuandoLaCondicionSeNormaliza() async {
        let h = Harness(battery: .battery(80))
        await h.start()
        await h.tapMenuToggle()
        h.batterySource.emit(.battery(15))
        await h.pump()
        #expect(h.state.status == .blockedLowBattery(percent: 15))

        h.log.clear()
        h.batterySource.emit(.plugged(90))   // enchufaste el cargador
        await h.pump()

        #expect(h.state.status == .disarmed, "vuelve a desarmado, nunca a armado solo")
        #expect(!h.log.all.contains(Effect.engage), "rearmar solo produce ciclos de arme/desarme")
    }

    @Test func queSeNormaliceUnaGuardaNoDesbloqueaSiLaOtraSigue() async {
        let h = Harness(battery: .battery(80))
        await h.start()
        await h.tapMenuToggle()

        h.thermalSource.emit(.critical)
        await h.pump()
        h.batterySource.emit(.battery(10))
        await h.pump()

        h.batterySource.emit(.plugged(100))
        await h.pump()

        #expect(h.state.status != .disarmed, "la termica todavia bloquea")
    }

    // MARK: - Fallos (requisito 8: nunca en silencio)

    @Test func sinDaemonArmaDegradadoYAvisa() async {
        let h = Harness(lidInstallState: .notInstalled, lidFailure: .helperUnavailable)
        await h.start()
        await h.tapMenuToggle()

        #expect(h.state.status == .armed, "las assertions igual sirven con la tapa abierta")
        #expect(h.state.lastError == .helperUnavailable)

        let body = h.deliverer.payloads.last?.body ?? ""
        #expect(body.contains("iamawaked") || body.contains("daemon"),
                "el usuario tiene que saber que el cierre de tapa NO esta cubierto")
    }

    @Test func falloDeIOKitNoDejaNadaColgado() async {
        let h = Harness(inhibitorFailure: .assertionFailed(-536870212))
        await h.start()
        await h.tapMenuToggle()

        #expect(h.state.status == .failed(.assertionFailed(-536870212)))
        #expect(!h.inhibitor.isEngaged)
        #expect(h.log.all.contains(Effect.lidOff), "el interruptor de tapa queda devuelto")
        #expect(h.deliverer.payloads.count == 1)
    }

    @Test func permisoDeNotificacionesNegadoNoRompeNada() async {
        let h = Harness(battery: .battery(80), notificationsGranted: false)
        await h.start()
        await h.tapMenuToggle()
        h.batterySource.emit(.battery(5))
        await h.pump()

        #expect(h.state.status == .blockedLowBattery(percent: 5),
                "el desarme ocurre igual aunque no se pueda avisar")
        #expect(h.deliverer.payloads.isEmpty)
    }

    // MARK: - Cierre de la app

    @Test func alCerrarLaAppSeDevuelveElInterruptorDeTapa() async {
        let h = Harness()
        await h.start()
        await h.tapMenuToggle()
        h.log.clear()

        await h.state.requestDisarm(reason: .appTerminating)

        #expect(h.log.all == [Effect.disengage, Effect.lidOff],
                "si la app se va con disablesleep=1, la bateria se drena a 0 con la tapa cerrada")
        #expect(h.deliverer.payloads.map(\.identifier) == ["arm.ok"],
                "salir de la app no notifica; el 'arm.ok' es del armado previo")
    }

    // MARK: - Preferencias

    @Test func subirElUmbralDesarmaEnCaliente() async {
        let h = Harness(battery: .battery(30))
        await h.start()
        await h.tapMenuToggle()
        #expect(h.state.status == .armed, "30% con umbral 20 se puede armar")

        await h.changePreferences { $0.batteryThreshold = 40 }

        #expect(h.state.status == .blockedLowBattery(percent: 30),
                "asi se prueba el desarme por bateria sin descargarla: se mueve el umbral")
    }

    @Test func conCargadorLaGuardaDeBateriaNoMolesta() async {
        let h = Harness(battery: .plugged(3))
        await h.start()
        await h.tapMenuToggle()

        #expect(h.state.status == .armed, "desarmar enchufado no protege de nada")
    }

    @Test func desactivarLaGuardaTermicaLaSilencia() async {
        let h = Harness()
        await h.start()
        await h.changePreferences { $0.thermalGuardEnabled = false }
        await h.tapMenuToggle()

        h.thermalSource.emit(.critical)
        await h.pump()

        #expect(h.state.status == .armed)
    }

    // MARK: - Menu

    @Test func elIconoSigueAlEstado() async {
        let h = Harness(battery: .battery(80))
        await h.start()
        await h.tapMenuToggle()
        h.batterySource.emit(.battery(10))
        await h.pump()

        let simbolos = h.presenter.presentations.map(\.symbolName)
        #expect(Set(simbolos).count >= 3, "desarmado, armado y bateria baja son iconos distintos")
    }

    @Test func losOtrosItemsDelMenuFuncionan() async {
        let h = Harness()
        await h.start()

        h.presenter.onOpenPreferences?()
        h.presenter.onQuit?()

        #expect(h.preferencesOpened == 1)
        #expect(h.quitRequested)
    }
}

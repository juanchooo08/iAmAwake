import Foundation
import Testing

import AwakeCore
@testable import Overlay

@Suite("AwakeTally — cuanto aguanto")
struct AwakeTallyTests {
    @Test func segundosDebajoDelMinuto() {
        #expect(AwakeTally.duration(0) == "0 s")
        #expect(AwakeTally.duration(42) == "42 s")
        #expect(AwakeTally.duration(59.4) == "59 s")
    }

    @Test func minutosEnteros() {
        #expect(AwakeTally.duration(60) == "1 min")
        #expect(AwakeTally.duration(47 * 60 + 30) == "47 min")
        #expect(AwakeTally.duration(59 * 60) == "59 min")
    }

    @Test func horasConYSinResto() {
        #expect(AwakeTally.duration(3600) == "1 h")
        #expect(AwakeTally.duration(3600 * 3) == "3 h")
        #expect(AwakeTally.duration(3600 + 12 * 60) == "1 h 12 min")
    }

    @Test func intervaloNegativoNoImprimeBasura() {
        // El reloj del sistema puede saltar hacia atras.
        #expect(AwakeTally.duration(-5) == "0 s")
    }
}

@Suite("OverlayCopy — cuando aparece y que dice")
struct OverlayCopyTests {
    @Test func desarmadoNoMuestraNada() {
        // La animacion es la prueba de que iAmAwake esta haciendo algo.
        // Si no esta armado, cerrar la tapa es una noche normal.
        #expect(OverlayCopy.forTransition(LidTransition(to: .closed, wasArmed: false)) == nil)
        #expect(OverlayCopy.forTransition(
            LidTransition(to: .open, wasArmed: false, closedFor: 300)) == nil)
    }

    @Test func cerrarArmadoBarreLosParpados() throws {
        let copy = try #require(OverlayCopy.forTransition(
            LidTransition(to: .closed, wasArmed: true)))
        #expect(copy.motion == .closing)
        #expect(copy.headline == "iAmAwake")
    }

    @Test func abrirArmadoCuentaElTiempo() throws {
        let copy = try #require(OverlayCopy.forTransition(
            LidTransition(to: .open, wasArmed: true, closedFor: 47 * 60)))
        #expect(copy.motion == .opening)
        #expect(copy.detail == "47 min con la tapa cerrada")
    }

    @Test func abrirSinDuracionNoInventaUnNumero() throws {
        let copy = try #require(OverlayCopy.forTransition(
            LidTransition(to: .open, wasArmed: true, closedFor: nil)))
        #expect(copy.motion == .opening)
        #expect(!copy.detail.contains("0 s"))
    }

    @Test func abrirYCerrarDeGolpeNoDiceCeroSegundos() throws {
        let copy = try #require(OverlayCopy.forTransition(
            LidTransition(to: .open, wasArmed: true, closedFor: 0.3)))
        #expect(copy.detail == "seguí despierto")
    }
}

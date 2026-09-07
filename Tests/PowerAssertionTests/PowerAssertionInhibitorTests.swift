import Foundation
import IOKit.pwr_mgt
import StillOnCore
import Testing

@testable import PowerAssertion

@Suite("PowerAssertionInhibitor")
struct PowerAssertionInhibitorTests {

    @Test("engage exitoso crea las dos assertions y queda enganchado")
    func engageCreatesBothAssertions() async throws {
        let creator = MockAssertionCreator(statuses: [kIOReturnSuccess])
        let spawner = MockProcessSpawner()
        let inhibitor = PowerAssertionInhibitor(assertions: creator, spawner: spawner)

        #expect(inhibitor.isEngaged == false)
        try await inhibitor.engage()

        #expect(inhibitor.isEngaged == true)
        #expect(inhibitor.isUsingFallback == false)
        #expect(creator.createdTypes == [
            kIOPMAssertionTypeNoDisplaySleep,
            kIOPMAssertionTypePreventUserIdleSystemSleep,
        ])
        #expect(creator.liveIDs.count == 2)
        #expect(spawner.spawnCount == 0)
    }

    @Test("si la segunda assertion falla, la primera se libera")
    func secondFailureReleasesFirst() async throws {
        let creator = MockAssertionCreator(statuses: [kIOReturnSuccess, mockFailure])
        let spawner = MockProcessSpawner()
        let inhibitor = PowerAssertionInhibitor(assertions: creator, spawner: spawner)

        try await inhibitor.engage()

        #expect(creator.createCount == 2)
        #expect(creator.releasedIDs.count == 1)
        #expect(creator.liveIDs.isEmpty)
    }

    @Test("disengage es idempotente")
    func disengageIsIdempotent() async throws {
        let creator = MockAssertionCreator(statuses: [kIOReturnSuccess])
        let spawner = MockProcessSpawner()
        let inhibitor = PowerAssertionInhibitor(assertions: creator, spawner: spawner)

        try await inhibitor.engage()
        await inhibitor.disengage()
        await inhibitor.disengage()
        await inhibitor.disengage()

        #expect(inhibitor.isEngaged == false)
        #expect(creator.releasedIDs.count == 2)  // una sola vez cada assertion
        #expect(creator.liveIDs.isEmpty)
    }

    @Test("disengage sin engage previo no explota")
    func disengageWithoutEngage() async {
        let creator = MockAssertionCreator()
        let inhibitor = PowerAssertionInhibitor(assertions: creator, spawner: MockProcessSpawner())

        await inhibitor.disengage()

        #expect(inhibitor.isEngaged == false)
        #expect(creator.releasedIDs.isEmpty)
    }

    @Test("engage doble no duplica assertions")
    func doubleEngageDoesNotDuplicate() async throws {
        let creator = MockAssertionCreator(statuses: [kIOReturnSuccess])
        let inhibitor = PowerAssertionInhibitor(assertions: creator, spawner: MockProcessSpawner())

        try await inhibitor.engage()
        try await inhibitor.engage()
        try await inhibitor.engage()

        #expect(creator.createCount == 2)
        #expect(creator.liveIDs.count == 2)
        #expect(inhibitor.isEngaged == true)
    }

    @Test("fallo de IOKit cae al fallback caffeinate")
    func iokitFailureFallsBackToCaffeinate() async throws {
        let creator = MockAssertionCreator(statuses: [mockFailure])
        let spawner = MockProcessSpawner()
        let inhibitor = PowerAssertionInhibitor(assertions: creator, spawner: spawner)

        try await inhibitor.engage()

        #expect(inhibitor.isEngaged == true)
        #expect(inhibitor.isUsingFallback == true)
        #expect(spawner.spawnCount == 1)
        #expect(spawner.invocations.first?.path == "/usr/bin/caffeinate")
        #expect(spawner.invocations.first?.arguments == ["-dis"])
        // La primera assertion fallo, asi que no hay nada creado que liberar.
        #expect(creator.liveIDs.isEmpty)
    }

    @Test("disengage mata el proceso caffeinate del fallback")
    func disengageKillsFallbackProcess() async throws {
        let spawner = MockProcessSpawner()
        let inhibitor = PowerAssertionInhibitor(
            assertions: MockAssertionCreator(statuses: [mockFailure]),
            spawner: spawner
        )

        try await inhibitor.engage()
        let child = try #require(spawner.spawned.first)
        #expect(child.isRunning == true)

        await inhibitor.disengage()

        #expect(child.isRunning == false)
        #expect(child.terminateCount == 1)
        #expect(inhibitor.isEngaged == false)
        #expect(inhibitor.isUsingFallback == false)
    }

    @Test("engage doble en modo fallback no lanza un segundo caffeinate")
    func doubleEngageInFallbackDoesNotRespawn() async throws {
        let spawner = MockProcessSpawner()
        let inhibitor = PowerAssertionInhibitor(
            assertions: MockAssertionCreator(statuses: [mockFailure]),
            spawner: spawner
        )

        try await inhibitor.engage()
        try await inhibitor.engage()

        #expect(spawner.spawnCount == 1)
    }

    @Test("si IOKit y caffeinate fallan, lanza assertionFailed con el kern_return_t")
    func bothFailuresThrowAssertionFailed() async {
        let inhibitor = PowerAssertionInhibitor(
            assertions: MockAssertionCreator(statuses: [mockFailure]),
            spawner: MockProcessSpawner(shouldFail: true)
        )

        await #expect(throws: StillOnError.assertionFailed(mockFailure)) {
            try await inhibitor.engage()
        }
        #expect(inhibitor.isEngaged == false)
    }

    @Test("tras un fallo total se puede reintentar engage y funcionar")
    func recoversAfterTotalFailure() async throws {
        let creator = MockAssertionCreator(statuses: [mockFailure, kIOReturnSuccess, kIOReturnSuccess])
        let inhibitor = PowerAssertionInhibitor(
            assertions: creator,
            spawner: MockProcessSpawner(shouldFail: true)
        )

        await #expect(throws: StillOnError.self) { try await inhibitor.engage() }
        try await inhibitor.engage()

        #expect(inhibitor.isEngaged == true)
        #expect(inhibitor.isUsingFallback == false)
        #expect(creator.liveIDs.count == 2)
    }
}

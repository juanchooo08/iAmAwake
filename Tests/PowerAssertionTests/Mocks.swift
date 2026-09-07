import Foundation
import IOKit.pwr_mgt

@testable import PowerAssertion

/// Falla de IOKit generica para los tests. -536870212 == kIOReturnError.
let mockFailure: kern_return_t = kIOReturnError

struct MockSpawnError: Error {}

final class MockAssertionCreator: AssertionCreating, @unchecked Sendable {
    private let lock = NSLock()

    /// Status a devolver por cada llamada a `create`, en orden. Cuando se agota,
    /// se usa el ultimo valor.
    private var scriptedStatuses: [kern_return_t]
    private var nextID: UInt32 = 1

    private(set) var createdTypes: [String] = []
    private(set) var liveIDs: Set<IOPMAssertionID> = []
    private(set) var releasedIDs: [IOPMAssertionID] = []

    init(statuses: [kern_return_t] = [kIOReturnSuccess]) {
        self.scriptedStatuses = statuses
    }

    func create(type: String, name: String) -> AssertionCreationResult {
        lock.lock(); defer { lock.unlock() }
        createdTypes.append(type)
        let status = scriptedStatuses.count > 1 ? scriptedStatuses.removeFirst() : (scriptedStatuses.first ?? kIOReturnSuccess)
        guard status == kIOReturnSuccess else {
            return AssertionCreationResult(status: status, id: IOPMAssertionID(0))
        }
        let id = IOPMAssertionID(nextID)
        nextID += 1
        liveIDs.insert(id)
        return AssertionCreationResult(status: kIOReturnSuccess, id: id)
    }

    func release(_ id: IOPMAssertionID) -> kern_return_t {
        lock.lock(); defer { lock.unlock() }
        releasedIDs.append(id)
        liveIDs.remove(id)
        return kIOReturnSuccess
    }

    var createCount: Int {
        lock.lock(); defer { lock.unlock() }
        return createdTypes.count
    }
}

final class MockProcess: SpawnedProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private(set) var terminateCount = 0

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    func terminateAndWait() {
        lock.lock(); defer { lock.unlock() }
        terminateCount += 1
        running = false
    }
}

final class MockProcessSpawner: ProcessSpawning, @unchecked Sendable {
    private let lock = NSLock()
    private let shouldFail: Bool
    private(set) var invocations: [(path: String, arguments: [String])] = []
    private(set) var spawned: [MockProcess] = []

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func spawn(path: String, arguments: [String]) throws -> SpawnedProcess {
        lock.lock(); defer { lock.unlock() }
        invocations.append((path, arguments))
        if shouldFail { throw MockSpawnError() }
        let process = MockProcess()
        spawned.append(process)
        return process
    }

    var spawnCount: Int {
        lock.lock(); defer { lock.unlock() }
        return invocations.count
    }
}

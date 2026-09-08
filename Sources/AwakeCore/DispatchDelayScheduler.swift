import Foundation

/// `DelayScheduling` real, sobre una cola propia.
///
/// Cada `schedule` invalida lo anterior por generacion en vez de cancelar el
/// `DispatchWorkItem`: un item ya despachado puede correr igual, y la generacion
/// lo descarta cuando llega tarde.
public final class DispatchDelayScheduler: DelayScheduling, @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var generation = 0

    public init(queue: DispatchQueue = DispatchQueue(label: "dev.local.iamawake.delay")) {
        self.queue = queue
    }

    public func schedule(after seconds: TimeInterval, _ body: @escaping @Sendable () -> Void) {
        let mine = bumpGeneration()
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.isCurrent(mine) else { return }
            body()
        }
    }

    public func cancelPending() {
        _ = bumpGeneration()
    }

    private func bumpGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ value: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == value
    }
}

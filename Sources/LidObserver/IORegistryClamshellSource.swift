import AwakeCore
import Foundation
import IOKit

/// `ClamshellSource` real: lee `AppleClamshellState` de `IOPMrootDomain`.
///
/// No necesita privilegios: es una propiedad de lectura del IORegistry. Lo que
/// necesita root es *escribir* `DisableClamshellSleep`, y de eso se ocupa el
/// daemon, no esto.
public final class IORegistryClamshellSource: ClamshellSource, @unchecked Sendable {
    private let lock = NSLock()
    private var notifyPort: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var sink: (@Sendable () -> Void)?

    public init() {}

    deinit { teardown() }

    public func read() -> LidState? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let raw = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )
        // Una Mac sin tapa (Mini, Studio) sencillamente no publica la propiedad.
        guard let closed = raw?.takeRetainedValue() as? Bool else { return nil }
        return closed ? .closed : .open
    }

    public func subscribe(_ onAnyChange: @escaping @Sendable () -> Void) {
        teardown()

        lock.lock()
        sink = onAnyChange
        lock.unlock()

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        // Despacha en main: el consumidor final es la animacion, que es AppKit.
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            IONotificationPortDestroy(port)
            return
        }
        defer { IOObjectRelease(service) }

        var token: io_object_t = 0
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = IOServiceAddInterestNotification(
            port, service, kIOGeneralInterest,
            { context, _, _, _ in
                guard let context else { return }
                Unmanaged<IORegistryClamshellSource>.fromOpaque(context)
                    .takeUnretainedValue()
                    .fire()
            },
            context, &token
        )
        guard status == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }

        lock.lock()
        notifyPort = port
        notification = token
        lock.unlock()
    }

    public func unsubscribe() { teardown() }

    // MARK: - Privado

    private func fire() {
        lock.lock()
        let sink = self.sink
        lock.unlock()
        sink?()
    }

    private func teardown() {
        lock.lock()
        let port = notifyPort
        let token = notification
        notifyPort = nil
        notification = 0
        sink = nil
        lock.unlock()

        if token != 0 { IOObjectRelease(token) }
        if let port { IONotificationPortDestroy(port) }
    }
}

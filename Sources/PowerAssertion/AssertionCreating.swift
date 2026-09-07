import Foundation
import IOKit.pwr_mgt

/// Resultado crudo de crear una assertion. `id` solo es valido si `status == kIOReturnSuccess`.
struct AssertionCreationResult: Sendable {
    let status: kern_return_t
    let id: IOPMAssertionID
}

/// Frontera con IOKit. Existe para poder testear `PowerAssertionInhibitor` con un
/// mock, sin tocar el power management real de macOS.
protocol AssertionCreating: Sendable {
    func create(type: String, name: String) -> AssertionCreationResult
    func release(_ id: IOPMAssertionID) -> kern_return_t
}

/// Implementacion real. Es la unica parte del modulo que llama a IOKit.
struct IOKitAssertionCreator: AssertionCreating {
    func create(type: String, name: String) -> AssertionCreationResult {
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        return AssertionCreationResult(status: status, id: id)
    }

    func release(_ id: IOPMAssertionID) -> kern_return_t {
        IOPMAssertionRelease(id)
    }
}

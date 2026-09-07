import Darwin
import Foundation
import StillOnCore
import os

// Punto de entrada de `stillond`. Corre como root bajo launchd
// (`/Library/LaunchDaemons/dev.local.stillond.plist`).
//
// Uso:
//   stillond --uid <uid autorizado> [--socket <ruta>]
//
// El uid tambien puede venir por la variable de entorno `STILLOND_UID`. NO esta
// hardcodeado a proposito: el plist lo escribe `Scripts/install-helper.sh` con
// el uid de quien corre la instalacion, asi el binario sirve para cualquier
// usuario y no hay un uid magico en el fuente.

private func flag(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

let environment = ProcessInfo.processInfo.environment
let uidText = flag("--uid") ?? environment["STILLOND_UID"]
let socketPath = flag("--socket") ?? environment["STILLOND_SOCKET"] ?? Wire.socketPath

let authorizedUID: uid_t? = uidText.flatMap { UInt32($0) }
// El grupo se deriva del uid: no queremos que el instalador tenga que pasarlo.
let authorizedGID: gid_t? = authorizedUID.flatMap { getpwuid($0)?.pointee.pw_gid }

if authorizedUID == nil {
    // Sin uid, el socket queda root:wheel 0600 y solo root puede hablarle. El
    // daemon sigue siendo util (por ejemplo con `sudo`), pero la app no llega.
    Daemon.logger.error("sin --uid ni STILLOND_UID: el socket quedara accesible solo a root")
}
if geteuid() != 0 {
    Daemon.logger.error("stillond no corre como root: pmset va a fallar y no se podra impedir el sueño con la tapa cerrada")
}

Daemon(
    socketPath: socketPath,
    authorizedUID: authorizedUID,
    authorizedGID: authorizedGID
).run()

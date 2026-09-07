import Darwin
import Foundation
import HelperClient   // DeadManTimer: un solo fuente compartido con el cliente
import StillOnCore
import os

/// Daemon root. Lo unico que realmente evita que la Mac duerma con la tapa
/// cerrada, y lo unico que puede dejar la bateria en 0 si se porta mal.
///
/// Lee ARCHITECTURE.md seccion 0 antes de tocar esto. Resumen: `disablesleep=1`
/// significa que la Mac **no duerme nunca**. Si la app muere sin desarmar y el
/// daemon no revierte solo, el usuario abre la tapa al dia siguiente y encuentra
/// la maquina apagada por bateria agotada. Por eso el dead man's switch no es
/// una feature: es la razon por la que este proceso existe con estado.
final class Daemon: @unchecked Sendable {

    /// Por que se revirtio. Va al log; el usuario tiene que poder reconstruir
    /// que paso sin adivinar.
    enum RevertCause: String {
        case startupCleanup = "limpieza de arranque"
        case request = "pedido de la app"
        case heartbeatTimeout = "sin heartbeat (dead man's switch)"
        case clientDisconnected = "la app cerro la conexion"
        case signal = "SIGTERM/SIGINT"
        case hardBatteryFloor = "piso duro de bateria"
    }

    static let logger = Logger(subsystem: "dev.local.stillon", category: "stillond")

    /// Cada cuanto mira el reloj el watchdog.
    static let watchdogInterval: TimeInterval = 1.0
    /// Cada cuantos ticks del watchdog se relee la bateria (IOKit no es gratis).
    static let batteryCheckEveryTicks = 5
    /// Timeout de lectura por conexion. Solo sirve para no dejar hilos clavados;
    /// el silencio del cliente lo juzga el `DeadManTimer`, no esto.
    static let clientReadTimeout: TimeInterval = 1.0

    private let socketPath: String
    private let authorizedUID: uid_t?
    private let authorizedGID: gid_t?
    private let deadMan: DeadManTimer

    /// Protege `isArmed` y serializa las llamadas a `pmset`. Se toma durante toda
    /// la operacion: nunca puede haber un arm y un revert pisandose.
    private let lock = NSLock()
    private var isArmed = false
    private var isStopping = false

    private var listener: ListeningSocket?
    private var watchdog: DispatchSourceTimer?
    private var signalSources: [DispatchSourceSignal] = []

    init(
        socketPath: String = Wire.socketPath,
        authorizedUID: uid_t?,
        authorizedGID: gid_t?,
        deadMan: DeadManTimer = DeadManTimer()
    ) {
        self.socketPath = socketPath
        self.authorizedUID = authorizedUID
        self.authorizedGID = authorizedGID
        self.deadMan = deadMan
    }

    // MARK: - Ciclo de vida

    func run() -> Never {
        Self.logger.notice("stillond arrancando (uid autorizado: \(self.uidDescription, privacy: .public))")

        // Si un crash anterior dejo disablesleep=1, esto lo limpia. Arrancar
        // asumiendo un estado desconocido es como no tener dead man's switch.
        forceDisableSleepOff(cause: .startupCleanup, wasArmed: true)

        installSignalHandlers()
        startWatchdog()

        do {
            listener = try ListeningSocket(
                path: socketPath, ownerUID: authorizedUID, ownerGID: authorizedGID)
        } catch {
            Self.logger.fault("no se pudo abrir el socket: \(String(describing: error), privacy: .public)")
            exit(1)
        }
        Self.logger.notice("escuchando en \(self.socketPath, privacy: .public)")

        while !stoppingNow, let listener {
            guard let client = listener.accept() else { break }
            Thread.detachNewThread { [self] in serve(client) }
        }

        shutdown(cause: .signal)
    }

    private func shutdown(cause: RevertCause) -> Never {
        lock.lock()
        isStopping = true
        // Se fuerza sin mirar `isArmed`: salir dejando `disablesleep=1` puesto es
        // el peor final posible, y poner un 0 de mas no cuesta nada.
        forceDisableSleepOff(cause: cause, wasArmed: true)
        lock.unlock()

        listener?.closeAndUnlink()
        Self.logger.notice("stillond terminando")
        exit(0)
    }

    /// SIGTERM/SIGINT: `signal(..., SIG_IGN)` desactiva la accion por defecto y
    /// deja que el `DispatchSourceSignal` la maneje desde una cola normal, donde
    /// si se puede llamar a `pmset` (un handler de señal de verdad no podria).
    private func installSignalHandlers() {
        signal(SIGPIPE, SIG_IGN)
        let queue = DispatchQueue(label: "dev.local.stillon.signals")
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [self] in shutdown(cause: .signal) }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Vigila el silencio de la app y el piso de bateria. Corre en su propia cola:
    /// el hilo principal esta bloqueado en `accept()` y no puede mirar el reloj.
    private func startWatchdog() {
        let queue = DispatchQueue(label: "dev.local.stillon.watchdog")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.watchdogInterval, repeating: Self.watchdogInterval)
        let ticks = TickCounter()
        timer.setEventHandler { [self] in
            if deadMan.hasExpired {
                revert(cause: .heartbeatTimeout)
            }
            if ticks.next() % Self.batteryCheckEveryTicks == 0, armedNow,
               BatteryReader.isBelowHardFloor(BatteryReader.current(), floor: Wire.hardBatteryFloor) {
                revert(cause: .hardBatteryFloor)
            }
        }
        timer.resume()
        watchdog = timer
    }

    // MARK: - Conexiones

    private func serve(_ client: ClientConnection) {
        defer { client.closeConnection() }

        // Control de acceso #2 (el #1 son los permisos 0600 del socket): si el
        // proceso del otro lado no es el usuario autorizado, no le hablamos.
        if let authorizedUID {
            let peer = client.peerUID
            guard peer == authorizedUID || peer == 0 else {
                Self.logger.error(
                    "conexion rechazada: uid \(peer.map { String($0) } ?? "desconocido", privacy: .public)")
                return
            }
        }

        client.setReadTimeout(Self.clientReadTimeout)
        loop: while true {
            switch client.readLine() {
            case .line(let line):
                guard client.write(handle(line)) else { break loop }
            case .timedOut:
                // Silencio: lo juzga el watchdog, no este hilo.
                continue
            case .closed:
                break loop
            }
        }

        // La app se fue. Si quedo algo armado, se revierte: no sabemos si murio
        // limpia o de un kill -9.
        revert(cause: .clientDisconnected)
    }

    /// Un request → una respuesta. Nunca lanza: un daemon que se cae con un
    /// request raro es un daemon que deja `disablesleep=1` puesto.
    private func handle(_ line: Data) -> Data {
        let request: Wire.Request
        do {
            request = try Wire.decode(Wire.Request.self, from: line)
        } catch {
            return encode(Wire.Response(ok: false, error: "request malformado"))
        }

        guard request.version == Wire.protocolVersion else {
            return encode(Wire.Response(
                ok: false,
                error: "version de protocolo incompatible: el daemon habla "
                    + "\(Wire.protocolVersion), el cliente \(request.version)"))
        }

        // Cualquier request cuenta como señal de vida, no solo `ping`.
        deadMan.noteActivity()

        switch request.cmd {
        case .ping, .status:
            return encode(Wire.Response(ok: true, clamshellSleepDisabled: armedNow))
        case .arm:
            return encode(arm())
        case .disarm:
            revert(cause: .request)
            return encode(Wire.Response(ok: true, clamshellSleepDisabled: armedNow))
        }
    }

    private func encode(_ response: Wire.Response) -> Data {
        (try? Wire.encode(response))
            ?? Data(#"{"ok":false,"version":1,"error":"fallo al codificar"}"#.utf8 + [0x0A])
    }

    // MARK: - Estado

    private var stoppingNow: Bool {
        lock.lock(); defer { lock.unlock() }
        return isStopping
    }

    private var armedNow: Bool {
        lock.lock(); defer { lock.unlock() }
        return isArmed
    }

    private func arm() -> Wire.Response {
        // Piso de seguridad ANTES de armar: con la bateria en 4 % no hay pedido
        // de la app que justifique impedir el sueño.
        let battery = BatteryReader.current()
        if BatteryReader.isBelowHardFloor(battery, floor: Wire.hardBatteryFloor) {
            let percent = battery?.percent ?? 0
            Self.logger.notice("arm rechazado: bateria \(percent, privacy: .public) %")
            return Wire.Response(
                ok: false,
                clamshellSleepDisabled: false,
                error: "bateria en \(percent) %, por debajo del piso duro de "
                    + "\(Wire.hardBatteryFloor) %")
        }

        lock.lock()
        defer { lock.unlock() }
        guard !isStopping else {
            return Wire.Response(ok: false, clamshellSleepDisabled: isArmed,
                                 error: "el daemon se esta apagando")
        }
        do {
            try PMSet.setDisableSleep(true)
        } catch {
            Self.logger.error("arm fallo: \(String(describing: error), privacy: .public)")
            return Wire.Response(ok: false, clamshellSleepDisabled: isArmed,
                                 error: String(describing: error))
        }
        isArmed = true
        deadMan.arm()
        Self.logger.notice("armado: disablesleep=1")
        return Wire.Response(ok: true, clamshellSleepDisabled: true)
    }

    /// Revierte a `disablesleep 0` si hacia falta. Idempotente y seguro de llamar
    /// desde cualquier hilo.
    private func revert(cause: RevertCause) {
        lock.lock()
        defer { lock.unlock() }
        guard isArmed else { return }
        forceDisableSleepOff(cause: cause, wasArmed: true)
    }

    /// Requiere `lock` tomado, salvo en el arranque (todavia no hay otros hilos).
    private func forceDisableSleepOff(cause: RevertCause, wasArmed: Bool) {
        guard wasArmed else { return }
        deadMan.disarm()
        do {
            try PMSet.setDisableSleep(false)
            isArmed = false
            Self.logger.notice("revertido a disablesleep=0 — causa: \(cause.rawValue, privacy: .public)")
        } catch {
            // Se deja `isArmed = true` a proposito: si no pudimos revertir, el
            // watchdog tiene que volver a intentarlo en el proximo tick.
            Self.logger.fault(
                "NO SE PUDO REVERTIR — causa: \(cause.rawValue, privacy: .public) — \(String(describing: error), privacy: .public)")
        }
    }

    private var uidDescription: String {
        authorizedUID.map(String.init) ?? "ninguno (solo root)"
    }
}

/// Contador del watchdog. Existe solo para no tener estado mutable capturado
/// suelto en el closure del timer.
private final class TickCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}

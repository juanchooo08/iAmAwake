# iamawaked

Daemon root. Es lo **unico** que realmente evita que la Mac duerma con la tapa
cerrada, y lo unico del proyecto que puede dejarte la bateria en 0 si se porta
mal. Lee ARCHITECTURE.md seccion 0 antes de tocarlo.

```
iamawaked --uid <uid autorizado> [--socket <ruta>]
```

Se instala con `Scripts/install-helper.sh` (una vez, con `sudo`) y lo levanta
launchd desde `/Library/LaunchDaemons/dev.local.iamawaked.plist`.

## Que hace

Escucha en `/var/run/iamawaked.sock` (JSON delimitado por `\n`, tipos `Wire`) y
atiende cuatro comandos:

| Comando | Efecto |
|---|---|
| `arm` | `/usr/bin/pmset -a disablesleep 1` |
| `disarm` | `/usr/bin/pmset -a disablesleep 0` |
| `ping` | responde y cuenta como señal de vida |
| `status` | dice si `disablesleep` esta puesto |

Nada mas. No abre red, no lee archivos del usuario, no persiste nada.

Por que `pmset` y no IOKit: escribir `DisableClamshellSleep` en `IOPMrootDomain`
devuelve `kIOReturnNotPermitted` sin root, y con el user client abierto el
selector 11 devuelve `kIOReturnBadArgument` (medido en este hardware). Las power
assertions de IOKit no sirven: la Mac durmio a los 22 s con las tres activas.

## Dead man's switch

Con `disablesleep=1` la Mac **no duerme nunca**. Si la app muere sin desarmar y
el daemon no revierte por su cuenta, el usuario abre la tapa al dia siguiente y
encuentra la maquina apagada por bateria agotada. Por eso el daemon revierte a
`disablesleep 0` solo, sin depender de nadie, cuando pasa cualquiera de estas:

1. **Silencio** — ningun request en `Wire.heartbeatTimeout` (30 s) estando
   armado. La logica es `DeadManTimer`; el watchdog la consulta cada segundo.
2. **Conexion cerrada** — la app murio, limpia o de un `kill -9`.
3. **SIGTERM / SIGINT** — hay handlers instalados y se revierte antes de salir.
   Se usa `DispatchSourceSignal` y no un handler de señal C porque desde un
   handler real no se puede lanzar un proceso.
4. **Piso duro de bateria** — el daemon lee `IOPSCopyPowerSourcesInfo` por su
   cuenta y revierte con `<= Wire.hardBatteryFloor` (5 %) con bateria. Es
   independiente de la guarda configurable de la app: el daemon no le cree a la
   app, que puede estar colgada o muerta. Tambien rechaza `arm` en esa condicion.

Ademas, **al arrancar fuerza `disablesleep 0`**: si un crash anterior lo dejo en
1, se limpia solo. Y si un `pmset` de reversion falla, deja el estado como
"armado" a proposito para que el watchdog lo reintente al segundo siguiente.

Cada reversion automatica se loggea con su causa:

```
log stream --predicate 'subsystem == "dev.local.iamawake"'
```

## Que NO maneja

- **No** decide cuando armar. Eso lo pide la app; el daemon solo obedece o se
  niega por seguridad.
- **No** conoce las preferencias del usuario (umbral de bateria configurable,
  limite termico). Solo tiene el piso duro del 5 %.
- **No** toca el sueño por inactividad ni el display: eso son las power
  assertions del lado de la app (`PowerAssertion`).
- **No** se autoinstala ni se autoactualiza.
- **No** verifica la firma del binario cliente. El control de acceso es por uid
  (ver abajo).

## Modelo de seguridad

Corre como root, asi que el punto importante es **quien puede darle ordenes**:

1. **Permisos del socket.** Se crea con `umask 0o177` (0600) y `chown` al uid
   autorizado. El umask se aprieta *antes* del `bind`, no despues: si no, queda
   una ventana con el socket abierto a todo el mundo.
2. **`getpeereid` por conexion.** Se compara el uid del proceso del otro lado
   contra el autorizado (root tambien pasa) y se corta la conexion si no coincide,
   con un log.

El uid autorizado **no esta hardcodeado**: llega por `--uid` (o `IAMAWAKED_UID`)
desde el plist, que `install-helper.sh` escribe con `$SUDO_UID`.

Superficie de ataque: el protocolo es un enum cerrado de cuatro comandos sin
parametros. No se aceptan rutas, argumentos ni datos del cliente que terminen en
un `exec`. Lo unico que se ejecuta es `/usr/bin/pmset` con argumentos constantes.
Un request malformado se responde con `ok:false`; el daemon no se cae — un daemon
que se cae es un daemon que deja `disablesleep=1` puesto.

## Como se testea

El daemon en si **no** se testea automaticamente: haria falta root y ejecutar
`pmset` de verdad sobre la maquina del usuario. Lo que si se testea, y es la
parte donde un bug se paga con la bateria en 0, es la decision temporal:
`DeadManTimer`, con un reloj inyectado y tiempo simulado, en
`Tests/HelperClientTests/DeadManTimerTests.swift`.

`Sources/iamawaked/DeadManTimer.swift` es un **symlink** a
`Sources/HelperClient/DeadManTimer.swift`: el fuente y sus tests viven en
`HelperClient` (que si tiene test target), y este target lo compila tambien.
`iamawaked` no depende de `HelperClient` en `Package.swift`, y ese contrato no se
toco.

Verificacion manual del daemon, sobre una maquina que puedas dejar despierta:

```sh
sudo ./Scripts/install-helper.sh
pmset -g | grep -i disablesleep     # 0
# armar desde la app, o a mano con nc:
printf '{"cmd":"arm","version":1}\n' | nc -U /var/run/iamawaked.sock
pmset -g | grep -i disablesleep     # 1
# al cortar el nc, la conexion se cierra y vuelve a 0 en el acto (causa 2).
# Si en cambio el cliente queda abierto pero callado, vuelve a 0 a los 30 s (causa 1).
```

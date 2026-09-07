# HelperClient

Cliente del daemon root `iamawaked`. Implementa `LidSleepControlling`
(`SocketLidController`) hablando JSON delimitado por `\n` sobre un socket Unix.

## Que asume

- Que el daemon existe y habla `Wire` v1. Si no, lo dice; no adivina.
- Que el plist del LaunchDaemon en `/Library/LaunchDaemons/dev.local.iamawaked.plist`
  es la señal de "instalado". Su ausencia ⇒ `.notInstalled` sin siquiera intentar
  conectar.
- Que la app manda `heartbeat()` cada `Wire.heartbeatInterval` (10 s) mientras
  esta armada. Si deja de mandarlos, el daemon revierte solo a los 30 s. Este
  modulo **no** agenda el heartbeat: eso es de `PowerState`.

## Que NO maneja

- **No** instala ni arranca el daemon. Eso es `Scripts/install-helper.sh`, una
  vez, con `sudo`, a mano.
- **No** ejecuta `pmset` ni toca IOKit. Todo el privilegio vive del otro lado.
- **No** decide si hay que armar. Solo transmite la orden y traduce la respuesta.
- **No** cubre el sueño por inactividad: eso es `PowerAssertion`. Este modulo
  cubre unicamente el cierre de tapa.
- **No** reintenta indefinidamente: un solo reintento tras reconectar. Un daemon
  roto tiene que verse como error, no esconderse detras de reintentos.

## Modelo de seguridad

Quien puede hablarle al daemon:

1. **Permisos del filesystem.** El socket se crea 0600 con dueño = el uid que
   corrio la instalacion. Otro usuario de la maquina no puede abrirlo.
2. **`getpeereid` del lado del daemon.** Aunque alguien lograra un descriptor
   heredado, el daemon compara el uid del proceso conectado contra el autorizado
   y corta si no coincide.

Este modulo no tiene privilegios propios: corre como tu usuario y lo unico que
puede hacer es pedirle al daemon que ponga `disablesleep` en 0 o en 1. El
protocolo no tiene comandos para nada mas — no hay forma de convertir el socket
en una ejecucion arbitraria como root, porque el daemon no acepta rutas,
argumentos ni datos: solo cuatro comandos de un enum cerrado.

La app nunca se cuelga esperando: connect, read y write tienen timeout. En el
peor caso recibe `helperUnavailable` y desarma.

## Errores

| Situacion | Error |
|---|---|
| Socket ausente, caido o timeout | `AwakeError.helperUnavailable` |
| Respuesta `ok:false` | `AwakeError.helperRefused(mensaje)` |
| `version` distinta de `Wire.protocolVersion` | `AwakeError.helperVersionMismatch` |
| Respuesta truncada o basura | `AwakeError.helperUnavailable` |

`installState` es la excepcion: si el daemon contesta con otra version devuelve
`.ready(protocolVersion:)` con la version real. Decidir que hacer con la
incompatibilidad es de `PowerState`, no del transporte.

## Como se testea

`Tests/HelperClientTests` levanta un **daemon falso** (`FakeDaemon`) en un socket
Unix en `/tmp`, que habla el mismo protocolo y puede provocar a voluntad:
silencio, respuesta cortada a la mitad, version equivocada, `ok:false` y caida de
conexion. Nunca se instala el daemon real ni se ejecuta `pmset`.

`DeadManTimer` — la decision del dead man's switch — vive en este target aunque
lo use el daemon, precisamente para poder testearla sin I/O: se le inyecta un
`ClockProviding` falso (`MutableClock`) y se avanza el tiempo a mano. Cero
esperas reales.

> `Sources/iamawaked/DeadManTimer.swift` es un **symlink** a este archivo. Los dos
> targets lo compilan; el fuente y los tests viven aca. Se hizo asi porque
> `iamawaked` no depende de `HelperClient` en `Package.swift` y ese archivo es de
> otro modulo.

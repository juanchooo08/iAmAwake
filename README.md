# iAmAwake

App de barra de menú que evita que tu MacBook duerma con la tapa cerrada, para
dejar corriendo Claude Code, builds y descargas. Reemplazo local de iAmAwake, uso
personal, sin distribución.

Verificado en **MacBook Air M1 (MacBookAir10,1), macOS 26.6.2**. Nada más.

---

## Lo que hay que entender antes de usarla

Las power assertions de IOKit —lo que usa `caffeinate` y casi toda app del
rubro— **no evitan el sueño al cerrar la tapa**. Está medido en esta máquina:
durmió a los 22 segundos con `PreventUserIdleSystemSleep`, `PreventSystemSleep`
y `NoDisplaySleep` activas simultáneamente.

Lo único que funciona es `DisableClamshellSleep` en `IOPMrootDomain`, que es lo
que hace `pmset -a disablesleep 1`. Medido: 296 s de heartbeat continuo, tapa
cerrada, **con batería**, sin periféricos.

Eso exige root. Por eso hay dos procesos:

```
iAmAwake.app (tu usuario, sin privilegios)        iamawaked (root, LaunchDaemon)
├─ barra de menú, hotkey, guardas          <──>  ├─ pmset disablesleep
└─ socket Unix 0600                        JSON  └─ dead man's switch
```

El daemon se instala **una vez** con sudo. Después la app nunca vuelve a pedir
contraseña.

## Instalación

```bash
swift build -c release          # o Scripts/build-app.sh para el .app
sudo Scripts/install-helper.sh  # única vez que pide contraseña
Scripts/build-app.sh
cp -R build/iAmAwake.app /Applications/
xattr -cr /Applications/iAmAwake.app
open /Applications/iAmAwake.app
```

## Uso

Clic en el ícono o ⌃⌥S (configurable) para armar y desarmar.

| Ícono | Estado |
|---|---|
| `moon.zzz` | Desarmado |
| `bolt.fill` | Armado — la Mac no va a dormir |
| `battery.25` | Desarmado solo por batería baja |
| `thermometer.high` | Desarmado solo por temperatura |
| `wifi.slash` | Desarmado solo por falta de conexión |
| `exclamationmark.triangle` | Error — la app te dice cuál |

Armado, el ícono **late** despacio. Es el único feedback que se ve sin abrir el
menú. Respeta «Reducir movimiento» del sistema: con eso activado se queda quieto.

### Notificaciones

| Cuándo | Qué dice |
|---|---|
| Armás | «Podés cerrar la tapa: tu Mac se queda despierta» |
| Desarmás vos | «Tu Mac vuelve a dormirse normalmente cuando cierres la tapa» |
| Se desarma solo | El motivo: batería, temperatura o red |
| Falla algo | Qué falló, nunca en silencio |

Dos casos **no** notifican a propósito: salir de la app (la cerraste vos), y
armar cuando el daemon no está — ahí llega el aviso de la falla en vez del de
armado, para no darte dos notificaciones seguidas ni decirte que está todo bien
cuando el cierre de tapa no está cubierto.

### La guarda de red

Si la conexión se cae y no vuelve dentro del margen (5 min por defecto,
configurable de «al toque» a 30 min), iAmAwake se desarma solo y te avisa por
qué. Con la tapa cerrada eso significa que la Mac se duerme: sin internet no hay
descargas ni Claude Code que cuidar, así que no tiene sentido gastar batería.

El margen existe para que un salto entre redes o un reconnect de WiFi no te
corte la sesión. Como todas las guardas, **no rearma sola** cuando vuelve el
internet: quedás desarmado hasta que decidas.

### La cortina

Al cerrar la tapa baja una cortina desde arriba y tapa la pantalla. Al abrirla la
cortina se levanta, así que la pantalla se destapa de abajo hacia arriba; antes
de levantarse se queda un momento con el resumen (`47 min con la tapa cerrada`).

Solo aparece **si estás armado** — es la prueba de que iAmAwake está haciendo
algo, y con la app desarmada no estaría haciendo nada.

Para verla sin cerrar la tapa:

```bash
/Applications/iAmAwake.app/Contents/MacOS/iAmAwake --demo-overlay opening
/Applications/iAmAwake.app/Contents/MacOS/iAmAwake --demo-overlay closing
```

Se apaga desde Preferencias.

## El dead man's switch

Con `disablesleep=1` la Mac **no duerme nunca**. Si la app crashea sin desarmar,
tu batería se drena hasta 0 con la tapa cerrada. El daemon revierte por su
cuenta, sin depender de la app, cuando:

1. No recibe heartbeat por 30 s.
2. Se cierra la conexión del cliente.
3. Recibe SIGTERM o SIGINT.
4. Ve la batería en 5% o menos, sin importar tu umbral configurado.

Además fuerza `disablesleep 0` al arrancar, por si quedó colgado de un crash.

---

## Limitaciones conocidas de v1

1. **Requiere sudo una vez.** No hay alternativa: probado. Las tres vías sin
   privilegios (`AppliesToLimitedPower`, escribir `DisableClamshellSleep` por
   IORegistry, y el user client de `IOPMrootDomain`) devuelven
   `NotPrivileged` / `NotPermitted` / `BadArgument` en macOS 26.
2. **Sin grados Celsius.** macOS no expone temperatura absoluta por API pública.
   La guarda térmica usa los 4 niveles de `ProcessInfo.thermalState`. Leer el SMC
   necesita claves no documentadas.
3. **Sin firma de Apple.** Firma ad-hoc. Hay que quitar la cuarentena a mano la
   primera vez (`xattr -cr`). No se puede distribuir a otras máquinas así.
4. **Un solo hardware probado.** M1 / macOS 26.6. En otro Mac puede comportarse
   distinto; corré `Scripts/test.sh` y la prueba manual de tapa antes de confiar.
5. **No rearma sola.** Cuando la batería o la temperatura se normalizan, la app
   queda desarmada esperando que vos decidas. Es deliberado: rearmar solo tras un
   corte térmico produce ciclos de arme/desarme.
6. **La guarda térmica no distingue** calor por tapa cerrada de calor por carga de
   CPU. Solo ve el nivel que reporta el sistema.
7. **El hotkey no valida** que la combinación esté libre hasta que intenta
   registrarla. Si otra app la tiene tomada, falla ahí y te avisa.
8. **`Preferences` duplica el formateador de hotkey** de `Hotkey`, porque el
   contrato prohíbe la dependencia cruzada. Cosmético.
9. **La bajada de la cortina apenas se percibe.** Medido en este hardware, no
   supuesto: el sistema detecta el cierre correctamente, y la pantalla se apaga
   **204 ms** después de esa detección. La bajada dura 140 ms, así que entra
   completa en esa ventana. Lo que queda como límite no es el software sino el
   ángulo: cuando el sistema avisa, la tapa ya está a ~5° del cierre, y por esa
   rendija se percibe luz, no formas. Por eso al cerrar el dobladillo es una
   banda de luz ancha en vez del filito fino que usa al abrir. Para una
   animación progresiva mientras bajás la tapa haría falta el sensor de ángulo,
   que existe solo en los MacBook Pro 2021+. macOS reporta la
   tapa con un booleano (`AppleClamshellState`) que cambia recién a ~5° del
   cierre, y el backlight se apaga a los ~0,2 s. El sensor de ángulo que daría
   una animación progresiva existe solo en los MacBook Pro 2021+, que lo publican
   por HID en la usage page 0x20; verificado con `ioreg` en este MacBookAir10,1:
   cero dispositivos ahí. La que se ve de verdad es la de apertura.
10. **La guarda de red mira el camino, no internet.** Usa `NWPathMonitor`, que
   dice si hay ruta a la red. Un WiFi de hotel con portal cautivo, o un router
   sin salida, cuentan como conectado. Distinguirlo pediría pegarle a un
   servidor, y el requisito de v1 es cero llamadas de red.
11. **La animación dibuja solo en `NSScreen.main`.** Con monitores externos, las
   otras pantallas no muestran nada.

## Lo que falta (roadmap)

- Login item: que arranque sola al iniciar sesión.
- Animación en todas las pantallas, no solo la principal.
- Temporizador: armar por N horas y que se desarme sola.
- Reglas por aplicación: armar solo si cierto proceso está corriendo.
- Historial de por qué se desarmó, más allá de la notificación del momento.
- Instalación del daemon vía `SMAppService` en vez de script con sudo (requiere
  cuenta de desarrollador de Apple para que la firma valide).
- Probar en Intel y en otras versiones de macOS.

## Tests

```bash
Scripts/test.sh                        # los 161
Scripts/test.sh --filter GuardsTests   # uno solo
```

`Scripts/test.sh` existe porque esta máquina tiene Command Line Tools sin Xcode:
`XCTest.framework` no está, todo el proyecto usa swift-testing, y SwiftPM no
encuentra `Testing.framework` sin ayuda. Con Xcode instalado, el script detecta y
usa `swift test` normal.

Ningún test toca IOKit, pmset, la barra de menú ni el daemon real. Todo va contra
dobles inyectados.

## Desinstalar

```bash
sudo Scripts/uninstall-helper.sh
rm -rf /Applications/iAmAwake.app
```

## Estructura

Ver [ARCHITECTURE.md](ARCHITECTURE.md). Regla: todo depende de `AwakeCore`,
ningún módulo de implementación depende de otro, y solo `AwakeApp` los conoce
a todos.

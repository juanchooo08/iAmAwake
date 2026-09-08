# Estado

- 205 tests en 18 suites pasan; `swift build -c release` sin warnings.
- Renombre StillOn -> iAmAwake completo. El proyecto vive en
  `/Users/juancho/Documents/SAAS FAC/iAmAwake/iAmAwake`.
- Daemon `dev.local.iamawaked` instalado y probado contra el socket real.
- `/Applications/iAmAwake.app` instalada y corriendo.
- Animacion: cortina (baja al cerrar, se levanta al abrir). Modulos
  `LidObserver` + `Overlay`.
- Cuarta guarda: red. Desarma tras 5 min sin conexion, configurable.
- Notificaciones de armado/desarmado andando y verificadas en pantalla. Tres
  causas encadenadas: el permiso negado se cacheaba para siempre, faltaba el
  `UNUserNotificationCenterDelegate` (macOS descarta el banner si la app que lo
  manda esta activa), y el aviso iba con prioridad normal, asi que salia tarde.
  Armado y desarmado comparten grupo para que una rafaga de toggles no se
  descarte entera.
- Trazas con `os.Logger`, subsistema `dev.local.iamawake`. Sin ellas el
  diagnostico fue a ciegas: `log show --predicate 'subsystem == "dev.local.iamawake"'`.
- `--check-notifications` corre dentro del run loop de AppKit. En el codigo de
  nivel superior de `main.swift` se colgaba para siempre.

Pendiente:
- Atajo de teclado dedicado que reproduzca la cortina de cierre a pedido. Es el
  reemplazo acordado para la deteccion automatica, que es imposible: este
  hardware no expone angulo de tapa y `AppleClamshellState` avisa recien a ~5
  grados del cierre, 204 ms antes de que se apague el backlight.
- `Scripts/test.sh` no limpia: al cambiar el layout de un struct publico hay que
  borrar `.build/debug` o la suite falla con corrupcion de memoria.

Sin verificar contra hardware todavia:
- La cortina en un cierre de tapa real (la de cierre casi no se ve por diseno
  del hardware; ver limitacion 9 del README).
- La guarda de red en una caida real de WiFi.

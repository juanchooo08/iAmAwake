# Estado

- 199 tests en 18 suites pasan; `swift build -c release` sin warnings.
- Renombre StillOn -> iAmAwake completo. El proyecto vive en
  `/Users/juancho/Documents/SAAS FAC/iAmAwake/iAmAwake`.
- Daemon `dev.local.iamawaked` instalado y probado contra el socket real.
- `/Applications/iAmAwake.app` instalada y corriendo.
- Animacion: cortina (baja al cerrar, se levanta al abrir). Modulos
  `LidObserver` + `Overlay`.
- Cuarta guarda: red. Desarma tras 5 min sin conexion, configurable.

Sin verificar contra hardware todavia:
- La cortina en un cierre de tapa real (la de cierre casi no se ve por diseno
  del hardware; ver limitacion 9 del README).
- La guarda de red en una caida real de WiFi.

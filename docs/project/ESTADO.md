# Estado

v1 verificada end-to-end (2026-09-07), mas el renombre a iAmAwake y la animacion
de tapa.

- 187 tests en 17 suites pasan; `swift build -c release` sin warnings.
- Daemon verificado: arm pone SleepDisabled=1, disarm lo devuelve, dead man's
  switch revierte ~0.5 s despues de cortar la conexion.
- Prueba fisica de tapa cerrada: PASO (sin cargador, 5 min).
- Renombre StillOn -> iAmAwake completo: modulos `Awake*`, daemon `iamawaked`,
  socket `/var/run/iamawaked.sock`, bundle `dev.local.iamawake`. El directorio
  paso de `StillOnLocal` a `iAmAwake`.
- Animacion de parpado: modulos `LidObserver` + `Overlay`.

Pendiente del usuario (necesita sudo o hardware):
- Correr `sudo Scripts/install-helper.sh` de nuevo: el daemon viejo
  (`dev.local.stillond`) sigue instalado y el script lo limpia solo.
- Reemplazar `/Applications/StillOn.app` por el bundle nuevo.

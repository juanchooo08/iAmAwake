#!/bin/bash
#
# install-helper.sh — instala el daemon root `stillond`.
#
# Se corre UNA sola vez, con sudo. Lee esto entero antes: te va a instalar un
# proceso que corre como root y arranca con la maquina.
#
#   sudo ./Scripts/install-helper.sh [ruta/al/binario/stillond]
#
# QUE HACE, exactamente:
#   1. Copia el binario `stillond` a /usr/local/libexec/stillond (root:wheel 0755).
#   2. Escribe /Library/LaunchDaemons/dev.local.stillond.plist (root:wheel 0644),
#      con TU uid adentro (el de quien corre el sudo, via $SUDO_UID).
#   3. Lo carga con `launchctl bootstrap system`.
#
# QUE PODRA HACER ESE DAEMON:
#   Solo una cosa: ejecutar `pmset -a disablesleep 0|1`. Nada mas. No abre red,
#   no lee tus archivos, no persiste datos. El codigo esta en Sources/stillond.
#
# QUIEN PODRA HABLARLE:
#   Escucha en un socket Unix con permisos 0600 y dueño = tu uid. Solo vos (y
#   root) podes abrirlo, y ademas verifica el uid del proceso del otro lado con
#   getpeereid(). Otro usuario de la maquina no puede armarlo ni desarmarlo.
#
# COMO SACARLO:
#   sudo ./Scripts/uninstall-helper.sh
#
set -euo pipefail

LABEL="dev.local.stillond"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
INSTALL_DIR="/usr/local/libexec"
INSTALL_PATH="${INSTALL_DIR}/stillond"
SOCKET="/var/run/stillond.sock"
LOG_DIR="/var/log/stillon"

# --- 1. Tiene que correr como root -------------------------------------------
# Sin root no se puede escribir en /Library/LaunchDaemons ni cargar el daemon.
if [ "$(id -u)" -ne 0 ]; then
  echo "error: hay que correrlo con sudo." >&2
  echo "       sudo $0 [ruta/al/binario/stillond]" >&2
  exit 1
fi

# --- 2. De quien va a ser el socket ------------------------------------------
# $SUDO_UID es el uid del usuario que invoco sudo, no el 0 de root. Ese es el
# unico uid que va a poder hablarle al daemon. No esta hardcodeado en ningun
# lado: se escribe en el plist ahora y el binario lo lee por argumento.
TARGET_UID="${SUDO_UID:-}"
if [ -z "$TARGET_UID" ] || [ "$TARGET_UID" -eq 0 ]; then
  echo "error: no pude determinar tu uid (\$SUDO_UID vacio o 0)." >&2
  echo "       Corre el script con 'sudo', no como root directo." >&2
  exit 1
fi
TARGET_USER="$(id -un "$TARGET_UID")"

# --- 3. Encontrar el binario compilado ---------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_BINARY="${1:-}"
if [ -z "$SOURCE_BINARY" ]; then
  for candidate in \
    "${PACKAGE_DIR}/.build/release/stillond" \
    "${PACKAGE_DIR}/.build/debug/stillond" \
    "${PACKAGE_DIR}/.build-helper/release/stillond" \
    "${PACKAGE_DIR}/.build-helper/debug/stillond"; do
    if [ -x "$candidate" ]; then SOURCE_BINARY="$candidate"; break; fi
  done
fi
if [ -z "$SOURCE_BINARY" ] || [ ! -x "$SOURCE_BINARY" ]; then
  echo "error: no encontre el binario 'stillond'." >&2
  echo "       Compilalo primero:" >&2
  echo "         swift build -c release --package-path \"${PACKAGE_DIR}\" --product stillond" >&2
  echo "       o pasame la ruta:  sudo $0 /ruta/a/stillond" >&2
  exit 1
fi

echo "Instalando ${LABEL}"
echo "  binario origen : ${SOURCE_BINARY}"
echo "  usuario        : ${TARGET_USER} (uid ${TARGET_UID})"

# --- 4. Idempotencia: si ya estaba cargado, se descarga primero ---------------
# `bootout` falla si no estaba cargado; ese caso no es un error, por eso el `|| true`.
if launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  echo "  ya estaba instalado: descargando para recargar"
  launchctl bootout "system/${LABEL}" 2>/dev/null || true
fi

# Por las dudas: si el daemon anterior quedo armado, esto lo revierte ya mismo.
/usr/bin/pmset -a disablesleep 0 || true
rm -f "$SOCKET"

# --- 5. Copiar el binario ----------------------------------------------------
mkdir -p "$INSTALL_DIR"
install -m 0755 -o root -g wheel "$SOURCE_BINARY" "$INSTALL_PATH"

mkdir -p "$LOG_DIR"
chmod 0755 "$LOG_DIR"

# --- 6. Escribir el plist del LaunchDaemon -----------------------------------
# RunAtLoad + KeepAlive: si el daemon muere, launchd lo vuelve a levantar, y al
# arrancar el propio daemon fuerza `disablesleep 0`. Es una red de seguridad mas.
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_PATH}</string>
        <string>--uid</string>
        <string>${TARGET_UID}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stillond.out.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stillond.err.log</string>
</dict>
</plist>
PLIST_EOF

chown root:wheel "$PLIST"
chmod 0644 "$PLIST"

# --- 7. Cargar ---------------------------------------------------------------
launchctl bootstrap system "$PLIST"

echo
echo "Listo. El daemon corre como root y escucha en ${SOCKET} (0600, dueño ${TARGET_USER})."
echo "Ver su log:      log stream --predicate 'subsystem == \"dev.local.stillon\"'"
echo "Desinstalarlo:   sudo ${SCRIPT_DIR}/uninstall-helper.sh"

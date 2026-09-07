#!/bin/bash
#
# uninstall-helper.sh — saca el daemon root `iamawaked` y deja la maquina como estaba.
#
#   sudo ./Scripts/uninstall-helper.sh
#
# ORDEN DE LOS PASOS (importa):
#   1. `pmset -a disablesleep 0` PRIMERO. Si el daemon estaba armado y lo matamos
#      antes de revertir, la Mac queda sin dormir nunca y la bateria se drena.
#      Revertir primero es gratis; revertir despues puede no llegar a pasar.
#   2. Descargar el daemon con `launchctl bootout`.
#   3. Borrar plist, binario y socket.
#
# Todo el script tolera que las cosas ya no existan: se puede correr dos veces.
#
set -euo pipefail

LABEL="dev.local.iamawaked"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
INSTALL_PATH="/usr/local/libexec/iamawaked"
SOCKET="/var/run/iamawaked.sock"

# --- 0. Tiene que correr como root -------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "error: hay que correrlo con sudo." >&2
  echo "       sudo $0" >&2
  exit 1
fi

# --- 1. Revertir el estado del sistema ANTES de tocar nada -------------------
echo "Reactivando el sueño con la tapa cerrada (pmset -a disablesleep 0)"
/usr/bin/pmset -a disablesleep 0 || echo "  aviso: pmset fallo; revisa 'pmset -g' a mano" >&2

# --- 2. Descargar el daemon --------------------------------------------------
if launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  echo "Descargando ${LABEL}"
  launchctl bootout "system/${LABEL}" 2>/dev/null || true
else
  echo "El daemon no estaba cargado"
fi

# --- 3. Borrar los archivos --------------------------------------------------
for path in "$PLIST" "$INSTALL_PATH" "$SOCKET"; do
  if [ -e "$path" ]; then
    echo "Borrando ${path}"
    rm -f "$path"
  fi
done

# --- 4. Verificacion ---------------------------------------------------------
echo
echo "Estado final de disablesleep:"
/usr/bin/pmset -g | grep -i disablesleep || echo "  (pmset no lo reporta: ya no esta forzado)"
echo "Listo. No queda nada de iAmAwake corriendo como root."

#!/bin/sh
# Hook de Claude Code: marca que sesiones estan trabajando, para que iAmAwake
# deje dormir la Mac cuando ninguna trabaja (ClaudeSessionMarkerReader).
#
#   busy  -> crea o refresca la marca de la sesion
#   idle  -> la borra (termino el turno, o espera una respuesta tuya)
#
# Lee el JSON del hook por stdin. Nunca falla: un hook roto no puede trabar a
# Claude Code.
dir="$HOME/Library/Application Support/iAmAwake/claude-sessions"
id=$(grep -o '"session_id" *: *"[A-Za-z0-9_-]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$id" ] || exit 0
case "$1" in
  busy) mkdir -p "$dir" && touch "$dir/$id" ;;
  idle) rm -f "$dir/$id" ;;
esac
exit 0

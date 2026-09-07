#!/bin/bash
# Corre la suite. Necesario porque en esta maquina hay Command Line Tools sin
# Xcode: XCTest.framework no existe (por eso todo el proyecto usa swift-testing)
# y SwiftPM no agrega solo la ruta de Testing.framework.
set -euo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [ -d /Applications/Xcode.app ]; then
  exec swift test --package-path "$PKG" "$@"     # con Xcode no hace falta nada de esto
fi
DYLD_LIBRARY_PATH="$LIB" exec swift test --package-path "$PKG" \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$LIB" "$@"

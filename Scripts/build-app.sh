#!/bin/bash
# Compila iAmAwake.app y lo firma ad-hoc (sin cuenta de desarrollador de Apple).
#
# Por que hace falta un .app y no alcanza el binario suelto: UNUserNotifications
# exige un bundle con identificador, y NSStatusItem necesita una app con
# activation policy. Un ejecutable pelado no tiene ni una cosa ni la otra.
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$PKG/build/iAmAwake.app"
VERSION="1.0.0"

echo "==> Compilando en release"
swift build --package-path "$PKG" -c release
BIN="$(swift build --package-path "$PKG" -c release --show-bin-path)"

echo "==> Armando el bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/iAmAwake" "$APP/Contents/MacOS/iAmAwake"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>iAmAwake</string>
    <key>CFBundleDisplayName</key><string>iAmAwake</string>
    <key>CFBundleIdentifier</key><string>dev.local.iamawake</string>
    <key>CFBundleExecutable</key><string>iAmAwake</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- App de barra de menu: sin icono en el Dock ni menu de ventana. -->
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Uso personal</string>
</dict>
</plist>
PLIST

echo "==> Firmando ad-hoc"
# La identidad "-" es la firma ad-hoc: no necesita cuenta de Apple. Sirve para
# correr en TU maquina; no sirve para distribuir a otras.
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# Sin esto Gatekeeper marca el .app como descargado/no confiable.
xattr -cr "$APP" 2>/dev/null || true

echo
echo "Listo: $APP"
echo
echo "Para instalarlo:"
echo "    cp -R \"$APP\" /Applications/"
echo "    xattr -cr /Applications/iAmAwake.app"
echo "    open /Applications/iAmAwake.app"

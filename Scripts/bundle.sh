#!/bin/bash
# Compila e monta Forge.app em dist/. Uso: Scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Forge.app"

cd "$ROOT"
ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c "$CONFIG" "${ARCHS[@]}" >/dev/null 2>&1; then
  ARCHS=()
  swift build -c "$CONFIG"
fi
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]+"${ARCHS[@]}"}" --show-bin-path)/Forge"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Forge"
cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d)/Forge.iconset"
swiftc -swift-version 5 -O "$ROOT/Scripts/icon/main.swift" -o "$(dirname "$ICONSET")/gen" >/dev/null
"$(dirname "$ICONSET")/gen" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Forge.icns"

codesign --force --sign - --identifier dev.mesquita.Forge "$APP" >/dev/null

echo "Pronto: $APP"

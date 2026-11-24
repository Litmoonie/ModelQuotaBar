#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/ModelQuotaBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$MACOS_DIR"

cp "$ROOT_DIR/.build/release/ModelQuotaBar" "$MACOS_DIR/ModelQuotaBar"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ModelQuotaBar</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.litmoonie.modelquotabar</string>
  <key>CFBundleName</key>
  <string>ModelQuotaBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.3.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Open-source local menu bar tool.</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${MODELQUOTABAR_SIGNING_IDENTITY:--}"

codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"

echo "Built $APP_DIR"

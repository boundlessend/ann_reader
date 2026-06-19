#!/bin/bash
# собирает release-бинарь в .app-бандл (sandbox, локализации en/ru/fr) и .dmg
set -euo pipefail

APP="ANN Reader"
EXE="ANNReaderApp"
DIST="dist"
BUNDLE="$DIST/$APP.app"
RES="$BUNDLE/Contents/Resources"

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$RES"
cp ".build/release/$EXE" "$BUNDLE/Contents/MacOS/$EXE"
cp "Resources/AppIcon.icns" "$RES/AppIcon.icns"
cp -R Resources/*.lproj "$RES/"   # таблицы локализации в бандл для Bundle.main

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>$APP</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>com.annreader.app</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 boundlessend</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>ru</string><string>fr</string></array>
</dict>
</plist>
PLIST

# ad-hoc подпись с sandbox-энтайтлментами
codesign --force --deep \
  --entitlements Resources/ANNReader.entitlements --sign - "$BUNDLE"

rm -f "$DIST/$APP"*.dmg
create-dmg "$BUNDLE" "$DIST" || true   # ненулевой код, если нет Developer ID - это ок для ad-hoc
echo "готово:"
ls -la "$DIST"

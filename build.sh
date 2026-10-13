#!/bin/bash
# Compila CamPanel.app (SwiftUI/AppKit + WKWebView). Requiere Xcode / Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/CamPanel.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "› Compilando…"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/main.swift -o build/CamPanel-arm64
swiftc -O -swift-version 5 -target x86_64-apple-macos13.0 Sources/main.swift -o build/CamPanel-x86_64
lipo -create build/CamPanel-arm64 build/CamPanel-x86_64 -output "$APP/Contents/MacOS/CamPanel"
rm build/CamPanel-arm64 build/CamPanel-x86_64

cp -R web "$APP/Contents/Resources/web"

if [ -f Icon/AppIcon.icns ]; then cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CamPanel</string>
  <key>CFBundleDisplayName</key><string>CamPanel</string>
  <key>CFBundleIdentifier</key><string>io.github.ssoler01.campanel</string>
  <key>CFBundleExecutable</key><string>CamPanel</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSLocalNetworkUsageDescription</key><string>CamPanel necesita acceder a tu red local para hablar con la cámara.</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "✓ Listo: $(pwd)/$APP"

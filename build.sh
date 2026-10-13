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
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
  <key>NSLocalNetworkUsageDescription</key><string>CamPanel needs access to your local network to talk to the camera.</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/es.lproj"
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<'STR'
"NSLocalNetworkUsageDescription" = "CamPanel needs access to your local network to talk to the camera.";
STR
cat > "$APP/Contents/Resources/es.lproj/InfoPlist.strings" <<'STR'
"NSLocalNetworkUsageDescription" = "CamPanel necesita acceder a tu red local para hablar con la cámara.";
STR

codesign --force --deep --sign - "$APP"
echo "✓ Listo: $(pwd)/$APP"

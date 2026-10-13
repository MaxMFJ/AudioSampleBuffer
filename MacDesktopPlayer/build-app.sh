#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
# Remove a stale Bridge bundle left by older builds. The provider clients now
# run in Swift, and the source Bridge remains in the repository for reference.
rm -rf "$BIN_DIR/MacDesktopPlayer_MacDesktopPlayer.bundle/Bridge"
APP_DIR=".build/MacDesktopPlayer.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/MacDesktopPlayer "$APP_DIR/Contents/MacOS/MacDesktopPlayer"
# Bundle.module for this SwiftPM executable resolves the resource bundle next
# to the .app bundle executable's application bundle URL, not under
# Contents/Resources. Keep the generated bundle at the .app root so packaged
# builds can load resources after being copied to /Applications.
rm -rf "$APP_DIR/MacDesktopPlayer_MacDesktopPlayer.bundle"
cp -R "$BIN_DIR/MacDesktopPlayer_MacDesktopPlayer.bundle" "$APP_DIR/"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacDesktopPlayer</string>
<key>CFBundleIdentifier</key><string>com.audiosamplebuffer.macdesktopplayer</string>
<key>CFBundleName</key><string>桌面音乐</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict>
  <key>NSExceptionDomains</key><dict>
    <key>126.net</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
    <key>163.com</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
    <key>qq.com</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
    <key>gtimg.cn</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
    <key>kugou.com</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
  </dict>
</dict>
</dict></plist>
PLIST
echo "Built $APP_DIR"

#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR=".build/MacDesktopPlayer.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/MacDesktopPlayer "$APP_DIR/Contents/MacOS/MacDesktopPlayer"
cp -R "$BIN_DIR/MacDesktopPlayer_MacDesktopPlayer.bundle" "$APP_DIR/Contents/Resources/"
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
</dict></plist>
PLIST
echo "Built $APP_DIR"

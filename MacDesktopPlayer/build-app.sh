#!/bin/sh
set -eu
cd "$(dirname "$0")"
BRIDGE_DIR="Sources/MacDesktopPlayer/Bridge"
BRIDGE_DEPENDENCY="$BRIDGE_DIR/node_modules/NeteaseCloudMusicApi/main.js"
if [ ! -f "$BRIDGE_DEPENDENCY" ]; then
  echo "Installing Mineradio Bridge dependencies..."
  (cd "$BRIDGE_DIR" && npm ci --omit=dev --ignore-scripts)
fi
if [ ! -x "$BRIDGE_DIR/runtime/node" ]; then
  NODE_RUNTIME="$(command -v node || true)"
  if [ -z "$NODE_RUNTIME" ]; then
    echo "Node.js is required to package the local Bridge" >&2
    exit 1
  fi
  mkdir -p "$BRIDGE_DIR/runtime"
  cp "$NODE_RUNTIME" "$BRIDGE_DIR/runtime/node"
  chmod +x "$BRIDGE_DIR/runtime/node"
fi
NODE_LIBRARY_NAME="$(otool -L "$BRIDGE_DIR/runtime/node" | awk '/libnode\..*dylib/{print $1; exit}' | xargs basename)"
NODE_LIBRARY=""
if [ -n "$NODE_LIBRARY_NAME" ]; then
  NODE_REAL="$(realpath "$(command -v node)")"
  NODE_LIBRARY="$(cd "$(dirname "$NODE_REAL")/.." && pwd)/lib/$NODE_LIBRARY_NAME"
fi
if [ -n "$NODE_LIBRARY" ] && [ -f "$NODE_LIBRARY" ] && [ ! -f "$BRIDGE_DIR/runtime/$NODE_LIBRARY_NAME" ]; then
  cp "$NODE_LIBRARY" "$BRIDGE_DIR/runtime/$NODE_LIBRARY_NAME"
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
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
</dict></plist>
PLIST
echo "Built $APP_DIR"

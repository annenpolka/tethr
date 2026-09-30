#!/bin/sh
set -eu
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
swift build --disable-sandbox --cache-path "$PWD/.cache/swiftpm" -c release
BIN_DIR="$(swift build --disable-sandbox --cache-path "$PWD/.cache/swiftpm" -c release --show-bin-path)"
APP="$PWD/dist/Tethr Native.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/TethrNative" "$APP/Contents/MacOS/TethrNative"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TethrNative</string>
<key>CFBundleIdentifier</key><string>com.tethr.lab.native</string>
<key>CFBundleName</key><string>Tethr Native</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"

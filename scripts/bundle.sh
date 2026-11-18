#!/bin/zsh
# Builds a release binary and wraps it in build/RepoRadar.app (menu bar only, no Dock icon).
set -euo pipefail

cd "${0:A:h}/.."
swift build -c release

app="build/RepoRadar.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/RepoRadar" "$app/Contents/MacOS/RepoRadar"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>RepoRadar</string>
    <key>CFBundleIdentifier</key><string>local.repo-radar</string>
    <key>CFBundleName</key><string>Repo Radar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $PWD/$app"

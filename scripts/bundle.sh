#!/bin/zsh
# Builds a release binary and wraps it in build/Kools.app (menu bar only, no Dock icon).
set -euo pipefail

cd "${0:A:h}/.."
swift build -c release

app="build/Kools.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Kools" "$app/Contents/MacOS/Kools"

# App icon: 😆, rendered fresh each build (no image files in the repo).
iconset="build/AppIcon.iconset"
swift scripts/make-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Kools</string>
    <key>CFBundleIdentifier</key><string>local.kools</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleName</key><string>Kools</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Sign with a real certificate when there is one. macOS ties the Accessibility
# grant to the signature, and an ad-hoc signature changes on every build, so
# the grant would be lost each time. Set KOOLS_SIGN_IDENTITY to override.
identity="${KOOLS_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ { print $2; exit }')}"
if [[ -n "$identity" ]]; then
    codesign --force --sign "$identity" "$app"
else
    echo "warning: no Apple Development certificate; signing ad-hoc. Accessibility must be re-granted after each build." >&2
    codesign --force --sign - "$app"
fi
echo "Built $PWD/$app"

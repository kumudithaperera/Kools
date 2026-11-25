#!/bin/zsh
# Builds Kools from source and installs it to /Applications.
#   git clone https://github.com/kumudithaperera/Kools.git && cd Kools && scripts/install.sh
set -euo pipefail

cd "${0:A:h}/.."

if ! command -v swift >/dev/null; then
    echo "error: Swift not found. Install Xcode from the App Store (or run: xcode-select --install), then try again." >&2
    exit 1
fi

scripts/bundle.sh

dest="/Applications/Kools.app"
if pgrep -x Kools >/dev/null; then
    echo "Quitting the running Kools..."
    pkill -x Kools || true
    sleep 1
fi
rm -rf "$dest"
cp -R build/Kools.app "$dest"
echo "Installed $dest"
open "$dest"

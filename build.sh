#!/bin/bash
# Usage: ./build.sh            -> builds build/ClaudeDash.app
#        ./build.sh install    -> also copies it to ~/Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/ClaudeDash.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeDash "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    mkdir -p ~/Applications
    pkill -x ClaudeDash || true
    rm -rf ~/Applications/ClaudeDash.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/ClaudeDash.app
    echo "Installed to ~/Applications/ClaudeDash.app"
fi

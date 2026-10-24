#!/bin/bash
# Build Spidolin.app with the Xcode Command Line Tools (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Spidolin.app
ARCH=$(uname -m)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target "$ARCH-apple-macos13.0" \
    -framework AppKit -framework Carbon -framework ServiceManagement \
    Sources/*.swift -o "$APP/Contents/MacOS/Spidolin"
cp Info.plist "$APP/Contents/"

# iCloud adds extended attributes that codesign refuses.
xattr -cr "$APP"
codesign --force --sign - "$APP" || echo "Warning: ad-hoc codesign failed"

echo "Built: $(pwd)/$APP"

# `bash build.sh install` copies the app to ~/Applications (per user, outside
# iCloud), a stable location for the "launch at login" setting.
if [[ "${1:-}" == "install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x Spidolin || true
    rm -rf "$HOME/Applications/Spidolin.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed: $HOME/Applications/Spidolin.app"
fi

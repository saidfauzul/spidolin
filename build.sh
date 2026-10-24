#!/bin/bash
# Build Spidolin.app with the Xcode Command Line Tools (no Xcode project needed).
#   bash build.sh           build for this Mac's architecture
#   bash build.sh install   ... and copy to ~/Applications
#   bash build.sh release   universal (arm64 + x86_64) build, zipped for download
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Spidolin.app
MODE="${1:-}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() { # compile <arch> <output>
    swiftc -O -target "$1-apple-macos13.0" \
        -framework AppKit -framework Carbon -framework ServiceManagement \
        Sources/*.swift -o "$2"
}

if [[ "$MODE" == "release" ]]; then
    compile arm64 build/Spidolin-arm64
    if compile x86_64 build/Spidolin-x86_64; then
        lipo -create build/Spidolin-arm64 build/Spidolin-x86_64 \
            -output "$APP/Contents/MacOS/Spidolin"
    else
        echo "Warning: x86_64 build failed, release is arm64 only"
        cp build/Spidolin-arm64 "$APP/Contents/MacOS/Spidolin"
    fi
    rm -f build/Spidolin-arm64 build/Spidolin-x86_64
else
    compile "$(uname -m)" "$APP/Contents/MacOS/Spidolin"
fi
cp Info.plist "$APP/Contents/"

# iCloud adds extended attributes that codesign refuses.
xattr -cr "$APP"
codesign --force --sign - "$APP" || echo "Warning: ad-hoc codesign failed"

echo "Built: $(pwd)/$APP"

# `bash build.sh install` copies the app to ~/Applications (per user, outside
# iCloud), a stable location for the "launch at login" setting.
if [[ "$MODE" == "install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x Spidolin || true
    rm -rf "$HOME/Applications/Spidolin.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed: $HOME/Applications/Spidolin.app"
fi

if [[ "$MODE" == "release" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
    ZIP="build/Spidolin-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Release: $(pwd)/$ZIP"
fi

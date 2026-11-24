#!/bin/sh
# Builds Amulet and installs it into ~/Applications.
set -eu
cd "$(dirname "$0")"

APP="$HOME/Applications/Amulet.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

if [ ! -f Profiles.swift ]; then
    echo "Profiles.swift is missing. Create it from the example and list your Chrome profiles:" >&2
    echo "  cp Profiles.example.swift Profiles.swift" >&2
    exit 1
fi

mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift Profiles.swift -o "$APP/Contents/MacOS/Amulet"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

# Stop a running copy so the next link starts the new build.
pkill -x Amulet || true

# Tell macOS the app exists and which link types it handles.
if [ -x "$LSREGISTER" ]; then "$LSREGISTER" -f "$APP"; fi

echo "Installed $APP"
echo "To make it the default browser: \"$APP/Contents/MacOS/Amulet\" --make-default"

#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_DIR="$SCRIPT_DIR/MacsBar.app"

echo "Building MacsBar..."
cd "$SCRIPT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$BUILD_DIR/MacsBar" "$APP_DIR/Contents/MacOS/MacsBar"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy Sparkle.framework into the app bundle
cp -R "$BUILD_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/"

# Add @executable_path/../Frameworks to the executable's rpath so it can find Sparkle
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/MacsBar"

# Code sign the app bundle. Set CODESIGN_IDENTITY env var to use a specific identity,
# otherwise falls back to ad-hoc signing (-).
SIGN_ID="${CODESIGN_IDENTITY:--}"
codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP_DIR"

echo "Done! App bundle created at: $APP_DIR"
echo ""
echo "To run:  open $APP_DIR"
echo "To install: cp -r $APP_DIR /Applications/"

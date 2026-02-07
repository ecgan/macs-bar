#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/build.config"

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

codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"

echo "Done! App bundle created at: $APP_DIR"
echo ""
echo "To run:  open $APP_DIR"
echo "To install: cp -r $APP_DIR /Applications/"

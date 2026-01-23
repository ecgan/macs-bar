#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_DIR="$SCRIPT_DIR/SuperbarApp.app"

echo "Building SuperbarApp..."
cd "$SCRIPT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/SuperbarApp" "$APP_DIR/Contents/MacOS/SuperbarApp"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Done! App bundle created at: $APP_DIR"
echo ""
echo "To run:  open $APP_DIR"
echo "To install: cp -r $APP_DIR /Applications/"

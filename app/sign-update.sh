#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_ZIP="$SCRIPT_DIR/MacsBar.zip"

if [ ! -f "$DIST_ZIP" ]; then
    echo "Error: MacsBar.zip not found. Please run notarize-app.sh first." >&2
    exit 1
fi

# Locate the Sparkle sign_update tool
SIGN_TOOL="$SCRIPT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"

if [ ! -f "$SIGN_TOOL" ]; then
    # Fallback to SPM build directory structure
    SIGN_TOOL=$(find "$SCRIPT_DIR/.build" -name "sign_update" -type f -perm +111 | head -n 1)
fi

if [ -z "$SIGN_TOOL" ] || [ ! -f "$SIGN_TOOL" ]; then
    echo "Error: Sparkle sign_update tool not found in .build directory." >&2
    echo "Please ensure you have built the app at least once." >&2
    exit 1
fi

echo "Signing MacsBar.zip for Sparkle update..."
"$SIGN_TOOL" "$DIST_ZIP"

#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/build.config" ]; then
    echo "Error: build.config not found. Copy build.config.example to build.config and configure it." >&2
    exit 1
fi
source "$SCRIPT_DIR/build.config"

APP_DIR="$SCRIPT_DIR/MacsBar.app"

if [ ! -d "$APP_DIR" ]; then
    echo "Error: MacsBar.app not found. Please run build-app.sh first." >&2
    exit 1
fi

# Determine how we are notarizing (Keychain profile vs explicit credentials)
if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
    echo "Using Keychain profile: $NOTARY_KEYCHAIN_PROFILE"
    NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else
    echo "Error: No notarization credentials configured in build.config." >&2
    echo "Please set NOTARY_KEYCHAIN_PROFILE." >&2
    exit 1
fi

SUBMIT_ZIP="$SCRIPT_DIR/MacsBar-Submit.zip"
DIST_ZIP="$SCRIPT_DIR/MacsBar.zip"

echo "Step 1: Packaging app for submission..."
rm -f "$SUBMIT_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$SUBMIT_ZIP"

echo "Step 2: Submitting to Apple Notary Service..."
xcrun notarytool submit "$SUBMIT_ZIP" "${NOTARY_ARGS[@]}" --wait

echo "Cleaning up submission zip..."
rm -f "$SUBMIT_ZIP"

echo "Step 3: Stapling notarization ticket to MacsBar.app..."
xcrun stapler staple "$APP_DIR"

echo "Step 4: Packaging final notarized MacsBar.zip..."
rm -f "$DIST_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_ZIP"

echo "Notarization and packaging complete! Created: $DIST_ZIP"

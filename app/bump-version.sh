#!/bin/bash
set -e

# Get the directory of the script and resolve path to Info.plist
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$SCRIPT_DIR/Info.plist"

# Verify that Info.plist exists
if [ ! -f "$INFO_PLIST" ]; then
    echo "Error: $INFO_PLIST not found." >&2
    exit 1
fi

# Ensure we are inside a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not a git repository." >&2
    exit 1
fi

# Extract current version using plutil
CURRENT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")
if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Could not extract current version from Info.plist." >&2
    exit 1
fi

# Determine new version
if [ -n "$1" ]; then
    NEW_VERSION="$1"
else
    # Calculate default bumped patch version
    if [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
        new_patch=$((patch + 1))
        DEFAULT_VERSION="$major.$minor.$new_patch"
    else
        echo "Error: Current version '$CURRENT_VERSION' is not in major.minor.patch (X.Y.Z) format." >&2
        exit 1
    fi

    # Prompt the user for the version
    read -p "Enter version number [$DEFAULT_VERSION]: " USER_INPUT
    if [ -z "$USER_INPUT" ]; then
        NEW_VERSION="$DEFAULT_VERSION"
    else
        NEW_VERSION="$USER_INPUT"
    fi
fi

# Check if tag already exists in git
if git rev-parse "$NEW_VERSION" >/dev/null 2>&1; then
    echo "Error: Git tag '$NEW_VERSION' already exists." >&2
    exit 1
fi

echo "Current version: $CURRENT_VERSION"
echo "Bumping version to: $NEW_VERSION"

# Update Info.plist using plutil
plutil -replace CFBundleVersion -string "$NEW_VERSION" "$INFO_PLIST"
plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" "$INFO_PLIST"

# Stage and commit the changes
git add "$INFO_PLIST"
git commit -m "Bump app version number to $NEW_VERSION"

# Create git tag
git tag "$NEW_VERSION"

echo "Successfully bumped version to $NEW_VERSION, committed, and tagged."

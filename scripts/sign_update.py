#!/usr/bin/env python3
import os
import sys
import re
import plistlib
import subprocess
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
APP_DIR = os.path.join(REPO_ROOT, 'app')
DIST_ZIP = os.path.join(APP_DIR, 'MacsBar.zip')
APPCAST_PATH = os.path.join(REPO_ROOT, 'docs', 'appcast.xml')
INFO_PLIST = os.path.join(APP_DIR, 'Info.plist')

def find_sign_tool():
    default_path = os.path.join(APP_DIR, '.build', 'artifacts', 'sparkle', 'Sparkle', 'bin', 'sign_update')
    if os.path.isfile(default_path) and os.access(default_path, os.X_OK):
        return default_path

    # Fallback search
    import glob
    search_pattern = os.path.join(APP_DIR, '.build', '**', 'sign_update')
    matches = glob.glob(search_pattern, recursive=True)
    for path in matches:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path

    return None

def get_app_version():
    if not os.path.exists(INFO_PLIST):
        print(f"Error: {INFO_PLIST} not found.", file=sys.stderr)
        sys.exit(1)
    with open(INFO_PLIST, 'rb') as f:
        plist = plistlib.load(f)
    version = plist.get('CFBundleShortVersionString')
    build = plist.get('CFBundleVersion')
    if not version or not build:
        print("Error: Could not read version or build from Info.plist.", file=sys.stderr)
        sys.exit(1)
    return version, build

def get_minimum_system_version():
    if not os.path.exists(INFO_PLIST):
        print(f"Error: {INFO_PLIST} not found.", file=sys.stderr)
        sys.exit(1)
    with open(INFO_PLIST, 'rb') as f:
        plist = plistlib.load(f)
    minimum_version = plist.get('LSMinimumSystemVersion')
    if not minimum_version:
        print("Error: Could not read LSMinimumSystemVersion from Info.plist.", file=sys.stderr)
        sys.exit(1)
    return minimum_version

def main():
    if not os.path.exists(DIST_ZIP):
        print(f"Error: {DIST_ZIP} not found. Please run notarize_app.py first.", file=sys.stderr)
        sys.exit(1)

    sign_tool = find_sign_tool()
    if not sign_tool:
        print("Error: Sparkle sign_update tool not found in .build directory.", file=sys.stderr)
        print("Please ensure you have built the app at least once.", file=sys.stderr)
        sys.exit(1)

    version, build = get_app_version()
    minimum_system_version = get_minimum_system_version()

    print(f"Signing MacsBar.zip for Sparkle update (v{version})...")
    try:
        result = subprocess.run([sign_tool, DIST_ZIP], capture_output=True, text=True, check=True)
        sign_output = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to run sign_update: {e}", file=sys.stderr)
        if e.stderr:
            print(e.stderr, file=sys.stderr)
        sys.exit(1)

    # Parse signature and length
    # Output format: sparkle:edSignature="xxxx" length="yyyy"
    sig_match = re.search(r'sparkle:edSignature="([^"]+)"', sign_output)
    len_match = re.search(r'length="([0-9]+)"', sign_output)

    if not sig_match or not len_match:
        print(f"Error: Could not parse signature and length from tool output:\n{sign_output}", file=sys.stderr)
        sys.exit(1)

    ed_signature = sig_match.group(1)
    length = len_match.group(1)

    # Generate RFC 2822 compliant pubDate
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

    # Define XML item block
    new_item = f"""        <item>
            <title>Version {version}</title>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{minimum_system_version}</sparkle:minimumSystemVersion>
            <pubDate>{pub_date}</pubDate>
            <enclosure
                url="https://github.com/ecgan/macs-bar/releases/download/{version}/MacsBar.zip"
                sparkle:edSignature="{ed_signature}"
                length="{length}"
                type="application/octet-stream" />
        </item>"""

    print(f"Updating appcast feed: {APPCAST_PATH}")
    if not os.path.exists(APPCAST_PATH):
        print(f"Error: {APPCAST_PATH} does not exist.", file=sys.stderr)
        sys.exit(1)

    with open(APPCAST_PATH, 'r', encoding='utf-8') as f:
        appcast_content = f.read()

    # Remove existing entry for the same version if it exists
    item_pattern = r'\s*<item>\s*<title>Version ' + re.escape(version) + r'</title>.*?</item>'
    appcast_content, count = re.subn(item_pattern, '', appcast_content, flags=re.DOTALL)

    # Insert new entry right below <language>en</language>
    lang_tag = "<language>en</language>"
    if lang_tag in appcast_content:
        appcast_content = appcast_content.replace(lang_tag, f"{lang_tag}\n{new_item}")
    else:
        # Fallback to after <channel>
        channel_tag = "<channel>"
        if channel_tag in appcast_content:
            appcast_content = appcast_content.replace(channel_tag, f"{channel_tag}\n{new_item}")
        else:
            print("Error: Could not find insert insertion target in appcast.xml", file=sys.stderr)
            sys.exit(1)

    # Normalize double blank lines if any
    appcast_content = re.sub(r'\n\s*\n\s*\n', '\n\n', appcast_content)

    with open(APPCAST_PATH, 'w', encoding='utf-8') as f:
        f.write(appcast_content)

    print(f"Successfully updated {APPCAST_PATH} for version {version}.")

    # Git add and commit
    print("Committing appcast.xml updates to git...")
    try:
        # Check if there are changes to commit
        subprocess.run(["git", "add", APPCAST_PATH], cwd=REPO_ROOT, check=True)
        status_res = subprocess.run(["git", "status", "--porcelain", APPCAST_PATH], cwd=REPO_ROOT, capture_output=True, text=True)
        if status_res.stdout.strip():
            commit_msg = f"Update appcast.xml for version {version}"
            subprocess.run(["git", "commit", "-m", commit_msg], cwd=REPO_ROOT, check=True)
            print(f"Successfully committed changes with message: '{commit_msg}'")
        else:
            print("No changes to appcast.xml detected. Skipping git commit.")
    except subprocess.CalledProcessError as e:
        print(f"Error committing updates to git: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()

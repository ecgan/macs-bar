#!/usr/bin/env python3
import os
import sys
import subprocess

from utils import load_build_config

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
APP_DIR = os.path.join(REPO_ROOT, 'app')

def main():
    config = load_build_config()
    notary_profile = config.get('NOTARY_KEYCHAIN_PROFILE')
    if not notary_profile:
        print("Error: NOTARY_KEYCHAIN_PROFILE not specified in build.config.", file=sys.stderr)
        sys.exit(1)

    target_app = os.path.join(APP_DIR, 'MacsBar.app')
    if not os.path.exists(target_app):
        print(f"Error: {target_app} not found. Please run build_app.py first.", file=sys.stderr)
        sys.exit(1)

    submit_zip = os.path.join(APP_DIR, 'MacsBar-Submit.zip')
    dist_zip = os.path.join(APP_DIR, 'MacsBar.zip')

    print("Step 1: Packaging app for submission...")
    if os.path.exists(submit_zip):
        os.remove(submit_zip)
    try:
        subprocess.run([
            "ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", target_app, submit_zip
        ], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to package submit zip: {e}", file=sys.stderr)
        sys.exit(1)

    print("Step 2: Submitting to Apple Notary Service...")
    try:
        subprocess.run([
            "xcrun", "notarytool", "submit", submit_zip,
            "--keychain-profile", notary_profile,
            "--wait"
        ], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: Notarization submission failed: {e}", file=sys.stderr)
        # Clean up submission zip on failure
        if os.path.exists(submit_zip):
            os.remove(submit_zip)
        sys.exit(1)

    print("Cleaning up submission zip...")
    if os.path.exists(submit_zip):
        os.remove(submit_zip)

    print("Step 3: Stapling notarization ticket to MacsBar.app...")
    try:
        subprocess.run(["xcrun", "stapler", "staple", target_app], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: Stapling ticket failed: {e}", file=sys.stderr)
        sys.exit(1)

    print("Step 4: Packaging final notarized MacsBar.zip...")
    if os.path.exists(dist_zip):
        os.remove(dist_zip)
    try:
        subprocess.run([
            "ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", target_app, dist_zip
        ], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to package final zip: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Notarization and packaging complete! Created: {dist_zip}")

if __name__ == '__main__':
    main()

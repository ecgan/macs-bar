#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile

from utils import load_build_config

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
APP_DIR = os.path.join(REPO_ROOT, 'app')
APP_NAME = 'MacsBar.app'
DMG_NAME = 'MacsBar.dmg'
VOLUME_NAME = 'Macs Bar'


def run_step(command, error_message):
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as error:
        print(f"Error: {error_message}: {error}", file=sys.stderr)
        sys.exit(1)


def main():
    config = load_build_config()
    codesign_identity = config.get('CODESIGN_IDENTITY')
    notary_profile = config.get('NOTARY_KEYCHAIN_PROFILE')
    if not codesign_identity or codesign_identity == '-':
        print(
            "Error: A Developer ID Application identity must be specified "
            "in build.config.",
            file=sys.stderr,
        )
        sys.exit(1)
    if not notary_profile:
        print("Error: NOTARY_KEYCHAIN_PROFILE not specified in build.config.", file=sys.stderr)
        sys.exit(1)

    target_app = os.path.join(APP_DIR, APP_NAME)
    if not os.path.exists(target_app):
        print(f"Error: {target_app} not found. Please run build_app.py first.", file=sys.stderr)
        sys.exit(1)

    dist_dmg = os.path.join(APP_DIR, DMG_NAME)

    print("Step 1: Verifying MacsBar.app code signature...")
    run_step(
        ["codesign", "--verify", "--deep", "--strict", "--verbose=2", target_app],
        "App code signature verification failed",
    )

    print("Step 2: Creating drag-and-drop disk image...")
    if os.path.exists(dist_dmg):
        os.remove(dist_dmg)

    with tempfile.TemporaryDirectory(prefix="macsbar-dmg-") as staging_dir:
        staged_app = os.path.join(staging_dir, APP_NAME)
        run_step(
            ["ditto", target_app, staged_app],
            "Failed to stage app bundle",
        )
        os.symlink("/Applications", os.path.join(staging_dir, "Applications"))
        run_step(
            [
                "hdiutil",
                "create",
                "-volname", VOLUME_NAME,
                "-fs", "APFS",
                "-format", "ULFO",
                "-nospotlight",
                "-srcfolder", staging_dir,
                dist_dmg,
            ],
            "Failed to create disk image",
        )

    print(f"Step 3: Signing disk image using identity: {codesign_identity}...")
    run_step(
        [
            "codesign",
            "--force",
            "--timestamp",
            "--sign", codesign_identity,
            dist_dmg,
        ],
        "Disk image signing failed",
    )

    print("Step 4: Submitting disk image to Apple Notary Service...")
    run_step(
        [
            "xcrun", "notarytool", "submit", dist_dmg,
            "--keychain-profile", notary_profile,
            "--wait",
        ],
        "Notarization submission failed",
    )

    print("Step 5: Stapling and validating notarization ticket...")
    run_step(
        ["xcrun", "stapler", "staple", dist_dmg],
        "Stapling ticket failed",
    )
    run_step(
        ["xcrun", "stapler", "validate", dist_dmg],
        "Stapled ticket validation failed",
    )

    print("Step 6: Verifying final disk image...")
    run_step(
        ["hdiutil", "verify", dist_dmg],
        "Disk image verification failed",
    )
    run_step(
        ["codesign", "--verify", "--verbose=2", dist_dmg],
        "Disk image code signature verification failed",
    )

    print(f"Notarization and packaging complete! Created: {dist_dmg}")

if __name__ == '__main__':
    main()

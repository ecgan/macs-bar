#!/usr/bin/env python3
import os
import sys
import plistlib
import subprocess
import re

# Get repo directories
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
INFO_PLIST = os.path.join(REPO_ROOT, 'app', 'Info.plist')
VERSION_RE = re.compile(r'^([0-9]+)\.([0-9]+)\.([0-9]+)$')

def check_git_status():
    try:
        subprocess.run(["git", "rev-parse", "--is-inside-work-tree"], cwd=REPO_ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        print("Error: Not a git repository.", file=sys.stderr)
        sys.exit(1)

def get_current_version():
    if not os.path.exists(INFO_PLIST):
        print(f"Error: {INFO_PLIST} not found.", file=sys.stderr)
        sys.exit(1)

    with open(INFO_PLIST, 'rb') as f:
        plist = plistlib.load(f)

    version = plist.get('CFBundleShortVersionString')
    if not version:
        print("Error: Could not extract CFBundleShortVersionString from Info.plist.", file=sys.stderr)
        sys.exit(1)
    return version

def tag_exists(tag):
    result = subprocess.run(["git", "rev-parse", tag], cwd=REPO_ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def validate_version(version):
    if not VERSION_RE.match(version):
        print(f"Error: '{version}' is not a valid major.minor.patch version.", file=sys.stderr)
        sys.exit(1)

def main():
    check_git_status()
    current_version = get_current_version()

    # Determine new version
    if len(sys.argv) > 1:
        new_version = sys.argv[1]
    else:
        # Calculate default patch bump (X.Y.Z -> X.Y.(Z+1))
        match = VERSION_RE.match(current_version)
        if not match:
            print(f"Error: Current version '{current_version}' is not in major.minor.patch format.", file=sys.stderr)
            sys.exit(1)
        major, minor, patch = match.groups()
        default_version = f"{major}.{minor}.{int(patch) + 1}"

        try:
            user_input = input(f"Enter version number [{default_version}]: ").strip()
            new_version = user_input if user_input else default_version
        except KeyboardInterrupt:
            print("\nAborted.")
            sys.exit(1)

    validate_version(new_version)

    if tag_exists(new_version):
        print(f"Error: Git tag '{new_version}' already exists.", file=sys.stderr)
        sys.exit(1)

    print(f"Current version: {current_version}")
    print(f"Bumping version to: {new_version}")

    # Update Info.plist
    with open(INFO_PLIST, 'rb') as f:
        plist = plistlib.load(f)

    plist['CFBundleVersion'] = new_version
    plist['CFBundleShortVersionString'] = new_version

    with open(INFO_PLIST, 'wb') as f:
        plistlib.dump(plist, f)

    # Git operations
    try:
        subprocess.run(["git", "add", INFO_PLIST], cwd=REPO_ROOT, check=True)
        subprocess.run(["git", "commit", "-m", f"Bump app version number to {new_version}"], cwd=REPO_ROOT, check=True)
        subprocess.run(["git", "tag", new_version], cwd=REPO_ROOT, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Git operations failed: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Successfully bumped version to {new_version}, committed, and tagged.")

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
APP_DIR = os.path.join(REPO_ROOT, 'app')
BUILD_CONFIG = os.path.join(APP_DIR, 'build.config')

def load_build_config():
    config = {}
    if not os.path.exists(BUILD_CONFIG):
        print(f"Error: build.config not found at {BUILD_CONFIG}.", file=sys.stderr)
        print("Please copy build.config.example to build.config and configure your signing identity.", file=sys.stderr)
        sys.exit(1)
    
    with open(BUILD_CONFIG, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                key, val = line.split('=', 1)
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                config[key] = val
    return config

def main():
    config = load_build_config()
    codesign_identity = config.get('CODESIGN_IDENTITY')
    if not codesign_identity:
        print("Error: CODESIGN_IDENTITY not specified in build.config.", file=sys.stderr)
        sys.exit(1)
        
    build_dir = os.path.join(APP_DIR, '.build', 'release')
    dest_app_dir = os.path.join(APP_DIR, 'MacsBar.app')
    icon_file = os.path.join(APP_DIR, 'Resources', 'AppIcon.icns')
    
    print("Building MacsBar...")
    try:
        subprocess.run(["swift", "build", "-c", "release"], cwd=APP_DIR, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: Swift build failed: {e}", file=sys.stderr)
        sys.exit(1)
        
    print("Creating app bundle...")
    if os.path.exists(dest_app_dir):
        shutil.rmtree(dest_app_dir)
        
    macos_dir = os.path.join(dest_app_dir, 'Contents', 'MacOS')
    resources_dir = os.path.join(dest_app_dir, 'Contents', 'Resources')
    frameworks_dir = os.path.join(dest_app_dir, 'Contents', 'Frameworks')
    
    os.makedirs(macos_dir, exist_ok=True)
    os.makedirs(resources_dir, exist_ok=True)
    os.makedirs(frameworks_dir, exist_ok=True)
    
    shutil.copy2(os.path.join(build_dir, 'MacsBar'), os.path.join(macos_dir, 'MacsBar'))
    shutil.copy2(os.path.join(APP_DIR, 'Info.plist'), os.path.join(dest_app_dir, 'Contents', 'Info.plist'))
    
    if os.path.exists(icon_file):
        shutil.copy2(icon_file, os.path.join(resources_dir, 'AppIcon.icns'))
        
    # Copy Sparkle.framework (preserves symlinks inside frameworks)
    src_framework = os.path.join(build_dir, 'Sparkle.framework')
    dest_framework = os.path.join(frameworks_dir, 'Sparkle.framework')
    if os.path.exists(src_framework):
        shutil.copytree(src_framework, dest_framework, symlinks=True)
    else:
        print(f"Warning: Sparkle.framework not found at {src_framework}", file=sys.stderr)
        
    # Add rpath
    print("Configuring rpath...")
    try:
        subprocess.run([
            "install_name_tool",
            "-add_rpath",
            "@executable_path/../Frameworks",
            os.path.join(macos_dir, 'MacsBar')
        ], check=True)
    except subprocess.CalledProcessError as e:
        # Ignore if rpath already exists
        pass
        
    # Code sign
    print(f"Signing MacsBar.app using identity: {codesign_identity}...")
    try:
        subprocess.run([
            "codesign",
            "--force",
            "--deep",
            "--options", "runtime",
            "--timestamp",
            "--sign", codesign_identity,
            dest_app_dir
        ], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: Code signing failed: {e}", file=sys.stderr)
        sys.exit(1)
        
    print(f"Done! App bundle created at: {dest_app_dir}")
    print("\nTo run:  open " + dest_app_dir)
    print("To install: ditto " + dest_app_dir + " /Applications/MacsBar.app")

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
import os
import sys


def load_build_config():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    build_config = os.path.join(repo_root, 'app', 'build.config')

    config = {}
    if not os.path.exists(build_config):
        print(f"Error: build.config not found at {build_config}.", file=sys.stderr)
        print("Please copy build.config.example to build.config and configure your signing identity.", file=sys.stderr)
        sys.exit(1)

    with open(build_config, 'r', encoding='utf-8') as f:
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

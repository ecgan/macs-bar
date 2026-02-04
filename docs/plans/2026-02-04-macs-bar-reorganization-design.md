# Macs Bar Codebase Reorganization

## Overview

Reorganize the MacWindowTracker codebase to:
1. Rename the project to "Macs Bar" (a wordplay on Mars Bar)
2. Move SuperbarApp out of Examples/ since it's the main distributed product
3. Create clear separation between library and app with co-located tests

## Naming Convention

| Context | Name |
|---------|------|
| GitHub Repo | `macs-bar` |
| CLI Command | `macsbar` |
| App Display Name | `Macs Bar` |
| Bundle/Process | `MacsBar.app` |
| Library Package | `MacWindowTracker` (unchanged for now) |

## New Structure

```
macs-bar/
├── lib/
│   ├── Sources/
│   │   └── MacWindowTracker/      # Library code (6 modules)
│   ├── Tests/
│   │   └── MacWindowTrackerTests/
│   └── Package.swift
│
├── app/
│   ├── Sources/
│   │   └── MacsBar/               # App code
│   ├── Tests/
│   │   └── MacsBarTests/          # App-specific tests (empty initially)
│   ├── Package.swift
│   ├── Info.plist
│   └── build-app.sh
│
├── docs/
│   └── plans/
│
└── README.md
```

## Migration Plan

### File Moves

| From | To |
|------|-----|
| `Sources/MacWindowTracker/` | `lib/Sources/MacWindowTracker/` |
| `Tests/MacWindowTrackerTests/` | `lib/Tests/MacWindowTrackerTests/` |
| `Package.swift` | `lib/Package.swift` |
| `Examples/SuperbarApp/Sources/SuperbarApp/` | `app/Sources/MacsBar/` |
| `Examples/SuperbarApp/Package.swift` | `app/Package.swift` |
| `Examples/SuperbarApp/Info.plist` | `app/Info.plist` |
| `Examples/SuperbarApp/build-app.sh` | `app/build-app.sh` |

### File Edits

**app/Package.swift:**
- Rename package and target from `SuperbarApp` to `MacsBar`
- Update dependency path from `"../.."` to `"../lib"`

**app/build-app.sh:**
- Update build paths
- Change bundle name from `Superbar.app` to `MacsBar.app`

**app/Info.plist:**
- Update `CFBundleIdentifier` to use `MacsBar`
- Update `CFBundleName` to `Macs Bar`
- Update `CFBundleExecutable` to `MacsBar`

**app/Sources/MacsBar/*.swift:**
- Rename source files: `SuperbarApp.swift` → `MacsBarApp.swift`, etc.
- Update class/struct names containing "Superbar" to "MacsBar"
- Update any string literals referencing "Superbar"

**lib/Package.swift:**
- Verify paths still work (should be fine, relative paths unchanged)

### Manual Steps

- Rename GitHub repository: `MacWindowTracker` → `macs-bar`

## Developer Workflow

After reorganization, the workflow remains simple:

```bash
# Run the app (builds lib automatically)
cd app && swift run

# Run library tests
cd lib && swift test

# Run app tests
cd app && swift test
```

Optional: Add root-level Makefile for convenience.

## Verification

After reorganization:
1. `cd lib && swift build` succeeds
2. `cd lib && swift test` passes
3. `cd app && swift build` succeeds
4. `cd app && swift run` launches the app
5. App functions correctly (panels appear, window tracking works)

## Decisions

- **Monorepo**: Keep library and app in same repository for simpler development
- **Library name**: Keep `MacWindowTracker` for now (can rename later)
- **Test co-location**: Tests live within each package (lib/Tests, app/Tests)
- **Do rename + reorg together**: One atomic change, touching same files anyway

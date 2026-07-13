# Macs Bar Release Guide

This document outlines the procedure for preparing, building, signing, and publishing updates for Macs Bar using the Sparkle update framework.

---

## 📋 Table of Contents

1. [Initial Setup (One-Time)](#initial-setup-one-time)
   - [1. Configure Code Signing](#1-configure-code-signing)
   - [2. Configure Notarization Credentials](#2-configure-notarization-credentials)
   - [3. Run Initial Build](#3-run-initial-build)
   - [4. Generate Sparkle EdDSA Keys](#4-generate-sparkle-eddsa-keys)
   - [5. Configure Update Feed URL](#5-configure-update-feed-url)
   - [6. Enable GitHub Pages](#6-enable-github-pages)
   - [7. Initialize the Appcast File](#7-initialize-the-appcast-file)
2. [Step-by-Step Release Process](#step-by-step-release-process)
   - [Step 1: Update Version Info](#step-1-update-version-info)
   - [Step 2: Build the App Bundle](#step-2-build-the-app-bundle)
   - [Step 3: Notarize and Staple the App](#step-3-notarize-and-staple-the-app)
   - [Step 4: Sign the Archive and Update the Appcast Feed](#step-4-sign-the-archive-and-update-the-appcast-feed)
   - [Step 5: Push Commits and Tag to GitHub](#step-5-push-commits-and-tag-to-github)
   - [Step 6: Create a GitHub Release](#step-6-create-a-github-release)
3. [🛠️ Local Installation & Verification](#️-local-installation--verification)

---

## Initial Setup (One-Time)

Before performing your first Sparkle-enabled release, complete these initial configuration steps.

> [!NOTE]
> All release scripts are Python scripts located in the `scripts/` folder at the repository root. They can be run from the repository root without any `cd` needed (e.g. `./scripts/build_app.py`). Python 3 must be available on your system, which is standard on macOS.

### 1. Configure Code Signing

To avoid exposing personal developer signing identities in public documentation or scripts, configuration is managed via a machine-specific `build.config` file. This file is configured in the `.gitignore` to prevent it from being committed.

1. Copy the example configuration:

   ```bash
   cp app/build.config.example app/build.config
   ```

2. Open `app/build.config` and set your personal codesigning identity:

   ```bash
   CODESIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"
   ```

   > [!TIP]
   > You can list your available macOS signing identities by running:
   >
   > ```bash
   > security find-identity -v -p codesigning
   > ```

### 2. Configure Notarization Credentials

To automate notarization without storing your Apple Account password in plaintext on your disk, you should save your credentials in the macOS Keychain.

#### A. Generate an App-Specific Password

1. Go to [account.apple.com](https://account.apple.com) and sign in.
2. Under **Sign-In and Security**, click **App-Specific Passwords**.
3. Select **Generate an app-specific password**, enter a label (e.g., `notarytool`), and click **Create**.
4. Copy the generated 16-character password (formatted as `xxxx-xxxx-xxxx-xxxx`).

#### B. Store Credentials in macOS Keychain

Open your terminal and run the following command to store the credentials under a profile named `notary-macsbar`. Replace the email and team ID with your own (your Team ID is part of your Developer ID Application certificate name):

```bash
xcrun notarytool store-credentials "notary-macsbar" \
  --apple-id "your-apple-id@email.com" \
  --team-id "your-10-char-team-id"
```

When prompted, paste the **App-Specific Password** you generated in the previous step.

#### C. Reference the Profile in `build.config`

Open `app/build.config` and add the keychain profile name:

```bash
# RECOMMENDED (Secure): Use a macOS Keychain profile name.
NOTARY_KEYCHAIN_PROFILE="notary-macsbar"
```

### 3. Run Initial Build

Run the build script once to fetch dependencies (via Swift Package Manager (SPM)) and compile the app. This makes Sparkle's command-line tools available in `app/.build/` for the key generation step below.

```bash
./scripts/build_app.py
```

### 4. Generate Sparkle EdDSA Keys

Sparkle updates must be signed using an EdDSA (Ed25519) key pair.

1. Generate the key pair using Sparkle's `generate_keys` tool:

   ```bash
   app/.build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

2. This tool outputs two keys:
   - **Private Key**: Saved to your local login keychain or a secure private file.
     > [!CAUTION]
     > **NEVER commit the private key to GitHub.** Keep it secure on your local machine.
   - **Public Key**: Printed in the terminal.
3. Open `app/Info.plist` and add/replace the public key inside the `<dict>` block:

   ```xml
   <key>SUPublicEDKey</key>
   <string>YOUR_SPARKLE_PUBLIC_ED_KEY</string>
   ```

### 5. Configure Update Feed URL

Ensure the updates URL is configured in `app/Info.plist` so that the running application knows where to poll for updates:

```xml
<key>SUFeedURL</key>
<string>https://ecgan.github.io/macs-bar/appcast.xml</string>
```

### 6. Enable GitHub Pages

GitHub Pages is used to host the update feed (`appcast.xml`).

1. Go to your repository settings on GitHub.
2. Navigate to **Pages** in the left sidebar.
3. Under **Build and deployment**, select **Deploy from a branch**.
4. Set the branch to `main` and select the `/docs` folder as the source directory.
5. Click **Save**.

### 7. Initialize the Appcast File

Ensure a basic structure is ready in `docs/appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Macs Bar Updates</title>
        <link>https://github.com/ecgan/macs-bar</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
        <!-- Release items will be prepended here -->
    </channel>
</rss>
```

---

## Step-by-Step Release Process

Perform these steps for each new version you publish.

### Step 1: Update Version Info

Before compiling the app, update the version identifiers in `app/Info.plist` to match the target release.

Run the version bump script from the repository root:

```bash
./scripts/bump_version.py [optional-version-number]
```

- If you don't provide a version number, it will prompt you with the next patch version as a default. Press **Enter** to accept it, or type your desired version.
- If you provide a version number (e.g., `./scripts/bump_version.py 0.2.0`), it will update the version immediately without prompting.

This script updates both `CFBundleVersion` and `CFBundleShortVersionString` in `app/Info.plist`, stages and commits the change, and tags the commit with the new version number.

> [!NOTE]
> Sparkle compares `CFBundleVersion` (or `CFBundleShortVersionString` if configured) to determine if a newer version is available.

### Step 2: Build the App Bundle

Compile the production bundle from the repository root:

```bash
./scripts/build_app.py
```

_This script compiles the release bundle, embeds `Sparkle.framework`, sets up RPath, and signs the app with hardened runtime and a secure timestamp using the `CODESIGN_IDENTITY` specified in your local `app/build.config`._

### Step 3: Notarize and Staple the App

Notarize the application using the Apple Notary Service so that users can run it without Gatekeeper warnings. This script will zip the app, submit it, wait for Apple's approval, staple the notarization ticket, and output the final `app/MacsBar.zip`:

```bash
./scripts/notarize_app.py
```

> [!IMPORTANT]
> Notarization and stapling **must** occur before generating the Sparkle signature. Stapling modifies the `.app` bundle (it adds the ticket to it), which changes the file signature of the final `.zip` archive.

### Step 4: Sign the Archive and Update the Appcast Feed

Sign the final `app/MacsBar.zip` archive and automatically update `docs/appcast.xml` with the new release entry:

```bash
./scripts/sign_update.py
```

This script will:

1. Run Sparkle's `sign_update` tool on `app/MacsBar.zip` to generate the EdDSA signature and file length.
2. Insert a new `<item>` entry into `docs/appcast.xml` (or replace an existing entry for the same version).
3. Automatically commit `docs/appcast.xml` with the message `Update appcast.xml for version <version_number>`.

### Step 5: Push Commits and Tag to GitHub

Push all local commits (version bump + appcast update) and the version tag to `main`. This also triggers GitHub Pages to publish the updated `appcast.xml`:

```bash
git push origin main --tags
```

> [!IMPORTANT]
> Push **before** creating the GitHub Release. This ensures the tag exists on the remote and that `--generate-notes` can correctly reference all commits when generating release notes.

### Step 6: Create a GitHub Release

Upload the signed archive `app/MacsBar.zip` as a release asset under the version tag (e.g. `0.2.0`).

Using the GitHub CLI (`gh`):

```bash
gh release create 0.2.0 app/MacsBar.zip --title "0.2.0" --generate-notes
```

---

## 🛠️ Local Installation & Verification

To install your newly compiled application locally for manual testing:

```bash
# Copy the app to the Applications folder
# NOTE: Use ditto (not cp -r) to correctly preserve symlinks inside
# framework bundles like Sparkle.framework
ditto app/MacsBar.app /Applications/MacsBar.app

# Open and run the installed application
open /Applications/MacsBar.app
```

# Macs Bar Release Guide

This document outlines the procedure for preparing, building, signing, and publishing updates for Macs Bar using the Sparkle update framework.

---

## 📋 Table of Contents

1. [Initial Setup (One-Time)](#initial-setup-one-time)
   - [1. Configure Code Signing](#1-configure-code-signing)
   - [2. Generate Sparkle EdDSA Keys](#2-generate-sparkle-eddsa-keys)
   - [3. Configure Update Feed URL](#3-configure-update-feed-url)
   - [4. Enable GitHub Pages](#4-enable-github-pages)
   - [5. Initialize the Appcast File](#5-initialize-the-appcast-file)
2. [Step-by-Step Release Process](#step-by-step-release-process)
   - [Step 1: Update Version Info](#step-1-update-version-info)
   - [Step 2: Build the App Bundle](#step-2-build-the-app-bundle)
   - [Step 3: Create the Compressed Archive](#step-3-create-the-compressed-archive)
   - [Step 4: Sign the Archive](#step-4-sign-the-archive)
   - [Step 5: Create a GitHub Release](#step-5-create-a-github-release)
   - [Step 6: Update the Appcast Update Feed](#step-6-update-the-appcast-update-feed)
   - [Step 7: Deploy the Update Feed](#step-7-deploy-the-update-feed)
3. [🛠️ Local Installation & Verification](#️-local-installation--verification)

---

## Initial Setup (One-Time)

Before performing your first Sparkle-enabled release, complete these initial configuration steps.

### 1. Configure Code Signing

To avoid exposing personal developer signing identities in public documentation or scripts, configuration is managed via a machine-specific `build.config` file. This file is configured in the `.gitignore` to prevent it from being committed.

1. Navigate to the `app` directory:

   ```bash
   cd app
   ```

2. Copy the example configuration:

   ```bash
   cp build.config.example build.config
   ```

3. Open `build.config` and set your personal codesigning identity:

   ```bash
   CODESIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"
   ```

   > [!TIP]
   > You can list your available macOS signing identities by running:
   >
   > ```bash
   > security find-identity -v -p codesigning
   > ```

### 2. Generate Sparkle EdDSA Keys

Sparkle updates must be signed using an EdDSA (Ed25519) key pair.

1. Generate the key pair using Sparkle's `generate_keys` tool (typically included in the Sparkle distribution):

   ```bash
   ./path/to/sparkle/bin/generate_keys
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

### 3. Configure Update Feed URL

Ensure the updates URL is configured in `app/Info.plist` so that the running application knows where to poll for updates:

```xml
<key>SUFeedURL</key>
<string>https://ecgan.github.io/macs-bar/appcast.xml</string>
```

### 4. Enable GitHub Pages

GitHub Pages is used to host the update feed (`appcast.xml`).

1. Go to your repository settings on GitHub.
2. Navigate to **Pages** in the left sidebar.
3. Under **Build and deployment**, select **Deploy from a branch**.
4. Set the branch to `main` and select the `/docs` folder as the source directory.
5. Click **Save**.

### 5. Initialize the Appcast File

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

- **`CFBundleVersion`**: A unique, incrementing integer representing the build number (e.g. `2`).
- **`CFBundleShortVersionString`**: The user-visible semantic version (e.g., `0.2.0`).

> [!NOTE]
> Sparkle compares `CFBundleVersion` (or `CFBundleShortVersionString` if configured) to determine if a newer version is available.

### Step 2: Build the App Bundle

Navigate to the `app` directory and compile the production bundle:

```bash
cd app
./build-app.sh
```

_This script compiles the release bundle, embeds `Sparkle.framework`, sets up RPath, and signs the app using the `CODESIGN_IDENTITY` specified in your local `build.config`._

### Step 3: Create the Compressed Archive

Compress the app bundle using macOS `ditto` instead of generic `zip`. This preserves Finder attributes, resource forks, and necessary code-signing metadata:

```bash
ditto -c -k --sequesterRsrc --keepParent MacsBar.app MacsBar.zip
```

### Step 4: Sign the Archive

Sign the `.zip` archive using Sparkle's `sign_update` tool and your private EdDSA key:

```bash
/path/to/sparkle/bin/sign_update MacsBar.zip
```

_(Adjust `/path/to/sparkle/bin/` to point to the location of Sparkle's tools on your machine)._

This command prints a signature and length. **Copy these two values:**

```text
sparkle:edSignature="xxxxxx..." length="yyyyyy"
```

### Step 5: Create a GitHub Release

Upload the signed archive `MacsBar.zip` as a release asset under a new tag corresponding to your version (e.g. `v0.2.0`).

Using the GitHub CLI (`gh`):

```bash
gh release create v0.2.0 MacsBar.zip --title "v0.2.0" --notes "Release notes here"
```

### Step 6: Update the Appcast Update Feed

Open `docs/appcast.xml` and add a new `<item>` entry inside the `<channel>` tag. Place it above any older releases:

```xml
<item>
    <title>Version 0.2.0</title>
    <sparkle:version>2</sparkle:version>
    <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <pubDate>Mon, 25 May 2026 22:15:53 +0800</pubDate>
    <enclosure
        url="https://github.com/ecgan/macs-bar/releases/download/v0.2.0/MacsBar.zip"
        sparkle:edSignature="PASTE_SIGNATURE_HERE"
        length="PASTE_LENGTH_HERE"
        type="application/octet-stream" />
</item>
```

#### Core Fields Explained

- **`sparkle:version`**: Must match `CFBundleVersion` in the app's `Info.plist`.
- **`sparkle:shortVersionString`**: Must match `CFBundleShortVersionString` in the app's `Info.plist`.
- **`pubDate`**: The publication timestamp. Use RFC 822/RFC 2822 format (e.g., `date -u +'%a, %d %b %Y %H:%M:%S GMT'`).
- **`url`**: The direct download URL for the signed zip asset on GitHub Releases.
- **`sparkle:edSignature`**: The EdDSA signature string copied from Step 4.
- **`length`**: The file size in bytes copied from Step 4.

### Step 7: Deploy the Update Feed

Commit and push the updated `appcast.xml` to `main`. This triggers GitHub Pages to publish the new updates XML file:

```bash
git add docs/appcast.xml
git commit -m "chore: publish release v0.2.0 appcast"
git push origin main
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

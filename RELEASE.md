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
   - [Step 4: Sign the Final Archive for Sparkle](#step-4-sign-the-final-archive-for-sparkle)
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
cd app
./build-app.sh
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

_This script compiles the release bundle, embeds `Sparkle.framework`, sets up RPath, and signs the app with hardened runtime and a secure timestamp using the `CODESIGN_IDENTITY` specified in your local `build.config`._

### Step 3: Notarize and Staple the App

Notarize the application using the Apple Notary Service so that users can run it without Gatekeeper warnings. This script will zip the app, submit it, wait for Apple's approval, staple the notarization ticket, and output the final `MacsBar.zip`:

```bash
./notarize-app.sh
```

> [!IMPORTANT]
> Notarization and stapling **must** occur before generating the Sparkle signature. Stapling modifies the `.app` bundle (it adds the ticket to it), which changes the file signature of the final `.zip` archive.

### Step 4: Sign the Final Archive for Sparkle

Sign the final `MacsBar.zip` archive using Sparkle's `sign_update` tool:

```bash
./sign-update.sh
```

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

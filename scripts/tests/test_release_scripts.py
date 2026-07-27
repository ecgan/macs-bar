import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

import notarize_app
import sign_update


class NotarizeAppTests(unittest.TestCase):
    def test_creates_signs_notarizes_and_verifies_dmg(self):
        with tempfile.TemporaryDirectory() as app_dir:
            Path(app_dir, notarize_app.APP_NAME).mkdir()

            def run_command(command, **kwargs):
                if command[0] == "ditto":
                    Path(command[2]).mkdir()
                if command[:2] == ["hdiutil", "create"]:
                    source_dir = Path(command[command.index("-srcfolder") + 1])
                    applications_link = source_dir / "Applications"
                    self.assertTrue((source_dir / notarize_app.APP_NAME).is_dir())
                    self.assertTrue(applications_link.is_symlink())
                    self.assertEqual("/Applications", os.readlink(applications_link))
                return subprocess.CompletedProcess(command, 0)

            with (
                mock.patch.object(notarize_app, "APP_DIR", app_dir),
                mock.patch.object(
                    notarize_app,
                    "load_build_config",
                    return_value={
                        "CODESIGN_IDENTITY": "Developer ID Application: Test",
                        "NOTARY_KEYCHAIN_PROFILE": "test-notary-profile",
                    },
                ),
                mock.patch.object(
                    notarize_app.subprocess,
                    "run",
                    side_effect=run_command,
                ) as run,
            ):
                notarize_app.main()

        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(9, len(commands))
        self.assertEqual(
            ["codesign", "--verify", "--deep", "--strict", "--verbose=2"],
            commands[0][:-1],
        )
        self.assertEqual("ditto", commands[1][0])
        self.assertEqual("hdiutil", commands[2][0])
        self.assertIn("-fs", commands[2])
        self.assertIn("APFS", commands[2])
        self.assertIn("-format", commands[2])
        self.assertIn("ULFO", commands[2])
        self.assertEqual(
            [
                "codesign",
                "--force",
                "--timestamp",
                "--sign",
                "Developer ID Application: Test",
                os.path.join(app_dir, notarize_app.DMG_NAME),
            ],
            commands[3],
        )
        self.assertEqual(
            [
                "xcrun",
                "notarytool",
                "submit",
                os.path.join(app_dir, notarize_app.DMG_NAME),
                "--keychain-profile",
                "test-notary-profile",
                "--wait",
            ],
            commands[4],
        )
        self.assertEqual(["xcrun", "stapler", "staple"], commands[5][:-1])
        self.assertEqual(["xcrun", "stapler", "validate"], commands[6][:-1])
        self.assertEqual(["hdiutil", "verify"], commands[7][:-1])
        self.assertEqual(
            ["codesign", "--verify", "--verbose=2"],
            commands[8][:-1],
        )

    def test_rejects_ad_hoc_identity(self):
        with (
            mock.patch.object(
                notarize_app,
                "load_build_config",
                return_value={
                    "CODESIGN_IDENTITY": "-",
                    "NOTARY_KEYCHAIN_PROFILE": "test-notary-profile",
                },
            ),
            mock.patch.object(notarize_app.subprocess, "run") as run,
            self.assertRaises(SystemExit),
        ):
            notarize_app.main()

        run.assert_not_called()


class SignUpdateTests(unittest.TestCase):
    def test_adds_dmg_entry_without_changing_historical_zip_entry(self):
        old_item = """        <item>
            <title>Version 0.0.6</title>
            <sparkle:version>0.0.6</sparkle:version>
            <enclosure
                url="https://github.com/ecgan/macs-bar/releases/download/0.0.6/MacsBar.zip"
                sparkle:edSignature="old-signature"
                length="123"
                type="application/octet-stream" />
        </item>"""
        appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss>
    <channel>
        <language>en</language>
{old_item}
    </channel>
</rss>
"""

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            archive_path = temp_path / sign_update.ARCHIVE_NAME
            appcast_path = temp_path / "appcast.xml"
            info_plist_path = temp_path / "Info.plist"
            archive_path.touch()
            appcast_path.write_text(appcast, encoding="utf-8")
            with info_plist_path.open("wb") as plist_file:
                plistlib.dump(
                    {
                        "CFBundleShortVersionString": "0.0.7",
                        "CFBundleVersion": "0.0.7",
                        "LSMinimumSystemVersion": "14.0",
                    },
                    plist_file,
                )

            def run_command(command, **kwargs):
                if command[0] == "/fake/sign_update":
                    return subprocess.CompletedProcess(
                        command,
                        0,
                        stdout='sparkle:edSignature="new-signature" length="456"\n',
                        stderr="",
                    )
                if command[:3] == ["git", "status", "--porcelain"]:
                    return subprocess.CompletedProcess(
                        command,
                        0,
                        stdout=" M appcast.xml\n",
                        stderr="",
                    )
                return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

            with (
                mock.patch.object(sign_update, "DIST_ARCHIVE", str(archive_path)),
                mock.patch.object(sign_update, "APPCAST_PATH", str(appcast_path)),
                mock.patch.object(sign_update, "INFO_PLIST", str(info_plist_path)),
                mock.patch.object(sign_update, "REPO_ROOT", temp_dir),
                mock.patch.object(
                    sign_update,
                    "find_sign_tool",
                    return_value="/fake/sign_update",
                ),
                mock.patch.object(
                    sign_update.subprocess,
                    "run",
                    side_effect=run_command,
                ),
            ):
                sign_update.main()

            updated_appcast = appcast_path.read_text(encoding="utf-8")

        self.assertIn(old_item, updated_appcast)
        self.assertIn(
            "releases/download/0.0.7/MacsBar.dmg",
            updated_appcast,
        )
        self.assertIn('sparkle:edSignature="new-signature"', updated_appcast)
        self.assertIn('length="456"', updated_appcast)


if __name__ == "__main__":
    unittest.main()

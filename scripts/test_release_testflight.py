#!/usr/bin/python3
"""Logic-only tests for scripts/release-testflight.py. No network, no signing, no Xcode.

    /usr/bin/python3 scripts/test_release_testflight.py

App Store Connect, `security`, `codesign` and `xcodebuild` are mocked or fed
canned JSON, so these tests run on any machine and never touch the Apple
account. The committed config example is checked too, so a broken template
fails here before anyone tries to release.
"""

import contextlib
import importlib.util
import io
import json
import plistlib
import sys
import tempfile
import unittest
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent

spec = importlib.util.spec_from_file_location(
    "release_testflight", ROOT / "scripts" / "release-testflight.py")
if spec is None or spec.loader is None:
    raise RuntimeError("Cannot load scripts/release-testflight.py")
release = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = release
spec.loader.exec_module(release)

AT = datetime(2026, 9, 23, 9, tzinfo=timezone.utc)
TEAM = "TESTTEAM01"
CLOVE = release.APPS["clove"]
LAB = release.APPS["lab"]


def app_store_profile(app, team=TEAM, **overrides):
    """Fixture App Store profile bytes, shaped like a decoded .mobileprovision."""
    profile = {
        "Name": f"{app.display_name} App Store",
        "UUID": "test-profile-uuid",
        "TeamIdentifier": [team],
        "Entitlements": {
            "application-identifier": team + "." + app.bundle_id,
            "get-task-allow": False,
        },
        "DeveloperCertificates": [b"certificate"],
    }
    profile.update(overrides)
    return plistlib.dumps(profile)


def security_output(payload=None, returncode=0):
    return SimpleNamespace(returncode=returncode, stdout=payload or b"", stderr=b"")


def ipa_info(app, **overrides):
    info = {
        "CFBundleIdentifier": app.bundle_id,
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "26092309",
        "ITSAppUsesNonExemptEncryption": False,
    }
    info.update(overrides)
    return info


def write_ipa(path, info, app=None):
    name = (app or CLOVE).product
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(f"Payload/{name}.app/Info.plist", plistlib.dumps(info))
    return path


def show_settings(**settings):
    lines = [f"    {name} = {value}" for name, value in settings.items()]
    return "\n".join(lines) + "\n"


class QuietTestCase(unittest.TestCase):
    """Keep the script's progress lines out of the test output."""

    def setUp(self):
        output = contextlib.redirect_stdout(io.StringIO())
        output.__enter__()
        self.addCleanup(output.__exit__, None, None, None)


class BuildNumberTests(QuietTestCase):
    def test_uses_utc_yymmddhh_and_only_compares_current_marketing_version(self):
        visible = [("0.1.0", "1"), ("0.1.0", "2"), ("0.2.0", "99999999")]
        self.assertEqual(release.next_build_number(visible, "0.1.0", now=AT), 26092309)

    def test_first_upload_uses_timestamp(self):
        self.assertEqual(release.next_build_number([], "0.1.0", now=AT), 26092309)

    def test_timestamp_follows_utc_not_local_time(self):
        # 2026-09-23 01:30 +08:00 is 2026-09-22 17:30 UTC.
        local = datetime(2026, 9, 23, 1, 30, tzinfo=timezone(timedelta(hours=8)))
        self.assertEqual(release.next_build_number([], "0.1.0", now=local), 26092217)

    def test_later_hour_is_greater_than_visible_build(self):
        visible = [("0.1.0", "26092309")]
        self.assertEqual(release.next_build_number(visible, "0.1.0", now=AT + timedelta(hours=1)), 26092310)

    def test_same_hour_fails_instead_of_incrementing(self):
        with self.assertRaisesRegex(release.ReleaseError, "wait until a later UTC hour"):
            release.next_build_number([("0.1.0", "26092309")], "0.1.0", now=AT)

    def test_higher_visible_build_fails(self):
        with self.assertRaises(release.ReleaseError):
            release.next_build_number([("0.1.0", "26092310")], "0.1.0", now=AT)

    def test_highest_visible_build_for_the_version_decides(self):
        visible = [("0.1.0", "26092308"), ("0.1.0", "26092309")]
        with self.assertRaises(release.ReleaseError):
            release.next_build_number(visible, "0.1.0", now=AT)

    def test_noninteger_version_refuses_to_guess(self):
        with self.assertRaises(release.ReleaseError):
            release.next_build_number([("0.1.0", "1.2")], "0.1.0", now=AT)


class ConfigPathTests(QuietTestCase):
    def test_explicit_path_wins(self):
        options = {"CLOVE_TESTFLIGHT_CONFIG": "/elsewhere/env.json"}
        self.assertEqual(release.resolve_config_path("/tmp/explicit.json", options),
                         Path("/tmp/explicit.json"))

    def test_environment_variable_is_used_next(self):
        options = {"CLOVE_TESTFLIGHT_CONFIG": "/elsewhere/env.json"}
        self.assertEqual(release.resolve_config_path(None, options), Path("/elsewhere/env.json"))

    def test_default_is_the_gitignored_local_config(self):
        self.assertEqual(release.resolve_config_path(None, {}), release.DEFAULT_CONFIG)

    def test_blank_environment_variable_falls_back(self):
        self.assertEqual(release.resolve_config_path(None, {"CLOVE_TESTFLIGHT_CONFIG": "  "}),
                         release.DEFAULT_CONFIG)


class ConfigFixture(QuietTestCase):
    def setUp(self):
        super().setUp()
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.files = {name: self.root / name for name in
                      ("key.p8", "cert.p12", "password", "clove.mobileprovision", "lab.mobileprovision")}
        for path in self.files.values():
            path.write_text("test-password\n")
            path.chmod(0o600)
        self.config_file = self.root / "TestFlight.local.json"
        self.write_config()
        self.config_file.chmod(0o600)

    def write_config(self, **overrides):
        config = {
            "apiKeyId": "TESTKEYID",
            "issuerId": "test-issuer",
            "apiKeyPath": str(self.files["key.p8"]),
            "distributionP12Path": str(self.files["cert.p12"]),
            "distributionP12PasswordFile": str(self.files["password"]),
            "appStoreProfiles": {
                "clove": str(self.files["clove.mobileprovision"]),
                "lab": str(self.files["lab.mobileprovision"]),
            },
        }
        config.update(overrides)
        self.config_file.write_text(json.dumps(config))


class ReleaseConfigTests(ConfigFixture):
    def test_reads_paths_and_password_file(self):
        config = release.release_config(self.config_file, LAB)
        self.assertEqual(config["apiKeyId"], "TESTKEYID")
        self.assertEqual(config["issuerId"], "test-issuer")
        self.assertEqual(config["p12Password"], "test-password")
        self.assertEqual(config["distributionP12Path"], self.files["cert.p12"].resolve())
        self.assertEqual(config["profilePath"], self.files["lab.mobileprovision"].resolve())

    def test_selects_the_profile_for_the_requested_app(self):
        self.assertEqual(release.release_config(self.config_file, CLOVE)["profilePath"],
                         self.files["clove.mobileprovision"].resolve())
        self.assertEqual(release.release_config(self.config_file, LAB)["profilePath"],
                         self.files["lab.mobileprovision"].resolve())

    def test_refuses_missing_config(self):
        with self.assertRaisesRegex(release.ReleaseError, "TestFlight.local.json.example"):
            release.release_config(self.root / "absent.json", CLOVE)

    def test_refuses_incomplete_config(self):
        for overrides in ({"issuerId": ""}, {"apiKeyPath": ""}):
            self.write_config(**overrides)
            with self.assertRaisesRegex(release.ReleaseError, "Incomplete TestFlight config"):
                release.release_config(self.config_file, CLOVE)

    def test_refuses_config_without_app_store_profiles(self):
        self.write_config(appStoreProfiles=[])
        with self.assertRaisesRegex(release.ReleaseError, "appStoreProfiles"):
            release.release_config(self.config_file, CLOVE)

    def test_refuses_config_without_the_requested_app_profile(self):
        self.write_config(appStoreProfiles={"clove": str(self.files["clove.mobileprovision"])})
        with self.assertRaisesRegex(release.ReleaseError, "appStoreProfiles\\['lab'\\]"):
            release.release_config(self.config_file, LAB)

    def test_refuses_missing_signing_file(self):
        self.files["cert.p12"].unlink()
        with self.assertRaisesRegex(release.ReleaseError, "Missing signing file"):
            release.release_config(self.config_file, CLOVE)

    def test_refuses_group_readable_config_or_secret_files(self):
        self.config_file.chmod(0o644)
        with self.assertRaisesRegex(release.ReleaseError, "chmod 600"):
            release.release_config(self.config_file, CLOVE)
        self.config_file.chmod(0o600)
        for name in ("cert.p12", "password", "key.p8"):
            path = self.files[name]
            path.chmod(0o640)
            with self.assertRaises(release.ReleaseError):
                release.release_config(self.config_file, CLOVE)
            path.chmod(0o600)

    def test_profiles_are_not_required_to_be_600(self):
        # Profiles are not secrets; `security cms` only reads them.
        for name in ("clove.mobileprovision", "lab.mobileprovision"):
            self.files[name].chmod(0o644)
        self.assertEqual(release.release_config(self.config_file, LAB)["apiKeyId"], "TESTKEYID")

    def test_refuses_signing_files_inside_repository(self):
        self.write_config(distributionP12Path=str(ROOT / "cert.p12"))
        with self.assertRaisesRegex(release.ReleaseError, "outside the repository"):
            release.release_config(self.config_file, CLOVE)

    def test_refuses_empty_password_file(self):
        self.files["password"].write_text("\n")
        with self.assertRaisesRegex(release.ReleaseError, "Empty distribution"):
            release.release_config(self.config_file, CLOVE)

    def test_beta_group_defaults_and_can_be_overridden(self):
        self.assertEqual(release.release_config(self.config_file, LAB)["betaGroup"],
                         "Clove Lab Internal")
        self.write_config(betaGroup="Another Group")
        self.assertEqual(release.release_config(self.config_file, LAB)["betaGroup"], "Another Group")

    def test_refuses_empty_beta_group(self):
        self.write_config(betaGroup="   ")
        with self.assertRaisesRegex(release.ReleaseError, "betaGroup"):
            release.release_config(self.config_file, LAB)

    def test_remembers_secrets_for_scrubbing(self):
        config = release.release_config(self.config_file, CLOVE)
        for value in (config["apiKeyId"], config["issuerId"], config["p12Password"]):
            self.assertNotIn(value, release.scrub(f"log line with {value} inside"))


class AppSelectionTests(QuietTestCase):
    def test_bundle_ids_are_pinned(self):
        self.assertEqual(CLOVE.bundle_id, "com.mimiqdev.clove")
        self.assertEqual(LAB.bundle_id, "com.mimiqdev.clove.lab")

    def test_each_app_maps_to_its_own_scheme_and_product(self):
        self.assertEqual((CLOVE.scheme, CLOVE.target, CLOVE.product), ("Clove", "Clove", "Clove"))
        self.assertEqual((LAB.scheme, LAB.target, LAB.product), ("CloveLab", "CloveLab", "CloveLab"))

    def test_only_the_two_apps_exist(self):
        self.assertEqual(sorted(release.APPS), ["clove", "lab"])

    def test_unknown_app_is_rejected_before_anything_runs(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            release.main(["--app", "mudi"])
        self.assertEqual(raised.exception.code, 2)


class CleanTreeTests(QuietTestCase):
    def test_clean_tree_passes(self):
        with patch.object(release, "working_tree_changes", return_value=""):
            release.ensure_clean_tree()

    def test_dirty_tree_lists_the_changes(self):
        with (
            patch.object(release, "working_tree_changes", return_value="?? untracked.tmp"),
            self.assertRaisesRegex(release.ReleaseError, "dirty worktree"),
        ):
            release.ensure_clean_tree()


class MainTests(ConfigFixture):
    def test_upload_stops_before_archiving_on_a_dirty_tree(self):
        with (
            patch.object(release, "working_tree_changes", return_value=" M project.yml"),
            patch.object(release, "resolve_config_path", return_value=self.config_file),
            patch.object(release, "generate_project") as generate,
            patch.object(release, "archive") as archive,
            self.assertRaisesRegex(release.ReleaseError, "dirty worktree"),
        ):
            release.main(["--app", "lab", "--upload"])
        generate.assert_not_called()
        archive.assert_not_called()


class BuildSettingsTests(QuietTestCase):
    output = (
        "Build settings for action build and target Clove:\n"
        + show_settings(PRODUCT_BUNDLE_IDENTIFIER="com.mimiqdev.clove", MARKETING_VERSION="0.1.0")
        + "Build settings for action build and target CloveUITests:\n"
        + show_settings(PRODUCT_BUNDLE_IDENTIFIER="com.mimiqdev.clove.uitests",
                        MARKETING_VERSION="9.9.9")
    )

    def test_picks_the_requested_target_section(self):
        settings = release.parse_build_settings(self.output, "Clove")
        self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "com.mimiqdev.clove")
        self.assertEqual(settings["MARKETING_VERSION"], "0.1.0")
        self.assertEqual(release.parse_build_settings(self.output, "CloveUITests")["MARKETING_VERSION"],
                         "9.9.9")

    def test_unknown_target_has_no_settings(self):
        self.assertEqual(release.parse_build_settings(self.output, "Absent"), {})

    def test_reads_marketing_version_from_xcode_build_settings(self):
        with patch.object(release, "command", return_value=self.output):
            self.assertEqual(release.app_build_settings(CLOVE), "0.1.0")

    def test_refuses_another_bundle_id(self):
        wrong = ("Build settings for action build and target Clove:\n"
                 + show_settings(PRODUCT_BUNDLE_IDENTIFIER="com.mimiqdev.someotherapp",
                                 MARKETING_VERSION="0.1.0"))
        with (
            patch.object(release, "command", return_value=wrong),
            self.assertRaisesRegex(release.ReleaseError, "com.mimiqdev.clove"),
        ):
            release.app_build_settings(CLOVE)

    def test_refuses_unusable_marketing_version(self):
        broken = ("Build settings for action build and target Clove:\n"
                  + show_settings(PRODUCT_BUNDLE_IDENTIFIER="com.mimiqdev.clove",
                                  MARKETING_VERSION="next"))
        with (
            patch.object(release, "command", return_value=broken),
            self.assertRaisesRegex(release.ReleaseError, "MARKETING_VERSION"),
        ):
            release.app_build_settings(CLOVE)

    def test_refuses_missing_target_section(self):
        with (
            patch.object(release, "command", return_value="Build settings for action build and target Other:\n"),
            self.assertRaisesRegex(release.ReleaseError, "No Xcode build settings"),
        ):
            release.app_build_settings(CLOVE)


class ProfileDetailsTests(QuietTestCase):
    profile = Path("profile.mobileprovision")

    def details(self, app, payload, team=TEAM):
        with patch.object(release.subprocess, "run", return_value=security_output(payload)):
            return release.profile_details(self.profile, app)

    def assert_refused(self, app, payload, message=None, returncode=0):
        with patch.object(release.subprocess, "run", return_value=security_output(payload, returncode)):
            if message:
                with self.assertRaisesRegex(release.ReleaseError, message):
                    release.profile_details(self.profile, app)
            else:
                with self.assertRaises(release.ReleaseError):
                    release.profile_details(self.profile, app)

    def test_accepts_app_store_distribution_profile(self):
        profile, team = self.details(LAB, app_store_profile(LAB))
        self.assertEqual(team, TEAM)
        self.assertEqual(profile["Name"], "Clove Lab App Store")

    def test_refuses_profile_without_explicit_get_task_allow_false(self):
        entitlements = {"application-identifier": TEAM + "." + LAB.bundle_id}
        self.assert_refused(LAB, app_store_profile(LAB, Entitlements=entitlements),
                            "not an App Store distribution profile")

    def test_refuses_profile_with_provisioned_devices(self):
        self.assert_refused(LAB, app_store_profile(LAB, ProvisionedDevices=["00008150-001265CE0E99401C"]))

    def test_refuses_profile_with_get_task_allow_true(self):
        entitlements = {
            "application-identifier": TEAM + "." + LAB.bundle_id,
            "get-task-allow": True,
        }
        self.assert_refused(LAB, app_store_profile(LAB, Entitlements=entitlements))

    def test_refuses_profile_for_another_app(self):
        self.assert_refused(LAB, app_store_profile(CLOVE), "com.mimiqdev.clove.lab")

    def test_refuses_undecodable_profile(self):
        self.assert_refused(CLOVE, None, "Cannot decode", returncode=1)


class VerifyIPATests(QuietTestCase):
    def setUp(self):
        super().setUp()
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.ipa = Path(self.temporary.name) / "CloveLab.ipa"

    def verify(self, ipa, app=LAB):
        release.verify_ipa(ipa, app, "0.1.0", "26092309", TEAM)

    def test_refuses_wrong_bundle_id_or_version(self):
        payloads = (ipa_info(LAB, CFBundleIdentifier=CLOVE.bundle_id),
                    ipa_info(LAB, CFBundleShortVersionString="9.9"),
                    ipa_info(LAB, CFBundleVersion="1"))
        for info in payloads:
            write_ipa(self.ipa, info, LAB)
            with self.assertRaisesRegex(release.ReleaseError, "unexpected ID, version, build"):
                self.verify(self.ipa)

    def test_refuses_missing_or_true_compliance_declaration(self):
        without_key = ipa_info(LAB)
        del without_key["ITSAppUsesNonExemptEncryption"]
        for payload in (without_key, ipa_info(LAB, ITSAppUsesNonExemptEncryption=True)):
            write_ipa(self.ipa, payload, LAB)
            with self.assertRaises(release.ReleaseError):
                self.verify(self.ipa)

    def test_refuses_ipa_without_the_app_payload(self):
        write_ipa(self.ipa, ipa_info(CLOVE), CLOVE)
        with self.assertRaisesRegex(release.ReleaseError, "Payload/CloveLab.app"):
            self.verify(self.ipa)

    def test_verifies_matching_ipa_with_local_codesign_and_embedded_profile(self):
        write_ipa(self.ipa, ipa_info(LAB), LAB)
        calls = []

        def record(argv, log=None):
            calls.append(argv)
            return ""

        signature = "Authority=Apple Distribution: Test Team\nTeamIdentifier=" + TEAM + "\n"
        with (
            patch.object(release, "command", side_effect=record),
            patch.object(release, "profile_details", return_value=({"Name": "Clove Lab App Store"}, TEAM)),
            patch.object(release.subprocess, "run",
                         return_value=SimpleNamespace(returncode=0, stdout="", stderr=signature)),
        ):
            self.verify(self.ipa)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0], ["codesign", "--verify", "--deep", "--strict", calls[0][-1]])
        self.assertTrue(calls[0][-1].endswith("Payload/CloveLab.app"))

    def test_refuses_ipa_signed_by_another_team(self):
        write_ipa(self.ipa, ipa_info(LAB), LAB)
        signature = "Authority=Apple Distribution: Test Team\nTeamIdentifier=" + TEAM + "\n"
        with (
            patch.object(release, "command", return_value=""),
            patch.object(release, "profile_details", return_value=({"Name": "Other"}, "OTHERTEAM")),
            patch.object(release.subprocess, "run",
                         return_value=SimpleNamespace(returncode=0, stdout="", stderr=signature)),
            self.assertRaisesRegex(release.ReleaseError, "another team"),
        ):
            self.verify(self.ipa)

    def test_refuses_ipa_without_apple_distribution_signature(self):
        write_ipa(self.ipa, ipa_info(LAB), LAB)
        with (
            patch.object(release, "command", return_value=""),
            patch.object(release.subprocess, "run", return_value=SimpleNamespace(
                returncode=1, stdout="", stderr="code object is not signed at all")),
            self.assertRaisesRegex(release.ReleaseError, "not signed locally"),
        ):
            self.verify(self.ipa)


def build_page(data, included=None, next_url=None):
    page = {"data": data, "included": included or []}
    if next_url:
        page["links"] = {"next": next_url}
    return page


def build_record(build_id, version, release_id):
    return {
        "type": "builds",
        "id": build_id,
        "attributes": {"version": version},
        "relationships": {"preReleaseVersion": {"data": {"type": "preReleaseVersions",
                                                         "id": release_id}}},
    }


def release_record(release_id, version, platform="IOS"):
    return {"type": "preReleaseVersions", "id": release_id,
            "attributes": {"version": version, "platform": platform}}


def group_record(name, group_id="group-id", **attributes):
    attributes = {"name": name, **attributes}
    return {"type": "betaGroups", "id": group_id, "attributes": attributes}


class AppStoreConnectTests(QuietTestCase):
    def test_altool_token_from_stderr_is_used_and_scrubbed(self):
        expected = "eyJheader.eyJpayload.signature"
        with patch.object(release.subprocess, "run", return_value=SimpleNamespace(
                returncode=0, stdout="", stderr="Info: " + expected)):
            self.assertEqual(release.jwt("key", "issuer", Path("key.p8")), expected)
        self.assertEqual(release.scrub("token " + expected), "token [redacted]")

    def test_failed_token_generation_mentions_no_output(self):
        with patch.object(release.subprocess, "run", return_value=SimpleNamespace(
                returncode=1, stdout="", stderr="error: secret-looking-output")):
            with self.assertRaises(release.ReleaseError) as raised:
                release.jwt("key", "issuer", Path("key.p8"))
        self.assertNotIn("secret-looking-output", str(raised.exception))

    def test_requires_exactly_one_app_for_the_bundle_id(self):
        empty = {"data": []}
        duplicate = {"data": [
            {"id": "a", "attributes": {"bundleId": LAB.bundle_id}},
            {"id": "b", "attributes": {"bundleId": LAB.bundle_id}},
        ]}
        for page in (empty, duplicate):
            with (
                patch.object(release, "asc_get", return_value=page),
                self.assertRaisesRegex(release.ReleaseError, LAB.bundle_id),
            ):
                release.lookup_app("token", LAB)

    def test_ignores_apps_whose_bundle_id_only_starts_the_same(self):
        # The API bundle ID filter is a prefix match: Clove returns Clove Lab too.
        page = {"data": [
            {"id": "lab-app", "attributes": {"bundleId": LAB.bundle_id, "name": "Clove Lab"}},
            {"id": "clove-app", "attributes": {"bundleId": CLOVE.bundle_id, "name": "Clove"}},
        ]}
        with patch.object(release, "asc_get", return_value=page):
            self.assertEqual(release.lookup_app("token", CLOVE), "clove-app")

    def test_reads_the_app_id_and_name(self):
        page = {"data": [{"id": "app-id", "attributes": {"bundleId": LAB.bundle_id,
                                                          "name": "Clove Lab"}}]}
        with patch.object(release, "asc_get", return_value=page):
            self.assertEqual(release.lookup_app("token", LAB), "app-id")

    def test_finds_the_beta_group_on_the_app(self):
        page = build_page([group_record("Other Group"),
                           group_record("Clove Lab Internal", isInternalGroup=True,
                                        hasAccessToAllBuilds=True)])
        with patch.object(release, "asc_get", return_value=page):
            self.assertEqual(release.check_beta_group("token", "app-id", "Clove Lab Internal"),
                             "group-id")

    def test_missing_beta_group_fails_with_its_name(self):
        page = build_page([group_record("Other Group")])
        with (
            patch.object(release, "asc_get", return_value=page),
            self.assertRaisesRegex(release.ReleaseError, "Clove Lab Missing"),
        ):
            release.check_beta_group("token", "app-id", "Clove Lab Missing")

    def test_beta_group_found_on_a_later_page(self):
        first = build_page([group_record("Other Group")], next_url="https://api.example/next")
        second = build_page([group_record("Clove Lab Internal")])
        with (
            patch.object(release, "asc_get", return_value=first),
            patch.object(release, "asc_json", return_value=second),
        ):
            self.assertEqual(release.check_beta_group("token", "app-id", "Clove Lab Internal"),
                             "group-id")

    def test_visible_builds_follow_pagination_and_ios_only(self):
        first = build_page([build_record("b1", "26092309", "p1")],
                           [release_record("p1", "0.1.0")],
                           next_url="https://api.example/next")
        second = build_page([build_record("b2", "26092310", "p2")],
                            [release_record("p2", "0.1.0", platform="MAC_OS")])
        with (
            patch.object(release, "asc_get", return_value=first),
            patch.object(release, "asc_json", return_value=second),
        ):
            self.assertEqual(release.visible_builds("token", "app-id"), [("0.1.0", "26092309")])


class ScrubTests(QuietTestCase):
    def test_scrub_replaces_every_registered_value(self):
        release.register_secret("very-secret-password")
        release.register_secret("KEYID12345")
        text = release.scrub("key KEYID12345 password very-secret-password")
        self.assertEqual(text, "key [redacted] password [redacted]")

    def test_scrub_keeps_unrelated_text(self):
        self.assertEqual(release.scrub("archive succeeded"), "archive succeeded")


class ConfigExampleTests(QuietTestCase):
    def setUp(self):
        super().setUp()
        self.path = ROOT / "Config" / "TestFlight.local.json.example"
        if not self.path.is_file():
            self.skipTest("Config/TestFlight.local.json.example is missing")
        self.example = json.loads(self.path.read_text())

    def test_example_has_both_apps_and_the_documented_keys(self):
        self.assertEqual(sorted(self.example["appStoreProfiles"]), ["clove", "lab"])
        for key in ("apiKeyId", "issuerId", "apiKeyPath", "distributionP12Path",
                    "distributionP12PasswordFile"):
            self.assertIn(key, self.example)

    def test_example_uses_placeholders_only(self):
        self.assertEqual(self.example["betaGroup"], "Clove Lab Internal")
        for value in (self.example["apiKeyId"], self.example["issuerId"]):
            self.assertTrue(value.isupper() or value.islower())
            self.assertTrue(value.startswith("YOUR_"), value)


if __name__ == "__main__":
    unittest.main()

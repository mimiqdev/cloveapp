#!/usr/bin/python3
"""Logic-only tests for scripts/public-beta-testflight.py. No network, no signing, no Xcode.

    /usr/bin/python3 scripts/test_public_beta_testflight.py
"""

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


release = _load_module("release_testflight", ROOT / "scripts" / "release-testflight.py")
public_beta = _load_module("public_beta_testflight", ROOT / "scripts" / "public-beta-testflight.py")


class QuietTestCase(unittest.TestCase):
    def setUp(self):
        self.stdout_buffer = io.StringIO()
        redirect = contextlib.redirect_stdout(self.stdout_buffer)
        redirect.__enter__()
        self.addCleanup(redirect.__exit__, None, None, None)


class FakeAscClient:
    """In-memory fake App Store Connect API server for testing public-beta-testflight.py."""

    def __init__(self):
        self.app_id = "app-clove-1"
        self.builds = []
        self.groups = []
        self.group_builds = {}
        self.app_localizations = []
        self.build_localizations = {}
        self.review_detail = {
            "type": "betaAppReviewDetails",
            "id": "app-clove-1",
            "attributes": {
                "contactFirstName": "Jane",
                "contactLastName": "Reviewer",
                "contactPhone": "+1-555-0199",
                "contactEmail": "reviewer-private@example.com",
                "demoAccountRequired": True,
                "notes": "Old notes",
            },
        }
        self.review_submissions = {}
        self.calls = []
        self.reject_public_link_until_attached = False
        self.reject_public_link_until_approved = False
        self.reject_locales = set()
        self.next_id = 100

    def _new_id(self, prefix):
        self.next_id += 1
        return f"{prefix}-{self.next_id}"

    def _check_https(self, url):
        if not url.startswith("https://"):
            raise release.ReleaseError("Refusing non-HTTPS URL: " + url)

    def asc_get(self, path, params, token):
        self.calls.append(("GET", path, params))
        if path == "apps":
            return {
                "data": [
                    {
                        "id": self.app_id,
                        "attributes": {
                            "bundleId": "com.mimiqdev.clove",
                            "name": "Clove",
                        },
                    }
                ]
            }
        if path == "builds":
            included = []
            seen_prv = set()
            for build in self.builds:
                prv_id = build["relationships"]["preReleaseVersion"]["data"]["id"]
                if prv_id not in seen_prv:
                    seen_prv.add(prv_id)
                    included.append({
                        "type": "preReleaseVersions",
                        "id": prv_id,
                        "attributes": {
                            "version": build["_marketingVersion"],
                            "platform": build.get("_platform", "IOS"),
                        },
                    })
            return {"data": self.builds, "included": included}
        if path.startswith("builds/") and path.endswith("/betaAppReviewSubmission"):
            build_id = path.split("/")[1]
            sub = self.review_submissions.get(build_id)
            if sub is None:
                return {"data": None}
            return {"data": sub}
        if path.startswith("builds/"):
            build_id = path.split("/")[1]
            for build in self.builds:
                if build["id"] == build_id:
                    return {"data": build}
            raise release.AscHttpError(release.ASC_HOST + path, 404, [("NOT_FOUND", "Not found")])
        if path == "betaGroups":
            return {"data": list(self.groups)}
        if path.startswith("betaGroups/") and path.endswith("/builds"):
            group_id = path.split("/")[1]
            return {"data": [{"type": "builds", "id": bid} for bid in self.group_builds.get(group_id, [])]}
        if path == "betaAppLocalizations":
            return {"data": list(self.app_localizations)}
        if path == "betaBuildLocalizations":
            build_id = (params or {}).get("filter[build]")
            return {"data": list(self.build_localizations.get(build_id, []))}
        if path == f"apps/{self.app_id}/betaAppReviewDetail":
            return {"data": self.review_detail}
        raise AssertionError(f"Unexpected GET path: {path}")

    def asc_post(self, path, payload, token):
        self.calls.append(("POST", path, payload))
        if path == "betaAppLocalizations":
            attrs = payload["data"]["attributes"]
            locale = attrs["locale"]
            if locale in self.reject_locales:
                raise release.AscHttpError(
                    release.ASC_HOST + path,
                    409,
                    [("ENTITY_ERROR.ATTRIBUTE.INVALID", "Unsupported locale", locale)],
                )
            item = {
                "type": "betaAppLocalizations",
                "id": self._new_id("app-loc"),
                "attributes": dict(attrs),
            }
            self.app_localizations.append(item)
            return {"data": item}
        if path == "betaGroups":
            attrs = payload["data"]["attributes"]
            item = {
                "type": "betaGroups",
                "id": self._new_id("group"),
                "attributes": {
                    "publicLinkEnabled": False,
                    "publicLink": None,
                    "publicLinkLimitEnabled": False,
                    "publicLinkLimit": None,
                    **attrs,
                },
            }
            self.groups.append(item)
            return {"data": item}
        if path == "betaBuildLocalizations":
            attrs = payload["data"]["attributes"]
            locale = attrs["locale"]
            if locale in self.reject_locales:
                raise release.AscHttpError(
                    release.ASC_HOST + path,
                    422,
                    [("ENTITY_ERROR.ATTRIBUTE.INVALID", "Unsupported locale", locale)],
                )
            build_id = payload["data"]["relationships"]["build"]["data"]["id"]
            item = {
                "type": "betaBuildLocalizations",
                "id": self._new_id("build-loc"),
                "attributes": dict(attrs),
            }
            self.build_localizations.setdefault(build_id, []).append(item)
            return {"data": item}
        if path.startswith("betaGroups/") and path.endswith("/relationships/builds"):
            group_id = path.split("/")[1]
            ids = [entry["id"] for entry in payload["data"]]
            attached = self.group_builds.setdefault(group_id, [])
            for bid in ids:
                if bid not in attached:
                    attached.append(bid)
            return {}
        if path == "betaAppReviewSubmissions":
            build_id = payload["data"]["relationships"]["build"]["data"]["id"]
            sub = {
                "type": "betaAppReviewSubmissions",
                "id": self._new_id("sub"),
                "attributes": {"betaReviewState": "WAITING_FOR_REVIEW"},
            }
            self.review_submissions[build_id] = sub
            return {"data": sub}
        raise AssertionError(f"Unexpected POST path: {path}")

    def asc_patch(self, path, payload, token):
        self.calls.append(("PATCH", path, payload))
        if path.startswith("betaAppLocalizations/"):
            loc_id = path.split("/")[1]
            for item in self.app_localizations:
                if item["id"] == loc_id:
                    item["attributes"].update(payload["data"]["attributes"])
                    return {"data": item}
            raise AssertionError(f"Unknown app localization {loc_id}")
        if path.startswith("betaBuildLocalizations/"):
            loc_id = path.split("/")[1]
            for items in self.build_localizations.values():
                for item in items:
                    if item["id"] == loc_id:
                        item["attributes"].update(payload["data"]["attributes"])
                        return {"data": item}
            raise AssertionError(f"Unknown build localization {loc_id}")
        if path.startswith("betaAppReviewDetails/"):
            attrs = payload["data"]["attributes"]
            self.review_detail["attributes"].update(attrs)
            return {"data": self.review_detail}
        if path.startswith("betaGroups/"):
            group_id = path.split("/")[1]
            attrs = payload["data"]["attributes"]
            for group in self.groups:
                if group["id"] != group_id:
                    continue
                if attrs.get("publicLinkEnabled"):
                    attached = self.group_builds.get(group_id, [])
                    if self.reject_public_link_until_attached and not attached:
                        raise release.AscHttpError(
                            release.ASC_HOST + path,
                            409,
                            [("STATE_ERROR", "Cannot enable public link without builds")],
                        )
                    if self.reject_public_link_until_approved:
                        raise release.AscHttpError(
                            release.ASC_HOST + path,
                            409,
                            [("STATE_ERROR", "Cannot enable public link until approved")],
                        )
                    group["attributes"]["publicLink"] = f"https://testflight.apple.com/join/{group_id}"
                group["attributes"].update(attrs)
                return {"data": group}
            raise AssertionError(f"Unknown group {group_id}")
        raise AssertionError(f"Unexpected PATCH path: {path}")


def make_build(build_id, version, *, marketing_version="0.1.0", state="VALID", uploaded="2026-11-18T10:00:00Z", platform="IOS"):
    return {
        "type": "builds",
        "id": build_id,
        "_marketingVersion": marketing_version,
        "_platform": platform,
        "attributes": {
            "version": version,
            "processingState": state,
            "uploadedDate": uploaded,
        },
        "relationships": {
            "preReleaseVersion": {
                "data": {"type": "preReleaseVersions", "id": f"prv-{marketing_version}-{platform}"},
            }
        },
    }


class MaterialsTests(QuietTestCase):
    def test_reads_marketing_version_from_project_yml(self):
        self.assertEqual(public_beta.default_marketing_version(), "0.1.0")

    def test_external_materials_doc_has_all_locales_and_no_stale_placeholders(self):
        doc_text = public_beta.MATERIALS_DOC.read_text(encoding="utf-8")
        self.assertNotIn("placeholder", doc_text.lower())
        self.assertNotIn("<FEEDBACK_EMAIL>", doc_text)

        materials = public_beta.load_external_materials()
        for locale in ("en-US", "zh-Hans", "zh-Hant"):
            desc = materials["descriptions"][locale]
            wn = materials["whats_new"][locale]
            self.assertTrue(desc)
            self.assertTrue(wn)
            self.assertLessEqual(len(desc), 4000)
            self.assertLessEqual(len(wn), 4000)

        en_desc = materials["descriptions"]["en-US"]
        for keyword in ("Files", "RAW", "100% zoom", "similar-shot", "XMP", "Move rejects", "Batch Rename"):
            self.assertIn(keyword, en_desc)

        notes = materials["review_notes"]
        self.assertIn("Open folder", notes)
        self.assertIn("Photo Library", notes)
        self.assertLessEqual(len(notes), 4000)


class ConfigAndSecurityTests(QuietTestCase):
    def setUp(self):
        super().setUp()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.key_file = self.root / "AuthKey_TESTKEY99.p8"
        self.key_file.write_text("KEYDATA")
        self.key_file.chmod(0o600)
        self.p12_pass = self.root / "p12.pass"
        self.p12_pass.write_text("super-secret-p12-pass\n")
        self.p12_pass.chmod(0o600)
        self.config_file = self.root / "config.json"
        self.config_file.write_text(json.dumps({
            "apiKeyId": "TESTKEY99",
            "issuerId": "issuer-uuid-secret",
            "apiKeyPath": str(self.key_file),
            "distributionP12PasswordFile": str(self.p12_pass),
        }))
        self.config_file.chmod(0o600)

    def test_loads_config_and_registers_secrets(self):
        cfg = public_beta.asc_config(self.config_file)
        self.assertEqual(cfg["apiKeyId"], "TESTKEY99")
        for secret in ("TESTKEY99", "issuer-uuid-secret", "super-secret-p12-pass"):
            self.assertNotIn(secret, release.scrub(f"err {secret} end"))

    def test_refuses_non_https_urls(self):
        with self.assertRaisesRegex(release.ReleaseError, "non-HTTPS"):
            release.asc_json("http://api.appstoreconnect.apple.com/v1/apps", "token")
        with self.assertRaisesRegex(release.ReleaseError, "non-HTTPS"):
            release.asc_json("http://api.appstoreconnect.apple.com/v1/betaGroups", "token", method="POST", payload={})

    def test_refuses_group_readable_config(self):
        self.config_file.chmod(0o644)
        with self.assertRaisesRegex(release.ReleaseError, "chmod 600"):
            public_beta.asc_config(self.config_file)


class InspectTests(QuietTestCase):
    def test_inspect_prints_summary_and_redacts_reviewer_contact_info(self):
        client = FakeAscClient()
        client.builds = [
            make_build("b1", "26111813", state="VALID"),
            make_build("b0", "26111810", state="VALID"),
        ]
        client.groups = [
            {
                "type": "betaGroups",
                "id": "g1",
                "attributes": {
                    "name": "Clove Public Beta",
                    "isInternalGroup": False,
                    "feedbackEnabled": True,
                    "publicLinkEnabled": False,
                    "publicLink": None,
                },
            }
        ]
        client.app_localizations = [
            {
                "type": "betaAppLocalizations",
                "id": "loc-1",
                "attributes": {
                    "locale": "en-US",
                    "description": "Some description",
                    "feedbackEmail": "mrtoniliu@gmail.com",
                },
            }
        ]

        with (
            patch.object(release, "asc_get", side_effect=client.asc_get),
            patch.object(release, "asc_post", side_effect=client.asc_post),
            patch.object(release, "asc_patch", side_effect=client.asc_patch),
        ):
            result = public_beta.inspect_public_beta("token", client.app_id)

        output = self.stdout_buffer.getvalue()
        self.assertTrue(result["contactComplete"])
        self.assertIn("App ID: app-clove-1", output)
        self.assertIn("26111813", output)
        self.assertIn("Clove Public Beta", output)
        self.assertIn("en-US", output)
        self.assertIn("contactComplete=True", output)
        # Personal phone, email, and name must never appear in stdout; phone & email must be scrubbed.
        for sensitive in ("+1-555-0199", "reviewer-private@example.com", "Jane", "Reviewer"):
            self.assertNotIn(sensitive, output)
        for scrubbed in ("+1-555-0199", "reviewer-private@example.com"):
            self.assertEqual(release.scrub(scrubbed), "[redacted]")

    def test_inspect_reports_incomplete_contact_when_phone_missing(self):
        client = FakeAscClient()
        client.review_detail["attributes"]["contactPhone"] = ""
        with patch.object(release, "asc_get", side_effect=client.asc_get):
            result = public_beta.inspect_public_beta("token", client.app_id)
        self.assertFalse(result["contactComplete"])
        self.assertIn("contactComplete=False", self.stdout_buffer.getvalue())


class PrepareTests(QuietTestCase):
    def test_prepare_upserts_localizations_patches_review_and_creates_group(self):
        client = FakeAscClient()
        client.app_localizations = [
            {
                "type": "betaAppLocalizations",
                "id": "loc-en",
                "attributes": {"locale": "en-US", "description": "old", "feedbackEmail": "old@example.com"},
            }
        ]
        client.reject_public_link_until_attached = True

        with (
            patch.object(release, "asc_get", side_effect=client.asc_get),
            patch.object(release, "asc_post", side_effect=client.asc_post),
            patch.object(release, "asc_patch", side_effect=client.asc_patch),
        ):
            result = public_beta.prepare_public_beta(
                "token",
                client.app_id,
                group_name="Clove Public Beta",
                feedback_email="mrtoniliu@gmail.com",
            )

        self.assertEqual(result["localizations"]["en-US"][0], "updated")
        self.assertEqual(result["localizations"]["zh-Hans"][0], "created")
        self.assertEqual(result["localizations"]["zh-Hant"][0], "created")
        self.assertEqual(len(client.app_localizations), 3)
        for item in client.app_localizations:
            self.assertEqual(item["attributes"]["feedbackEmail"], "mrtoniliu@gmail.com")

        # Contact fields preserved; demoAccountRequired set to False and notes updated.
        self.assertFalse(client.review_detail["attributes"]["demoAccountRequired"])
        self.assertIn("Open folder", client.review_detail["attributes"]["notes"])
        self.assertEqual(client.review_detail["attributes"]["contactPhone"], "+1-555-0199")
        review_patch = [c for c in client.calls if c[0] == "PATCH" and c[1].startswith("betaAppReviewDetails/")][0]
        for contact_key in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
            self.assertNotIn(contact_key, review_patch[2]["data"]["attributes"])

        # External group created cleanly even though ASC deferred publicLinkEnabled until a build exists.
        self.assertEqual(len(client.groups), 1)
        self.assertFalse(client.groups[0]["attributes"]["isInternalGroup"])
        self.assertTrue(client.groups[0]["attributes"]["feedbackEnabled"])
        self.assertFalse(client.groups[0]["attributes"]["publicLinkEnabled"])

    def test_prepare_fails_if_review_contact_incomplete(self):
        client = FakeAscClient()
        client.review_detail["attributes"]["contactPhone"] = "   "
        with (
            patch.object(release, "asc_get", side_effect=client.asc_get),
            patch.object(release, "asc_post", side_effect=client.asc_post),
            patch.object(release, "asc_patch", side_effect=client.asc_patch),
            self.assertRaisesRegex(release.ReleaseError, "contactPhone"),
        ):
            public_beta.prepare_public_beta(
                "token",
                client.app_id,
                group_name="Clove Public Beta",
                feedback_email="mrtoniliu@gmail.com",
            )
        self.assertEqual(len(client.app_localizations), 3)
        self.assertEqual(len(client.groups), 1)

    def test_prepare_logs_warning_when_secondary_locale_rejected(self):
        client = FakeAscClient()
        client.reject_locales = {"zh-Hant"}
        with (
            patch.object(release, "asc_get", side_effect=client.asc_get),
            patch.object(release, "asc_post", side_effect=client.asc_post),
            patch.object(release, "asc_patch", side_effect=client.asc_patch),
        ):
            result = public_beta.prepare_public_beta(
                "token",
                client.app_id,
                group_name="Clove Public Beta",
                feedback_email="mrtoniliu@gmail.com",
            )
        self.assertEqual(result["localizations"]["en-US"][0], "created")
        self.assertEqual(result["localizations"]["zh-Hans"][0], "created")
        self.assertEqual(result["localizations"]["zh-Hant"][0], "skipped")

    def test_prepare_refuses_internal_group_with_same_name(self):
        client = FakeAscClient()
        client.groups = [
            {
                "type": "betaGroups",
                "id": "g-internal",
                "attributes": {"name": "Clove Public Beta", "isInternalGroup": True},
            }
        ]
        with (
            patch.object(release, "asc_get", side_effect=client.asc_get),
            patch.object(release, "asc_post", side_effect=client.asc_post),
            patch.object(release, "asc_patch", side_effect=client.asc_patch),
            self.assertRaisesRegex(release.ReleaseError, "internal"),
        ):
            public_beta.prepare_public_beta(
                "token",
                client.app_id,
                group_name="Clove Public Beta",
                feedback_email="mrtoniliu@gmail.com",
            )


class SubmitTests(QuietTestCase):
    def test_submit_picks_highest_valid_build_attaches_and_submits(self):
        client = FakeAscClient()
        client.builds = [
            make_build("b-other", "99999999", marketing_version="0.2.0", state="VALID"),
            make_build("b-proc", "26111900", marketing_version="0.1.0", state="PROCESSING"),
            make_build("b-old", "26111810", marketing_version="0.1.0", state="VALID"),
            make_build("b-new", "26111815", marketing_version="0.1.0", state="VALID"),
        ]
        client.reject_public_link_until_attached = True

        with (
            patch.object(release, "asc_get", side_effect=client.asc_get),
            patch.object(release, "asc_post", side_effect=client.asc_post),
            patch.object(release, "asc_patch", side_effect=client.asc_patch),
        ):
            result = public_beta.submit_public_beta(
                "token",
                client.app_id,
                group_name="Clove Public Beta",
                feedback_email="mrtoniliu@gmail.com",
                marketing_version="0.1.0",
                public_link_limit=500,
            )

        self.assertEqual(result["build"]["id"], "b-new")
        self.assertEqual(result["betaReviewState"], "WAITING_FOR_REVIEW")
        self.assertTrue(result["publicLinkEnabled"])
        self.assertIn("https://testflight.apple.com/join/", result["publicLink"])
        self.assertEqual(len(client.build_localizations["b-new"]), 3)
        group_id = result["group"]["id"]
        self.assertEqual(client.group_builds[group_id], ["b-new"])
        self.assertEqual(result["group"]["attributes"]["publicLinkLimit"], 500)
        self.assertTrue(result["group"]["attributes"]["publicLinkLimitEnabled"])

    def test_submit_waits_for_processing_build_when_specified(self):
        client = FakeAscClient()
        build = make_build("b-wait", "26111820", marketing_version="0.1.0", state="PROCESSING")
        client.builds = [build]

        polls = {"count": 0}

        def fake_sleep(_seconds):
            polls["count"] += 1
            build["attributes"]["processingState"] = "VALID"

        with (
            patch.object(release, "asc_get", side_effect=client.asc_get),
            patch.object(release, "asc_post", side_effect=client.asc_post),
            patch.object(release, "asc_patch", side_effect=client.asc_patch),
        ):
            result = public_beta.submit_public_beta(
                "token",
                client.app_id,
                group_name="Clove Public Beta",
                feedback_email="mrtoniliu@gmail.com",
                marketing_version="0.1.0",
                build_number="26111820",
                wait_seconds=60,
                poll_interval=1,
                sleep_fn=fake_sleep,
            )

        self.assertEqual(polls["count"], 1)
        self.assertEqual(result["build"]["id"], "b-wait")
        self.assertEqual(result["betaReviewState"], "WAITING_FOR_REVIEW")

    def test_submit_is_idempotent_when_already_attached_and_submitted(self):
        client = FakeAscClient()
        client.builds = [make_build("b-1", "26111815", marketing_version="0.1.0", state="VALID")]
        client.groups = [
            {
                "type": "betaGroups",
                "id": "g-1",
                "attributes": {
                    "name": "Clove Public Beta",
                    "isInternalGroup": False,
                    "feedbackEnabled": True,
                    "publicLinkEnabled": False,
                },
            }
        ]
        client.group_builds["g-1"] = ["b-1"]
        client.review_submissions["b-1"] = {
            "type": "betaAppReviewSubmissions",
            "id": "sub-1",
            "attributes": {"betaReviewState": "IN_REVIEW"},
        }
        client.reject_public_link_until_approved = True

        with (
            patch.object(release, "asc_get", side_effect=client.asc_get),
            patch.object(release, "asc_post", side_effect=client.asc_post),
            patch.object(release, "asc_patch", side_effect=client.asc_patch),
        ):
            result = public_beta.submit_public_beta(
                "token",
                client.app_id,
                group_name="Clove Public Beta",
                feedback_email="mrtoniliu@gmail.com",
                marketing_version="0.1.0",
            )

        self.assertEqual(result["betaReviewState"], "IN_REVIEW")
        self.assertFalse(result["publicLinkEnabled"])
        self.assertIsNone(result["publicLink"])
        post_paths = [c[1] for c in client.calls if c[0] == "POST"]
        self.assertNotIn("betaGroups/g-1/relationships/builds", post_paths)
        self.assertNotIn("betaAppReviewSubmissions", post_paths)


class CliValidationTests(QuietTestCase):
    def test_requires_one_mode_flag(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            public_beta.main([])
        self.assertEqual(raised.exception.code, 2)

    def test_rejects_non_positive_public_link_limit(self):
        with self.assertRaisesRegex(release.ReleaseError, "positive integer"):
            public_beta.main(["--prepare", "--feedback-email", "a@b.com", "--public-link-limit", "0"])

    def test_requires_feedback_email_for_prepare(self):
        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            key = temp_path / "key.p8"
            key.write_text("KEY")
            key.chmod(0o600)
            cfg = temp_path / "cfg.json"
            cfg.write_text(json.dumps({
                "apiKeyId": "KID",
                "issuerId": "ISS",
                "apiKeyPath": str(key),
            }))
            cfg.chmod(0o600)
            with self.assertRaisesRegex(release.ReleaseError, "--feedback-email"):
                public_beta.main(["--config", str(cfg), "--prepare"])


if __name__ == "__main__":
    unittest.main()

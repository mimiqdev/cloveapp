#!/usr/bin/python3
"""Logic-only tests for the Clove fixture tooling. No network, no sips.

    /usr/bin/python3 scripts/test_fixtures.py

Covers manifest validation, checksum verification and repair with a fake
downloader, and the set layout built from fake input files. The committed
fixtures (``fixtures/manifest.json``, ``fixtures/sets.json``,
``fixtures/xmp/``) are checked too, so a broken fixture definition fails here
before a task ever downloads anything.
"""

import hashlib
import os
import shutil
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fixtures_lib as fx


def make_entry(entry_id="sample-file", payload=b"fixture payload", **overrides):
    entry = {
        "id": entry_id,
        "format": "CR3",
        "camera": "Canon EOS R6",
        "url": "https://example.com/%s.cr3" % entry_id,
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "source": "https://example.com/",
        "license": "CC0 1.0",
        "notes": "a fixture",
    }
    entry.update(overrides)
    return entry


def manifest_of(*entries):
    return {"schemaVersion": 1, "files": list(entries)}


class FakeDownloader(object):
    """Stands in for the network: serves payloads and records every call."""

    def __init__(self, payloads, failures=None):
        self.payloads = payloads
        self.failures = list(failures or [])
        self.calls = []

    def __call__(self, url, destination):
        self.calls.append(url)
        if self.failures:
            failure = self.failures.pop(0)
            if isinstance(failure, Exception):
                with open(destination, "wb") as handle:
                    handle.write(b"half a file")
                raise failure
            payload = failure
        else:
            payload = self.payloads[url]
        with open(destination, "wb") as handle:
            handle.write(payload)


class ManifestValidationTests(unittest.TestCase):
    def test_accepts_a_valid_manifest(self):
        entries = fx.validate_manifest(manifest_of(make_entry()))
        self.assertEqual(["sample-file"], [entry["id"] for entry in entries])

    def test_rejects_a_missing_files_list(self):
        with self.assertRaises(fx.FixtureError):
            fx.validate_manifest({"files": []})
        with self.assertRaises(fx.FixtureError):
            fx.validate_manifest([])

    def test_rejects_every_missing_required_field(self):
        for field in fx.MANIFEST_REQUIRED:
            entry = make_entry()
            del entry[field]
            with self.assertRaises(fx.FixtureError, msg="field %r" % field):
                fx.validate_manifest(manifest_of(entry))

    def test_rejects_duplicate_ids(self):
        with self.assertRaises(fx.FixtureError):
            fx.validate_manifest(manifest_of(make_entry(), make_entry()))

    def test_rejects_an_invalid_id(self):
        for bad_id in ("Sample", "sample file", "-sample", "sample_file", ""):
            with self.assertRaises(fx.FixtureError, msg="id %r" % bad_id):
                fx.validate_manifest(manifest_of(make_entry(entry_id=bad_id)))

    def test_rejects_a_bad_sha256(self):
        bad_values = (
            "abc",
            "81FAB349AE9080FD0172583B7FD5EA36806E95FFA434909D2CCC6527DDE34EE6",
            "zzfab349ae9080fd0172583b7fd5ea36806e95ffa434909d2ccc6527dde34ee6",
            "",
            12,
        )
        for value in bad_values:
            with self.assertRaises(fx.FixtureError, msg="sha256 %r" % (value,)):
                fx.validate_manifest(manifest_of(make_entry(sha256=value)))

    def test_rejects_a_bad_byte_count(self):
        for value in (0, -1, "12", True, 1.5):
            with self.assertRaises(fx.FixtureError, msg="bytes %r" % (value,)):
                fx.validate_manifest(manifest_of(make_entry(bytes=value)))

    def test_rejects_a_bad_url(self):
        for value in ("ftp://example.com/a.cr3", "example.com/a.cr3", "", "https://example.com/a b.cr3"):
            with self.assertRaises(fx.FixtureError, msg="url %r" % value):
                fx.validate_manifest(manifest_of(make_entry(url=value)))

    def test_rejects_an_empty_text_field(self):
        for field in ("format", "camera", "source", "license", "notes"):
            with self.assertRaises(fx.FixtureError, msg="field %r" % field):
                fx.validate_manifest(manifest_of(make_entry(**{field: "   "})))

    def test_entry_filename_uses_the_url_extension_lowercased(self):
        self.assertEqual("sample-file.cr3", fx.entry_filename(make_entry()))
        self.assertEqual(
            "canon-eos-6d-jpeg.jpg",
            fx.entry_filename(make_entry("canon-eos-6d-jpeg", url="https://example.com/a.JPG")),
        )


class VerificationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp(prefix="clove-verify-")
        self.addCleanup(lambda: shutil.rmtree(self.directory, ignore_errors=True))
        self.payload = b"verified bytes"
        self.entry = make_entry(payload=self.payload)
        self.path = os.path.join(self.directory, "file.cr3")

    def write(self, payload):
        with open(self.path, "wb") as handle:
            handle.write(payload)

    def test_missing_file(self):
        self.assertEqual((False, "missing"), fx.verify_file(self.path, self.entry))

    def test_size_mismatch(self):
        self.write(self.payload + b"x")
        ok, reason = fx.verify_file(self.path, self.entry)
        self.assertFalse(ok)
        self.assertIn("size", reason)

    def test_checksum_mismatch_with_the_right_size(self):
        self.write(b"x" * len(self.payload))
        ok, reason = fx.verify_file(self.path, self.entry)
        self.assertFalse(ok)
        self.assertIn("sha256", reason)

    def test_match(self):
        self.write(self.payload)
        self.assertEqual((True, "ok"), fx.verify_file(self.path, self.entry))


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp(prefix="clove-sync-")
        self.addCleanup(lambda: shutil.rmtree(self.directory, ignore_errors=True))
        self.payload = b"downloaded fixture bytes"
        self.entry = make_entry(payload=self.payload)
        self.destination = os.path.join(self.directory, "sample-file.cr3")
        self.logs = []

    def log(self, message):
        self.logs.append(message)

    def sync(self, downloader):
        return fx.sync_files([self.entry], self.directory, download=downloader, log=self.log)

    def test_downloads_a_missing_file(self):
        downloader = FakeDownloader({self.entry["url"]: self.payload})
        summary, failures = self.sync(downloader)
        self.assertEqual([], failures)
        self.assertEqual(1, summary["downloaded"])
        self.assertEqual(self.payload, open(self.destination, "rb").read())
        self.assertEqual(1, len(downloader.calls))

    def test_second_run_downloads_nothing(self):
        downloader = FakeDownloader({self.entry["url"]: self.payload})
        self.sync(downloader)
        summary, failures = self.sync(downloader)
        self.assertEqual([], failures)
        self.assertEqual(1, summary["cached"])
        self.assertEqual(0, summary["downloaded"])
        self.assertEqual(1, len(downloader.calls), "a cached file must not be downloaded again")

    def test_corrupt_file_is_deleted_and_downloaded_again(self):
        with open(self.destination, "wb") as handle:
            handle.write(self.payload + b"corruption")
        downloader = FakeDownloader({self.entry["url"]: self.payload})
        summary, failures = self.sync(downloader)
        self.assertEqual([], failures)
        self.assertEqual(1, summary["repaired"])
        self.assertEqual(self.payload, open(self.destination, "rb").read())
        self.assertTrue(any(log.startswith("repair") for log in self.logs))

    def test_a_download_that_never_matches_is_reported_and_kept_out(self):
        downloader = FakeDownloader({self.entry["url"]: b"wrong bytes entirely"})
        summary, failures = self.sync(downloader)
        self.assertEqual(1, summary["failed"])
        self.assertEqual(1, len(failures))
        self.assertEqual("sample-file", failures[0][0])
        self.assertIn("does not match the manifest", failures[0][1])
        self.assertFalse(os.path.exists(self.destination), "a bad file must not stay in the cache")
        self.assertFalse(os.path.exists(self.destination + ".part"))
        self.assertEqual(2, len(downloader.calls), "a mismatch is retried once")

    def test_a_bad_first_download_is_retried_and_kept(self):
        downloader = FakeDownloader(
            {self.entry["url"]: self.payload}, failures=[b"truncated"]
        )
        summary, failures = self.sync(downloader)
        self.assertEqual([], failures)
        self.assertEqual(1, summary["downloaded"])
        self.assertEqual(self.payload, open(self.destination, "rb").read())
        self.assertEqual(2, len(downloader.calls))

    def test_an_interrupted_download_leaves_no_file_under_the_final_name(self):
        downloader = FakeDownloader({}, failures=[RuntimeError("network went away")])
        summary, failures = self.sync(downloader)
        self.assertEqual(1, summary["failed"])
        self.assertIn("network went away", failures[0][1])
        self.assertFalse(os.path.exists(self.destination))
        self.assertFalse(os.path.exists(self.destination + ".part"))

    def test_bytes_only_appear_under_the_final_name_when_complete(self):
        seen = []

        def downloader(url, destination):
            seen.append(os.path.exists(self.destination))
            self.assertEqual(destination, self.destination + ".part")
            with open(destination, "wb") as handle:
                handle.write(self.payload)

        self.sync(downloader)
        self.assertEqual([False], seen)
        self.assertEqual(self.payload, open(self.destination, "rb").read())

    def test_fetch_entry_raises_when_the_checksum_never_matches(self):
        with self.assertRaises(fx.FixtureError) as caught:
            fx.fetch_entry(
                self.entry,
                self.destination,
                download=FakeDownloader({self.entry["url"]: b"nope"}),
            )
        self.assertIn("sample-file", str(caught.exception))
        self.assertFalse(os.path.exists(self.destination))
        self.assertFalse(os.path.exists(self.destination + ".part"))


class SetTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="clove-sets-")
        self.addCleanup(lambda: shutil.rmtree(self.root, ignore_errors=True))
        self.files = os.path.join(self.root, "files")
        self.generated = os.path.join(self.root, "generated")
        self.xmp = os.path.join(self.root, "xmp")
        self.output = os.path.join(self.root, "sets")
        for directory in (self.files, self.xmp):
            os.makedirs(directory)
        self.entry = make_entry()
        self.entries = [self.entry]
        self.recipes = [
            {
                "id": "jpeg-from-raw",
                "format": "JPEG",
                "extension": ".jpg",
                "tool": "sips",
                "args": ["-s", "format", "jpeg"],
                "notes": "fake recipe",
            }
        ]
        with open(os.path.join(self.files, "sample-file.cr3"), "wb") as handle:
            handle.write(b"raw bytes")
        with open(os.path.join(self.xmp, "lightroom-full.xmp"), "w", encoding="utf-8") as handle:
            handle.write("<x:xmpmeta/>\n")

    def resolve(self, document):
        return fx.resolve_sets(
            document, self.entries, self.recipes, self.files, self.xmp, self.generated
        )

    def build(self, document, generate=None):
        resolved = self.resolve(document)
        return fx.build_sets(resolved, self.output, generate=generate, log=lambda message: None)

    def listing(self, name="demo"):
        root = os.path.join(self.output, name)
        return fx.set_file_list(root, root)

    def document(self, entries, name="demo"):
        return {"sets": [{"name": name, "entries": entries}]}

    def test_builds_every_kind_of_entry(self):
        generated = []

        def generate(recipe, source, destination):
            generated.append((recipe["id"], source))
            with open(destination, "wb") as handle:
                handle.write(b"generated jpeg")

        document = self.document(
            [
                {"to": "DCIM/100CANON/IMG_0001.CR3", "from": "sample-file"},
                {"to": "DCIM/100CANON/IMG_0001.JPG", "from": "sample-file", "recipe": "jpeg-from-raw"},
                {"to": "DCIM/100CANON/IMG_0001.XMP", "fromXmp": "lightroom-full.xmp"},
                {"to": "DCIM/100CANON/._IMG_0001.CR3", "hex": "0005160700020000"},
                {"to": "DCIM/100CANON/.DS_Store", "text": "stub\n"},
                {"to": "DCIM/100CANON/_Rejected/IMG_9000.JPG", "from": "sample-file"},
            ]
        )
        report = self.build(document, generate=generate)
        self.assertEqual([("demo", 6)], report)
        self.assertEqual(
            [
                "DCIM/100CANON/.DS_Store",
                "DCIM/100CANON/._IMG_0001.CR3",
                "DCIM/100CANON/IMG_0001.CR3",
                "DCIM/100CANON/IMG_0001.JPG",
                "DCIM/100CANON/IMG_0001.XMP",
                "DCIM/100CANON/_Rejected/IMG_9000.JPG",
            ],
            self.listing(),
        )
        self.assertEqual([("jpeg-from-raw", os.path.join(self.files, "sample-file.cr3"))], generated)
        self.assertEqual(b"raw bytes", open(os.path.join(self.output, "demo/DCIM/100CANON/IMG_0001.CR3"), "rb").read())
        self.assertEqual(b"generated jpeg", open(os.path.join(self.output, "demo/DCIM/100CANON/IMG_0001.JPG"), "rb").read())
        self.assertEqual(b"stub\n", open(os.path.join(self.output, "demo/DCIM/100CANON/.DS_Store"), "rb").read())
        self.assertEqual(
            bytes.fromhex("0005160700020000"),
            open(os.path.join(self.output, "demo/DCIM/100CANON/._IMG_0001.CR3"), "rb").read(),
        )

    def test_repeat_expands_paths_and_writes_fixture_identity(self):
        document = {
            "sets": [
                {
                    "name": "demo",
                    "identity": True,
                    "entries": [
                        {"to": "DCIM/IMG_{index}.CR3", "from": "sample-file", "repeat": 3}
                    ],
                }
            ]
        }
        report = self.build(document)
        self.assertEqual([("demo", 3)], report)
        self.assertEqual(
            [
                ".clove-fixture.json",
                "DCIM/IMG_0001.CR3",
                "DCIM/IMG_0002.CR3",
                "DCIM/IMG_0003.CR3",
            ],
            self.listing(),
        )
        identity = fx.load_json(os.path.join(self.output, "demo", ".clove-fixture.json"))
        self.assertEqual("demo", identity["set"])
        self.assertEqual(3, identity["fileCount"])
        self.assertEqual(64, len(identity["definitionSHA256"]))
        self.assertEqual(
            {"sample-file": self.entry["sha256"]}, identity["sources"]
        )
        for path in self.listing():
            if path.endswith(".CR3"):
                with open(os.path.join(self.output, "demo", path), "rb") as handle:
                    self.assertEqual(b"raw bytes", handle.read())

    def test_repeat_one_replaces_the_index(self):
        document = self.document(
            [{"to": "IMG_{index}.CR3", "from": "sample-file", "repeat": 1}]
        )
        self.build(document)
        self.assertEqual(["IMG_0001.CR3"], self.listing())

    def test_identity_records_recipe_and_generated_bytes(self):
        document = {
            "sets": [
                {
                    "name": "demo",
                    "identity": True,
                    "entries": [
                        {
                            "to": "IMG.JPG",
                            "from": "sample-file",
                            "recipe": "jpeg-from-raw",
                        }
                    ],
                }
            ]
        }

        def generate(recipe, source, destination):
            with open(destination, "wb") as handle:
                handle.write(b"generated jpeg")

        self.build(document, generate=generate)
        identity = fx.load_json(os.path.join(self.output, "demo", ".clove-fixture.json"))
        self.assertEqual("sips", identity["recipes"]["jpeg-from-raw"]["tool"])
        self.assertEqual(
            {"jpeg-from-raw--sample-file.jpg": hashlib.sha256(b"generated jpeg").hexdigest()},
            identity["generated"],
        )

    def test_rejects_a_repeat_without_an_indexed_destination(self):
        document = self.document(
            [{"to": "IMG.CR3", "from": "sample-file", "repeat": 2}]
        )
        with self.assertRaises(fx.FixtureError):
            self.resolve(document)

    def test_rebuild_removes_files_from_an_older_definition(self):
        document = self.document([{"to": "a.txt", "text": "one\n"}])
        self.build(document)
        stale = os.path.join(self.output, "demo", "stale.bin")
        with open(stale, "wb") as handle:
            handle.write(b"left over")
        self.build(document)
        self.assertEqual(["a.txt"], self.listing())

    def test_the_file_list_is_the_same_on_every_run(self):
        document = self.document(
            [
                {"to": "DCIM/100CANON/IMG_0001.CR3", "from": "sample-file"},
                {"to": "DCIM/101CANON/IMG_0002.XMP", "fromXmp": "lightroom-full.xmp"},
            ]
        )
        self.build(document)
        first = self.listing()
        self.build(document)
        self.assertEqual(first, self.listing())

    def test_a_generated_file_is_built_once_and_reused(self):
        calls = []

        def generate(recipe, source, destination):
            calls.append(destination)
            with open(destination, "wb") as handle:
                handle.write(b"generated")

        document = self.document(
            [{"to": "IMG_0001.JPG", "from": "sample-file", "recipe": "jpeg-from-raw"}]
        )
        self.build(document, generate=generate)
        self.build(document, generate=generate)
        self.assertEqual(1, len(calls))
        self.assertEqual(
            os.path.join(self.generated, "jpeg-from-raw--sample-file.jpg"), calls[0]
        )
        self.assertEqual(["IMG_0001.JPG"], self.listing())

    def test_a_missing_download_points_at_fetch_fixtures(self):
        os.remove(os.path.join(self.files, "sample-file.cr3"))
        document = self.document([{"to": "IMG_0001.CR3", "from": "sample-file"}])
        with self.assertRaises(fx.FixtureError) as caught:
            self.build(document)
        self.assertIn("fetch-fixtures", str(caught.exception))

    def test_rejects_a_duplicate_destination(self):
        document = self.document(
            [
                {"to": "same.txt", "text": "one\n"},
                {"to": "same.txt", "text": "two\n"},
            ]
        )
        with self.assertRaises(fx.FixtureError):
            self.resolve(document)

    def test_rejects_a_path_that_escapes_the_set(self):
        for path in ("../escape.txt", "/absolute.txt", "DCIM/../../escape.txt"):
            document = self.document([{"to": path, "text": "x\n"}])
            with self.assertRaises(fx.FixtureError, msg=path):
                self.resolve(document)

    def test_rejects_an_unknown_manifest_id(self):
        document = self.document([{"to": "a.cr3", "from": "not-in-the-manifest"}])
        with self.assertRaises(fx.FixtureError):
            self.resolve(document)

    def test_rejects_an_unknown_recipe(self):
        document = self.document(
            [{"to": "a.jpg", "from": "sample-file", "recipe": "not-a-recipe"}]
        )
        with self.assertRaises(fx.FixtureError):
            self.resolve(document)

    def test_rejects_a_missing_sidecar(self):
        document = self.document([{"to": "a.XMP", "fromXmp": "missing.xmp"}])
        with self.assertRaises(fx.FixtureError):
            self.resolve(document)

    def test_rejects_an_entry_with_two_sources(self):
        document = self.document(
            [{"to": "a.cr3", "from": "sample-file", "text": "also text"}]
        )
        with self.assertRaises(fx.FixtureError):
            self.resolve(document)

    def test_rejects_an_entry_with_no_source(self):
        document = self.document([{"to": "a.cr3"}])
        with self.assertRaises(fx.FixtureError):
            self.resolve(document)

    def test_rejects_a_duplicate_set_name(self):
        document = {
            "sets": [
                {"name": "demo", "entries": [{"to": "a.txt", "text": "x\n"}]},
                {"name": "demo", "entries": [{"to": "b.txt", "text": "x\n"}]},
            ]
        }
        with self.assertRaises(fx.FixtureError):
            self.resolve(document)

    def test_rejects_a_bad_hex_value(self):
        for value in ("abc", "zz", ""):
            document = self.document([{"to": "a.bin", "hex": value}])
            with self.assertRaises(fx.FixtureError, msg=value):
                self.resolve(document)


class CommittedFixtureTests(unittest.TestCase):
    """The fixtures in the repository, checked without the network or the cache."""

    @classmethod
    def setUpClass(cls):
        cls.manifest = fx.load_json(fx.MANIFEST_PATH)
        cls.entries = fx.validate_manifest(cls.manifest)
        cls.recipes = fx.validate_recipes(fx.load_json(fx.GENERATED_PATH))
        cls.sets = fx.resolve_sets(
            fx.load_json(fx.SETS_PATH),
            cls.entries,
            cls.recipes,
            os.path.join(fx.DEFAULT_CACHE_DIR, "files"),
            fx.XMP_DIR,
            os.path.join(fx.DEFAULT_CACHE_DIR, "generated"),
        )

    def set_named(self, name):
        for spec in self.sets:
            if spec["name"] == name:
                return spec
        self.fail("no set named %r" % name)

    def paths(self, name):
        return [entry["to"] for entry in self.set_named(name)["entries"]]

    def test_the_five_sets_exist(self):
        self.assertEqual(
            ["card-basic", "xmp-interop", "name-collision", "browsing-2000", "formats"],
            [spec["name"] for spec in self.sets],
        )

    def test_every_required_format_is_covered(self):
        formats = {entry["format"] for entry in self.entries}
        for expected in ("CR3", "NEF", "ARW", "RAF", "ORF", "RW2", "DNG", "JPEG"):
            self.assertIn(expected, formats)
        self.assertTrue(
            any("ProRAW" in entry["format"] for entry in self.entries),
            "a ProRAW DNG entry is required",
        )

    def test_the_download_stays_under_one_gigabyte(self):
        total = sum(entry["bytes"] for entry in self.entries)
        self.assertLess(total, 1000 * 1000 * 1000, "the manifest is over the 1 GB budget")

    def test_every_entry_records_a_source_and_a_license(self):
        for entry in self.entries:
            self.assertTrue(entry["source"].startswith("http"), entry["id"])
            self.assertTrue(entry["license"].strip(), entry["id"])

    def test_no_entry_is_a_local_path(self):
        for entry in self.entries:
            self.assertTrue(entry["url"].startswith("https://"), entry["id"])

    def test_card_basic_layout(self):
        paths = self.paths("card-basic")
        dcim = {path.split("/")[1] for path in paths if path.startswith("DCIM/")}
        self.assertEqual({"100CANON", "101CANON"}, dcim)

        pairs = {
            "DCIM/100CANON/IMG_0001.CR3",
            "DCIM/100CANON/IMG_0001.JPG",
            "DCIM/100CANON/IMG_0002.NEF",
            "DCIM/100CANON/IMG_0002.JPG",
        }
        self.assertTrue(pairs.issubset(set(paths)), "RAW+JPG pairs with a shared base name")

        standalone = [
            path
            for path in paths
            if path.lower().endswith((".jpg", ".heic", ".dng")) and "/_Rejected/" not in path
        ]
        self.assertTrue(standalone, "a standalone JPEG, HEIC or DNG")
        self.assertTrue(any(path.endswith(".HEIC") for path in paths))
        self.assertTrue(any(os.path.basename(path).startswith("._") for path in paths))
        self.assertTrue(any(os.path.basename(path) == ".DS_Store" for path in paths))
        self.assertTrue(any(path.startswith(".Trashes/") for path in paths))
        self.assertTrue(any(path.endswith(".MOV") for path in paths))
        self.assertTrue(any(path.endswith(".txt") for path in paths))

        rejected = [path for path in paths if "/_Rejected/" in path]
        self.assertEqual(1, len(rejected), "an existing _Rejected folder with one photo")

    def test_xmp_interop_pairs_every_sidecar_with_a_raw(self):
        paths = self.paths("xmp-interop")
        sidecars = [path for path in paths if path.upper().endswith(".XMP")]
        self.assertEqual(11, len(sidecars))
        for sidecar in sidecars:
            base = os.path.splitext(sidecar)[0]
            siblings = [
                path
                for path in paths
                if os.path.splitext(path)[0] == base and not path.upper().endswith(".XMP")
            ]
            self.assertTrue(siblings, "%s has no RAW next to it" % sidecar)
            self.assertEqual(os.path.dirname(sidecar), os.path.dirname(siblings[0]))

    def test_name_collision_has_rejects_with_the_same_names(self):
        paths = self.paths("name-collision")
        rejected = {os.path.basename(path) for path in paths if "/_Rejected/" in path}
        active = {os.path.basename(path) for path in paths if "/_Rejected/" not in path}
        self.assertTrue(rejected)
        self.assertTrue(rejected & active, "a name must collide across _Rejected")

    def test_browsing_set_has_two_thousand_logical_photos(self):
        paths = self.paths("browsing-2000")
        self.assertEqual(4000, len(paths))
        stems = {os.path.splitext(path)[0] for path in paths}
        self.assertEqual(2000, len(stems))
        self.assertEqual(1200, len([path for path in paths if path.startswith("DCIM/100SONY/") and path.endswith(".ARW")]))
        self.assertEqual(600, len([path for path in paths if path.startswith("DCIM/101SONY/") and path.endswith(".HIF")]))
        self.assertEqual(100, len([path for path in paths if path.startswith("DCIM/102SONY/") and path.endswith(".HIF")]))
        self.assertTrue(self.set_named("browsing-2000")["identity"])

    def test_formats_set_holds_one_file_per_format(self):
        paths = self.paths("formats")
        extensions = {os.path.splitext(path)[1].lower() for path in paths}
        self.assertEqual(
            {".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2", ".dng", ".jpg", ".heic"},
            extensions,
        )
        self.assertEqual(
            10, len(paths), "nine extensions, plus the camera DNG and the ProRAW DNG"
        )
        self.assertEqual(
            2, len([path for path in paths if path.lower().endswith(".dng")])
        )
        self.assertTrue(all("/" not in path for path in paths), "the formats set is flat")

    def test_every_sidecar_in_the_folder_is_used(self):
        used = set()
        for spec in self.sets:
            for entry in spec["entries"]:
                if entry["kind"] == "copy" and entry["path"].startswith(fx.XMP_DIR + os.sep):
                    used.add(os.path.basename(entry["path"]))
        on_disk = {
            name
            for name in os.listdir(fx.XMP_DIR)
            if name.lower().endswith(".xmp")
        }
        self.assertEqual(on_disk, used)

    def test_well_formed_sidecars_parse_and_the_broken_one_does_not(self):
        broken = {"empty.xmp", "malformed.xmp"}
        for name in sorted(os.listdir(fx.XMP_DIR)):
            if not name.lower().endswith(".xmp"):
                continue
            path = os.path.join(fx.XMP_DIR, name)
            if name in broken:
                with self.assertRaises(ElementTree.ParseError, msg=name):
                    ElementTree.parse(path)
            else:
                ElementTree.parse(path)

    def test_the_empty_sidecar_is_zero_bytes(self):
        self.assertEqual(0, os.path.getsize(os.path.join(fx.XMP_DIR, "empty.xmp")))

    def test_every_sidecar_is_utf8_text_with_lf_endings(self):
        for name in sorted(os.listdir(fx.XMP_DIR)):
            if not name.lower().endswith(".xmp"):
                continue
            with open(os.path.join(fx.XMP_DIR, name), "rb") as handle:
                data = handle.read()
            self.assertNotIn(b"\r", data, "%s must use LF line endings" % name)
            data.decode("utf-8")


if __name__ == "__main__":
    unittest.main(verbosity=2)

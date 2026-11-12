#!/usr/bin/env python3
"""Exercise the runner's retry, skip and cleanup behavior without a simulator."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TARGET = "testDuoCoverToolbarMarkAndPickers"
TOOL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ["SMOKE_TEST_ROOT"])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as f:
    f.write(json.dumps([name, args]) + "\n")
if name == "xcrun":
    if args[:3] == ["simctl", "list", "runtimes"]:
        print(json.dumps({"runtimes": [{"identifier": "runtime.duo", "version": "27.2",
            "isAvailable": True, "platform": "iOS", "supportedDeviceTypes": [{"name": "iPhone Duo"}]}]}))
    elif args[:3] == ["simctl", "list", "devices"] and "--json" in args:
        print(json.dumps({"devices": {}}))
    elif args[:2] == ["simctl", "create"]:
        counter = root / "created"
        n = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(n))
        print("owned-" + str(n))
elif name == "xcodebuild":
    path = Path(args[args.index("-resultBundlePath") + 1])
    if path.exists():
        print("Result bundle already exists", file=sys.stderr)
        sys.exit(65)
    path.mkdir()
    count = root / "executions"
    n = int(count.read_text()) + 1 if count.exists() else 1
    count.write_text(str(n))
    mode = os.environ["SMOKE_TEST_MODE"]
    if mode == "retry" and n == 1:
        print("failed to initialize for UI testing")
        sys.exit(65)
    result = "skipped" if mode == "skip" else "passed"
    print("Test Case '-[CloveUITests.CloveFlowTests testDuoCoverToolbarMarkAndPickers]' " + result)
'''


class SmokeRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="clove-smoke-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/smoke.sh", self.root / "scripts/smoke.sh")
        (self.root / "Clove.xcodeproj").mkdir()
        products = self.root / ".build/DerivedData.noindex/Build/Products"
        products.mkdir(parents=True)
        (products / "Clove_test.xctestrun").touch()
        tools = self.root / "bin"
        tools.mkdir()
        for name in ["xcrun", "xcodebuild"]:
            path = tools / name
            path.write_text(TOOL)
            path.chmod(0o755)
        self.environment = dict(os.environ)
        for name in ["CLOVE_SIM_DEVICE_TYPE", "CLOVE_SIM_RUNTIME"]:
            self.environment.pop(name, None)
        self.environment.update(
            PATH=str(tools) + os.pathsep + os.environ["PATH"],
            SMOKE_TEST_ROOT=str(self.root),
            CLOVE_SIM_TAG="focused",
            CLOVE_SMOKE_ATTEMPTS="2",
        )

    def run_runner(self, mode, extra=None):
        environment = {**self.environment, "SMOKE_TEST_MODE": mode, **(extra or {})}
        result = subprocess.run(
            ["bash", "scripts/smoke.sh", "flows",
             "-only-testing:CloveUITests/CloveFlowTests/" + TARGET,
             "-resultBundlePath", str(self.root / "result.xcresult")],
            cwd=self.root, env=environment, text=True, capture_output=True, timeout=15,
        )
        calls = self.root / "calls.jsonl"
        records = [json.loads(line) for line in calls.read_text().splitlines()]
        return result, records

    def test_bootstrap_retry_keeps_both_bundles_and_cleans_each_owned_device(self):
        result, calls = self.run_runner("retry")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        commands = [args for tool, args in calls if tool == "xcodebuild"]
        paths = [args[args.index("-resultBundlePath") + 1] for args in commands]
        self.assertEqual(paths, [str(self.root / "result.xcresult"),
                                 str(self.root / "result.attempt-2.xcresult")])
        self.assertTrue(all(Path(path).is_dir() for path in paths))
        names = [args[2] for tool, args in calls if tool == "xcrun" and args[:2] == ["simctl", "create"]]
        self.assertEqual(len(set(names)), 2)
        deleted = [args[2] for tool, args in calls if tool == "xcrun" and args[:2] == ["simctl", "delete"]]
        self.assertEqual(deleted, ["owned-1", "owned-2"])

    def test_skipped_duo_test_is_failure_and_still_cleans_owned_device(self):
        result, calls = self.run_runner("skip")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("a skipped Duo test is not success", result.stderr)
        self.assertIn(["xcrun", ["simctl", "delete", "owned-1"]], calls)

    def test_incompatible_runtime_override_fails_before_creating_device(self):
        result, calls = self.run_runner("pass", {"CLOVE_SIM_RUNTIME": "runtime.phone"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(tool == "xcrun" and args[:2] == ["simctl", "create"] for tool, args in calls))

    def test_expanded_flow_is_rejected_headlessly_without_creating_a_device(self):
        environment = {**self.environment, "SMOKE_TEST_MODE": "pass"}
        result = subprocess.run(
            ["bash", "scripts/smoke.sh", "flows",
             "-only-testing:CloveUITests/CloveFlowTests/testDuoGridFocusDockMarkAndPhotoOnly"],
            cwd=self.root, env=environment, text=True, capture_output=True, timeout=15,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no headless runner", result.stderr)
        calls = self.root / "calls.jsonl"
        records = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
        self.assertFalse(
            any(tool == "xcrun" and args[:2] == ["simctl", "create"] for tool, args in records))


if __name__ == "__main__":
    unittest.main()

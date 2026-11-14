#!/usr/bin/env python3
"""Exercise the Duo helper cache's rebuild-on-load-failure path without a real dyld failure."""

import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
XCODE_PATH = "/Applications/Xcode_27.2.app/Contents/Developer"
XCODE_VERSION = "Xcode 27.2\nBuild version 17C52"
MACOS_BUILD = "25C56"
TOOLCHAIN = f"{XCODE_PATH}\n{XCODE_VERSION}\n{MACOS_BUILD}\n"

TOOL = f'''#!/usr/bin/env bash
set -eu
root="${{DUO_TEST_ROOT:?}}"
name="${{0##*/}}"
printf '%s\\n' "$name $*" >> "$root/calls"
case "$name" in
    xcode-select) printf '%s\\n' {shlex.quote(XCODE_PATH)} ;;
    xcodebuild) printf '%s\\n' {shlex.quote(XCODE_VERSION)} ;;
    sw_vers) printf '%s\\n' {shlex.quote(MACOS_BUILD)} ;;
    xcrun)
        printf '%s\\n' "$*" >> "$root/compiles"
        for output; do :; done
        cp "${{DUO_TEST_REBUILT:?}}" "$output"
        chmod +x "$output"
        ;;
    *) exit 64 ;;
esac
'''


class DuoPoseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="clove-duo-pose-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/duo-pose.sh", self.root / "scripts/duo-pose.sh")
        (self.root / "scripts/duo-devicehub.swift").write_text("// test source\n")
        (self.root / "tmp").mkdir()
        self.tools = self.root / "bin"
        self.tools.mkdir()
        for name in ["xcode-select", "xcodebuild", "sw_vers", "xcrun"]:
            path = self.tools / name
            path.write_text(TOOL)
            path.chmod(0o755)
        self.helper = self.root / ".build/DerivedData.noindex/Tools/duo-devicehub"
        self.helper.parent.mkdir(parents=True)
        self.environment = dict(os.environ)
        self.environment.pop("DUO_TEST_REBUILT", None)
        self.environment.update(
            PATH=str(self.tools) + os.pathsep + os.environ["PATH"],
            DUO_TEST_ROOT=str(self.root),
            TMPDIR=str(self.root / "tmp"),
        )

    def write_stamp(self):
        Path(str(self.helper) + ".toolchain").write_text(TOOLCHAIN)

    def write_helper(self, path, label, stdout=None, stderr=None, status=0):
        lines = [
            "#!/usr/bin/env bash",
            f"""printf '%s\\n' {shlex.quote(label)} >> "$DUO_TEST_ROOT/runs\"""",
        ]
        if stdout is not None:
            lines.append(f"printf '%s\\n' {shlex.quote(stdout)}")
        if stderr is not None:
            lines.append(f"printf '%s\\n' {shlex.quote(stderr)} >&2")
        lines.append(f"exit {status}")
        path.write_text("\n".join(lines) + "\n")
        path.chmod(0o755)

    def rebuilt_helper(self, **kwargs):
        path = self.root / "rebuilt-helper"
        self.write_helper(path, "rebuilt", **kwargs)
        self.environment["DUO_TEST_REBUILT"] = str(path)

    def run_script(self, *arguments):
        return subprocess.run(
            ["bash", "scripts/duo-pose.sh", *arguments],
            cwd=self.root,
            env=self.environment,
            text=True,
            capture_output=True,
            timeout=15,
        )

    def records(self, name):
        path = self.root / name
        return path.read_text().splitlines() if path.exists() else []

    def test_cached_load_failure_rebuilds_once_and_retries(self):
        self.write_stamp()
        self.write_helper(
            self.helper,
            "cached",
            stderr="dyld[123]: Symbol not found: _AXUIElementCopyAttributeValue",
            status=134,
        )
        self.rebuilt_helper(stdout="rebuilt helper ran")
        result = self.run_script("--pose", "open")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.records("runs"), ["cached", "rebuilt"])
        self.assertEqual(len(self.records("compiles")), 1)
        self.assertIn("rebuilt helper ran", result.stdout)

    def test_second_load_failure_is_reported_without_another_rebuild(self):
        self.write_stamp()
        self.write_helper(self.helper, "cached", stderr="dyld[123]: missing symbol", status=134)
        self.rebuilt_helper(
            stderr="dyld[456]: Library not loaded: @rpath/AppKit.framework/AppKit", status=134
        )
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.records("runs"), ["cached", "rebuilt"])
        self.assertEqual(len(self.records("compiles")), 1)
        self.assertIn("Library not loaded", result.stderr)

    def test_load_failure_of_a_fresh_build_is_not_rebuilt(self):
        self.rebuilt_helper(stderr="dyld[789]: Bad CPU type in executable", status=134)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.records("runs"), ["rebuilt"])
        self.assertEqual(len(self.records("compiles")), 1)
        self.assertIn("Bad CPU type", result.stderr)

    def test_other_helper_failure_is_not_rebuilt(self):
        self.write_stamp()
        self.write_helper(
            self.helper,
            "cached",
            stderr="Accessibility access was revoked. Run scripts/duo-pose.sh --request-access.",
            status=77,
        )
        result = self.run_script("--check-access")
        self.assertEqual(result.returncode, 77)
        self.assertEqual(self.records("runs"), ["cached"])
        self.assertEqual(self.records("compiles"), [])
        self.assertIn("Accessibility access was revoked", result.stderr)

    def test_current_cached_helper_runs_without_rebuilding(self):
        self.write_stamp()
        self.write_helper(self.helper, "cached", stdout="cached helper ran")
        result = self.run_script("--inspect")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.records("runs"), ["cached"])
        self.assertEqual(self.records("compiles"), [])
        self.assertIn("cached helper ran", result.stdout)


if __name__ == "__main__":
    unittest.main()

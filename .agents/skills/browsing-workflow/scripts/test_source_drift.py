#!/usr/bin/env python3
"""Unit tests for the fail-closed, symbol-scoped Swift source drift gate."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[3]
SKILL_SYNC = SCRIPT_DIR.parent / "model" / "source-sync.json"

sys.path.insert(0, str(SCRIPT_DIR))
import source_drift  # noqa: E402


SAMPLE_PURE_SWIFT = """\
struct PureRules {
    func step(_ x: Int) -> Int { x + 1 }
}
"""

SAMPLE_MIXED_SWIFT = """\
import SwiftUI

@MainActor
@Observable
final class SampleModel {
    private var labelFilter: String?

    var canMark: Bool {
        labelFilter == nil
    }

    @discardableResult
    func apply(_ value: Int, to id: String) -> Bool {
        // Initial comment inside tracked body
        let msg = "brace { } // not-comment /* still string */ \\"quote\\""
        let raw = #"raw { } // /* \\#" inside \\#(value /* interp */ + 1)"#
        let multi = \"\"\"
            line 1 { }
            line 2 // /*
            \"\"\"
        return !msg.isEmpty && !raw.isEmpty && !multi.isEmpty
    }

    private func apply(
        _ update: String,
        generation: Int
    ) async {
        /* outer /* nested { } */ still comment */
        guard generation > 0 else { return }
        _ = update
    }

    func unrelatedUIHelper() -> String {
        "layout"
    }
}
"""


class SwiftLexerAndExtractorTests(unittest.TestCase):
    def test_handles_tricky_strings_and_nested_comments(self) -> None:
        decls = source_drift.extract_declarations(SAMPLE_MIXED_SWIFT)
        apply_mark, err1 = source_drift.resolve_unique_declaration(
            "Sample.swift",
            "@discardableResult func apply(_ value: Int, to id: String) -> Bool",
            decls,
            "test",
        )
        self.assertIsNone(err1)
        self.assertIsNotNone(apply_mark)

        apply_update, err2 = source_drift.resolve_unique_declaration(
            "Sample.swift",
            "private func apply(_ update: String, generation: Int) async",
            decls,
            "test",
        )
        self.assertIsNone(err2)
        self.assertIsNotNone(apply_update)

        # Comments are stripped; string contents (including // and /* and braces) remain intact.
        self.assertNotIn("Initial comment", apply_mark.normalized)
        self.assertIn("not-comment /* still string */", apply_mark.normalized)
        self.assertNotIn("still comment", apply_update.normalized)

    def test_protocol_requirements_and_extension_defaults_resolve_distinctly(self) -> None:
        swift = """\
@MainActor
protocol SampleLibrary: AnyObject {
    var openGeneration: Int { get }
    func closeFolder() async
    func pick(_ url: URL) async -> Bool
}

extension SampleLibrary {
    var openGeneration: Int { 0 }
    func closeFolder() async {}
    func pick(_ url: URL) async -> Bool { false }
}
"""
        decls = source_drift.extract_declarations(swift)
        proto_gen, err_proto = source_drift.resolve_unique_declaration(
            "Lib.swift", "var openGeneration: Int { get }", decls, "test"
        )
        ext_gen, err_ext = source_drift.resolve_unique_declaration(
            "Lib.swift", "var openGeneration: Int { 0 }", decls, "test"
        )
        ext_close, err_close = source_drift.resolve_unique_declaration(
            "Lib.swift", "func closeFolder() async", decls, "test"
        )
        self.assertIsNone(err_proto)
        self.assertIsNone(err_ext)
        self.assertIsNone(err_close)
        self.assertIsNotNone(proto_gen)
        self.assertIsNotNone(ext_gen)
        self.assertIsNotNone(ext_close)

        # Bare prefix matching both { get } and { 0 } fails closed as ambiguous.
        _, err_ambig = source_drift.resolve_unique_declaration(
            "Lib.swift", "var openGeneration: Int", decls, "test"
        )
        self.assertIsNotNone(err_ambig)
        self.assertEqual(err_ambig.kind, "ambiguous")

    def test_unterminated_string_or_comment_fails_closed(self) -> None:
        with self.assertRaises(source_drift.SwiftParseError):
            source_drift.extract_declarations('func f() { let x = "unclosed }')
        with self.assertRaises(source_drift.SwiftParseError):
            source_drift.extract_declarations("func f() { /* outer /* inner */ }")
        with self.assertRaises(source_drift.SwiftParseError):
            source_drift.extract_declarations("func f() {")


class GitDriftGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="clove-drift-test-")
        self.addCleanup(self.tempdir.cleanup)
        self.root = Path(self.tempdir.name)
        self._git("init")
        self._git("config", "user.email", "test@example.com")
        self._git("config", "user.name", "Test")

        (self.root / "Pure.swift").write_text(SAMPLE_PURE_SWIFT, encoding="utf-8")
        (self.root / "Mixed.swift").write_text(SAMPLE_MIXED_SWIFT, encoding="utf-8")
        self._git("add", "Pure.swift", "Mixed.swift")
        self._git("commit", "-m", "baseline")
        self.commit = self._git("rev-parse", "HEAD").strip()

        self.sync_path = self.root / "source-sync.json"
        self._write_sync(
            whole_files=["Pure.swift"],
            symbol_files={
                "Mixed.swift": [
                    "var canMark: Bool",
                    "@discardableResult func apply(_ value: Int, to id: String) -> Bool",
                    "private func apply(_ update: String, generation: Int) async",
                ]
            },
        )

    def _git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=True,
        )
        return result.stdout

    def _write_sync(self, whole_files: list[str], symbol_files: dict[str, list[str]]) -> None:
        self.sync_path.write_text(
            json.dumps(
                {"commit": self.commit, "wholeFiles": whole_files, "symbolFiles": symbol_files},
                indent=2,
            ),
            encoding="utf-8",
        )

    def test_clean_baseline_passes(self) -> None:
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertTrue(report.passed, [f.format_line() for f in report.failures])

    def test_editing_comments_whitespace_and_unrelated_ui_passes(self) -> None:
        updated = SAMPLE_MIXED_SWIFT.replace(
            "// Initial comment inside tracked body",
            "// Updated doc note with { } and /* nested */ markers",
        ).replace(
            "private func apply(\n        _ update: String,\n        generation: Int\n    ) async {",
            "private func apply(_ update: String, generation: Int) async {",
        ).replace(
            'func unrelatedUIHelper() -> String {\n        "layout"\n    }',
            'func unrelatedUIHelper() -> String {\n        "new toast and filter UI"\n    }\n\n    var newUIProperty: Int { 42 }',
        )
        (self.root / "Mixed.swift").write_text(updated, encoding="utf-8")
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertTrue(report.passed, [f.format_line() for f in report.failures])

    def test_editing_tracked_symbol_body_fails_with_exact_path_and_symbol(self) -> None:
        updated = SAMPLE_MIXED_SWIFT.replace("labelFilter == nil", "labelFilter != nil")
        (self.root / "Mixed.swift").write_text(updated, encoding="utf-8")
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report.passed)
        self.assertEqual(len(report.failures), 1)
        failure = report.failures[0]
        self.assertEqual(failure.path, "Mixed.swift")
        self.assertEqual(failure.symbol, "var canMark: Bool")
        self.assertEqual(failure.kind, "drift")
        self.assertIn("Mixed.swift :: var canMark: Bool", failure.format_line())

    def test_editing_string_whitespace_inside_tracked_symbol_fails(self) -> None:
        updated = SAMPLE_MIXED_SWIFT.replace("line 1 { }", "line 1  { }")
        (self.root / "Mixed.swift").write_text(updated, encoding="utf-8")
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report.passed)
        self.assertEqual(report.failures[0].kind, "drift")
        self.assertIn("apply(_ value: Int, to id: String)", report.failures[0].format_line())

    def test_renaming_or_deleting_tracked_symbol_fails_closed(self) -> None:
        updated = SAMPLE_MIXED_SWIFT.replace("var canMark: Bool", "var canMarkPhoto: Bool")
        (self.root / "Mixed.swift").write_text(updated, encoding="utf-8")
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report.passed)
        self.assertEqual(report.failures[0].kind, "missing")
        self.assertIn("Mixed.swift :: var canMark: Bool", report.failures[0].format_line())

    def test_duplicate_declaration_in_working_tree_fails_closed(self) -> None:
        duplicate = "\n    var canMark: Bool { false }\n"
        updated = SAMPLE_MIXED_SWIFT.replace("    func unrelatedUIHelper()", duplicate + "    func unrelatedUIHelper()")
        (self.root / "Mixed.swift").write_text(updated, encoding="utf-8")
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report.passed)
        self.assertEqual(report.failures[0].kind, "ambiguous")
        self.assertIn("Mixed.swift :: var canMark: Bool", report.failures[0].format_line())

    def test_missing_symbol_in_baseline_fails_closed(self) -> None:
        self._write_sync(
            whole_files=["Pure.swift"],
            symbol_files={"Mixed.swift": ["func doesNotExist()"]},
        )
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report.passed)
        self.assertEqual(len(report.failures), 2)
        self.assertTrue(all(f.kind == "missing" for f in report.failures))

    def test_whole_file_edit_and_missing_file_fail_closed(self) -> None:
        (self.root / "Pure.swift").write_text(SAMPLE_PURE_SWIFT + "\n// edit\n", encoding="utf-8")
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report.passed)
        self.assertEqual(report.failures[0].path, "Pure.swift")
        self.assertIsNone(report.failures[0].symbol)

        (self.root / "Pure.swift").unlink()
        missing_report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(missing_report.passed)
        self.assertEqual(missing_report.failures[0].kind, "missing")


class RealRepoSanityTests(unittest.TestCase):
    def test_every_tracked_file_and_symbol_in_source_sync_resolves_against_head(self) -> None:
        report = source_drift.check_drift(REPO_ROOT, SKILL_SYNC, target_ref="HEAD")
        self.assertTrue(report.passed, [f.format_line() for f in report.failures])
        self.assertEqual(len(report.whole_files), 4)
        self.assertEqual(report.symbol_file_count, 5)
        self.assertGreaterEqual(report.symbol_count, 100)


if __name__ == "__main__":
    unittest.main()

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
    init(url: URL)
    func closeFolder() async
    func pick(_ url: URL) async -> Bool
}

extension SampleLibrary {
    var openGeneration: Int { 0 }
    init(url: URL) {}
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
        proto_init, err_proto_init = source_drift.resolve_unique_declaration(
            "Lib.swift",
            "@MainActor protocol SampleLibrary: AnyObject :: init(url: URL)",
            decls,
            "test",
        )
        ext_init, err_ext_init = source_drift.resolve_unique_declaration(
            "Lib.swift",
            "extension SampleLibrary :: init(url: URL)",
            decls,
            "test",
        )
        proto_close, err_proto_close = source_drift.resolve_unique_declaration(
            "Lib.swift",
            "@MainActor protocol SampleLibrary: AnyObject :: func closeFolder() async",
            decls,
            "test",
        )
        ext_close, err_ext_close = source_drift.resolve_unique_declaration(
            "Lib.swift",
            "extension SampleLibrary :: func closeFolder() async",
            decls,
            "test",
        )
        self.assertIsNone(err_proto)
        self.assertIsNone(err_ext)
        self.assertIsNone(err_proto_init)
        self.assertIsNone(err_ext_init)
        self.assertIsNone(err_proto_close)
        self.assertIsNone(err_ext_close)
        self.assertIsNotNone(proto_gen)
        self.assertIsNotNone(ext_gen)
        self.assertIsNotNone(proto_init)
        self.assertIsNotNone(ext_init)
        self.assertIsNotNone(proto_close)
        self.assertIsNotNone(ext_close)

        # Bare prefixes matching both protocol requirements and extension defaults fail closed.
        for ambiguous in ("var openGeneration: Int", "func closeFolder() async", "init(url: URL)"):
            _, err_ambig = source_drift.resolve_unique_declaration("Lib.swift", ambiguous, decls, "test")
            self.assertIsNotNone(err_ambig, ambiguous)
            self.assertEqual(err_ambig.kind, "ambiguous")

    def test_string_interpolation_delimiters_and_default_args_parse_cleanly(self) -> None:
        swift = """\
struct Sample {
    func g() {
        let s = "\\(1){\\(2)"
        let _ = s
    }

    func f(_ s: String = "\\(1)") {}
}
"""
        decls = source_drift.extract_declarations(swift)
        decl_g, err_g = source_drift.resolve_unique_declaration("Sample.swift", "func g()", decls, "test")
        decl_f, err_f = source_drift.resolve_unique_declaration(
            "Sample.swift", 'func f(_ s: String = "\\(1)")', decls, "test"
        )
        self.assertIsNone(err_g)
        self.assertIsNone(err_f)
        self.assertIsNotNone(decl_g)
        self.assertIsNotNone(decl_f)
        self.assertEqual(decl_g.start_line, 2)
        self.assertEqual(decl_g.end_line, 5)
        self.assertEqual(decl_f.start_line, 7)
        self.assertEqual(decl_f.end_line, 7)

    def test_operator_token_boundaries_preserve_distinct_operators(self) -> None:
        plus_unary = source_drift.extract_declarations("func f(_ a: Int, _ b: Int) -> Int { a + +b }")[0]
        plus_plus = source_drift.extract_declarations("func f(_ a: Int, _ b: Int) -> Int { a ++ b }")[0]
        self.assertNotEqual(plus_unary.fingerprint, plus_plus.fingerprint)

        range_tokens = [
            (t.kind, t.text)
            for t in source_drift.tokenize_swift("let r = 0..<n; let q = x ?? y; let s = a...b")
            if t.kind == "OP"
        ]
        self.assertEqual(
            range_tokens,
            [("OP", "="), ("OP", "..<"), ("OP", "="), ("OP", "??"), ("OP", "="), ("OP", "...")],
        )

    def test_conditional_compilation_directives_recorded_and_validated(self) -> None:
        swift = """\
#if FEATURE_A
func a() {}
#elseif FEATURE_B
func b() {}
#else
func c() {}
#endif
"""
        decls = source_drift.extract_declarations(swift)
        self.assertEqual(
            [(d.scope, d.conditions, d.full_tokens) for d in decls],
            [
                ((), ((("if", "FEATURE_A"),),), ("func", "a", "(", ")", "{", "}")),
                ((), ((("if", "FEATURE_A"), ("elseif", "FEATURE_B")),), ("func", "b", "(", ")", "{", "}")),
                (
                    (),
                    ((("if", "FEATURE_A"), ("elseif", "FEATURE_B"), ("else",)),),
                    ("func", "c", "(", ")", "{", "}"),
                ),
            ],
        )
        self.assertIn("[if=#if FEATURE_A / #elseif FEATURE_B / #else]", decls[2].normalized)

        for malformed in (
            "#else\nfunc a() {}\n#endif\n",
            "#elseif DEBUG\nfunc a() {}\n#endif\n",
            "#endif\n",
            "#if DEBUG\nfunc a() {}\n",
            "#if DEBUG\n#else\n#else\n#endif\n",
        ):
            with self.assertRaises(source_drift.SwiftParseError):
                source_drift.extract_declarations(malformed)

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

    def test_deleting_protocol_func_requirement_while_keeping_extension_default_fails(self) -> None:
        lib_swift = """\
protocol Lib {
    func closeFolder() async
}

extension Lib {
    func closeFolder() async {}
}
"""
        (self.root / "Lib.swift").write_text(lib_swift, encoding="utf-8")
        self._git("add", "Lib.swift")
        self._git("commit", "-m", "add protocol library")
        self.commit = self._git("rev-parse", "HEAD").strip()
        self._write_sync(
            whole_files=[],
            symbol_files={
                "Lib.swift": [
                    "protocol Lib :: func closeFolder() async",
                    "extension Lib :: func closeFolder() async",
                ]
            },
        )
        self.assertTrue(source_drift.check_drift(self.root, self.sync_path).passed)

        # Removing the protocol requirement while leaving the extension default must fail closed.
        (self.root / "Lib.swift").write_text(
            "protocol Lib {\n}\n\nextension Lib {\n    func closeFolder() async {}\n}\n",
            encoding="utf-8",
        )
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report.passed)
        self.assertEqual(len(report.failures), 1)
        self.assertEqual(report.failures[0].kind, "missing")
        self.assertIn("protocol Lib :: func closeFolder() async", report.failures[0].format_line())

    def test_wrapping_or_changing_conditional_compilation_directives_fails(self) -> None:
        cond_swift = """\
#if FEATURE_A
func guarded() -> Int { 1 }
#else
func guarded() -> Int { 2 }
#endif
"""
        (self.root / "Cond.swift").write_text(cond_swift, encoding="utf-8")
        self._git("add", "Cond.swift")
        self._git("commit", "-m", "add conditional file")
        self.commit = self._git("rev-parse", "HEAD").strip()
        self._write_sync(
            whole_files=[],
            symbol_files={
                "Mixed.swift": ["var canMark: Bool"],
                "Cond.swift": ["func guarded() -> Int { 2 }"],
            },
        )
        self.assertTrue(source_drift.check_drift(self.root, self.sync_path).passed)

        # Wrapping a tracked declaration in #if false ... #endif must fail drift.
        wrapped = SAMPLE_MIXED_SWIFT.replace(
            "    var canMark: Bool {",
            "#if false\n    var canMark: Bool {",
        ).replace(
            "        labelFilter == nil\n    }",
            "        labelFilter == nil\n    }\n#endif",
        )
        (self.root / "Mixed.swift").write_text(wrapped, encoding="utf-8")
        report_wrap = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report_wrap.passed)
        self.assertEqual(report_wrap.failures[0].kind, "drift")
        self.assertIn("Mixed.swift :: var canMark: Bool", report_wrap.failures[0].format_line())

        # Restoring Mixed.swift and flipping the #if condition gating an #else branch must fail drift.
        (self.root / "Mixed.swift").write_text(SAMPLE_MIXED_SWIFT, encoding="utf-8")
        (self.root / "Cond.swift").write_text(
            cond_swift.replace("#if FEATURE_A", "#if FEATURE_B"), encoding="utf-8"
        )
        report_cond = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report_cond.passed)
        self.assertEqual(report_cond.failures[0].kind, "drift")
        self.assertIn("Cond.swift :: func guarded() -> Int { 2 }", report_cond.failures[0].format_line())

    def test_changing_operator_token_boundaries_fails_drift(self) -> None:
        (self.root / "Ops.swift").write_text(
            "func combine(_ a: Int, _ b: Int) -> Int {\n    a + +b\n}\n", encoding="utf-8"
        )
        self._git("add", "Ops.swift")
        self._git("commit", "-m", "add ops")
        self.commit = self._git("rev-parse", "HEAD").strip()
        self._write_sync(
            whole_files=[],
            symbol_files={"Ops.swift": ["func combine(_ a: Int, _ b: Int) -> Int"]},
        )
        self.assertTrue(source_drift.check_drift(self.root, self.sync_path).passed)

        (self.root / "Ops.swift").write_text(
            "func combine(_ a: Int, _ b: Int) -> Int {\n    a ++ b\n}\n", encoding="utf-8"
        )
        report = source_drift.check_drift(self.root, self.sync_path)
        self.assertFalse(report.passed)
        self.assertEqual(report.failures[0].kind, "drift")


class RealRepoSanityTests(unittest.TestCase):
    def test_every_tracked_file_and_symbol_in_source_sync_resolves_against_head(self) -> None:
        report = source_drift.check_drift(REPO_ROOT, SKILL_SYNC, target_ref="HEAD")
        self.assertTrue(report.passed, [f.format_line() for f in report.failures])
        self.assertEqual(len(report.whole_files), 4)
        self.assertEqual(report.symbol_file_count, 5)
        self.assertEqual(report.symbol_count, 133)

        sync_data = json.loads(SKILL_SYNC.read_text(encoding="utf-8"))
        browsing = sync_data["symbolFiles"]["Clove/Browsing/BrowsingModel.swift"]
        self.assertIn("var openGeneration: Int", browsing)
        self.assertTrue(any(s.startswith("init(library: any FolderLibrary") for s in browsing))

        session = sync_data["symbolFiles"]["Clove/Folder/FolderLibrarySession.swift"]
        for expected_prefix in ("makeGrouping", "startGrouping", "publishGroups", "publish("):
            self.assertTrue(
                any(expected_prefix in s for s in session),
                f"Expected {expected_prefix!r} in FolderLibrarySession symbol tracking",
            )

        folder_lib = sync_data["symbolFiles"]["Clove/Browsing/FolderLibrary.swift"]
        self.assertTrue(
            any(s.startswith("@MainActor protocol FolderLibrary: AnyObject :: func closeFolder") for s in folder_lib)
        )
        self.assertTrue(any(s.startswith("extension FolderLibrary :: func closeFolder") for s in folder_lib))


if __name__ == "__main__":
    unittest.main()

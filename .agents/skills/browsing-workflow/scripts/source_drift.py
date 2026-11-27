#!/usr/bin/env python3
"""Fail-closed Swift lexer, declaration extractor, and symbol-scoped drift checker."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import subprocess
from typing import Iterable


MODIFIERS = frozenset(
    {
        "public",
        "internal",
        "fileprivate",
        "private",
        "open",
        "package",
        "final",
        "static",
        "override",
        "mutating",
        "nonmutating",
        "nonisolated",
        "convenience",
        "required",
        "dynamic",
        "indirect",
        "weak",
        "unowned",
        "lazy",
        "optional",
        "prefix",
        "infix",
        "postfix",
        "consuming",
        "borrowing",
        "distributed",
    }
)
PAREN_MODIFIERS = frozenset({"private", "fileprivate", "internal", "public", "package", "unowned"})
TYPE_KEYWORDS = frozenset({"struct", "class", "enum", "protocol", "actor", "extension"})
FUNC_KEYWORDS = frozenset({"func", "init", "deinit", "subscript"})
OTHER_DECL_KEYWORDS = frozenset(
    {"var", "let", "case", "typealias", "associatedtype", "import", "operator", "precedencegroup"}
)
ALL_DECL_KEYWORDS = TYPE_KEYWORDS | FUNC_KEYWORDS | OTHER_DECL_KEYWORDS
DIRECTIVE_KEYWORDS = frozenset({"if", "elseif", "else", "endif"})
LINE_CONTINUATION_PREV = frozenset({"=", "->", ".", "+", "*", "/", "&&", "||", "??", ":"})
MULTI_CHAR_OPS = (
    "===",
    "!==",
    "...",
    "..<",
    "->",
    "==",
    "!=",
    "<=",
    ">=",
    "&&",
    "||",
    "??",
    "+=",
    "-=",
    "*=",
    "/=",
    "%=",
    "&=",
    "|=",
    "^=",
    "~=",
)


class SwiftParseError(RuntimeError):
    """Raised when Swift lexing or brace-balanced extraction fails closed."""


@dataclass(frozen=True)
class Token:
    kind: str
    text: str
    start: int
    end: int
    line: int
    has_newline_before: bool


@dataclass(frozen=True)
class Declaration:
    header_tokens: tuple[str, ...]
    full_tokens: tuple[str, ...]
    normalized: str
    start_line: int
    end_line: int


@dataclass(frozen=True)
class DriftFailure:
    path: str
    symbol: str | None
    kind: str
    detail: str

    def format_line(self) -> str:
        target = f"{self.path} :: {self.symbol}" if self.symbol is not None else self.path
        return f"  {target} [{self.kind}]: {self.detail}"


@dataclass(frozen=True)
class DriftReport:
    commit: str
    whole_files: tuple[str, ...]
    symbol_count: int
    symbol_file_count: int
    failures: tuple[DriftFailure, ...]

    @property
    def passed(self) -> bool:
        return not self.failures


def _is_ident_start(ch: str) -> bool:
    return ch == "_" or ("A" <= ch <= "Z") or ("a" <= ch <= "z")


def _is_ident_continue(ch: str) -> bool:
    return _is_ident_start(ch) or ("0" <= ch <= "9")


def tokenize_swift(source: str) -> list[Token]:
    """Lex Swift source into non-whitespace, non-comment tokens.

    Handles line comments, nested /* ... */ block comments, normal strings,
    multiline strings (\"\"\"...\"\"\"), raw strings (#\"...\"# / #\"\"\"...\"\"\"#),
    string interpolations (\\(...) / \\#(...)), and raw regex literals (#/.../#).
    """
    tokens: list[Token] = []
    n = len(source)
    pos = 0
    line = 1
    newline_pending = False
    # Each entry: [pound_count, is_multiline, interp_paren_depth]
    string_stack: list[list[int | bool]] = []

    def emit(kind: str, text: str, start: int, end: int, tok_line: int) -> None:
        nonlocal newline_pending
        tokens.append(
            Token(
                kind=kind,
                text=text,
                start=start,
                end=end,
                line=tok_line,
                has_newline_before=newline_pending,
            )
        )
        newline_pending = False

    def scan_string_body(pound_count: int, is_multiline: bool, seg_start: int) -> None:
        nonlocal pos, line
        seg_line = line
        pounds = "#" * pound_count
        esc_prefix = "\\" + pounds
        close_delim = ('"""' if is_multiline else '"') + pounds

        while pos < n:
            if source.startswith(esc_prefix, pos):
                after = pos + len(esc_prefix)
                if after >= n:
                    raise SwiftParseError(f"Unterminated escape in string literal at line {line}")
                if source[after] == "(":
                    emit("STRING", source[seg_start:pos], seg_start, pos, seg_line)
                    emit("INTERP_OPEN", source[pos : after + 1], pos, after + 1, line)
                    string_stack.append([pound_count, is_multiline, 0])
                    pos = after + 1
                    return
                if source[after] == "\n":
                    line += 1
                pos = after + 1
                continue

            if source.startswith(close_delim, pos):
                pos += len(close_delim)
                emit("STRING", source[seg_start:pos], seg_start, pos, seg_line)
                return

            ch = source[pos]
            if not is_multiline and ch in ("\n", "\r"):
                raise SwiftParseError(f"Unterminated string literal at line {seg_line}")
            if ch == "\n":
                line += 1
            pos += 1

        raise SwiftParseError(f"Unterminated string literal starting at line {seg_line}")

    while pos < n:
        ch = source[pos]

        # Whitespace
        if ch in (" ", "\t", "\r", "\n"):
            if ch in ("\n", "\r"):
                newline_pending = True
            if ch == "\n":
                line += 1
            pos += 1
            continue

        # Line comment
        if source.startswith("//", pos):
            pos += 2
            while pos < n and source[pos] not in ("\n", "\r"):
                pos += 1
            continue

        # Nested block comment
        if source.startswith("/*", pos):
            start_line = line
            pos += 2
            depth = 1
            while pos < n and depth > 0:
                if source.startswith("/*", pos):
                    depth += 1
                    pos += 2
                elif source.startswith("*/", pos):
                    depth -= 1
                    pos += 2
                else:
                    if source[pos] == "\n":
                        line += 1
                        newline_pending = True
                    pos += 1
            if depth > 0:
                raise SwiftParseError(f"Unterminated block comment starting at line {start_line}")
            continue

        # Raw string (#"..."#, #"""..."""#) or raw regex (#/.../#)
        if ch == "#":
            k = 0
            while pos + k < n and source[pos + k] == "#":
                k += 1
            if pos + k < n and source[pos + k] == '"':
                seg_start = pos
                pos += k
                is_multiline = source.startswith('"""', pos)
                pos += 3 if is_multiline else 1
                scan_string_body(k, is_multiline, seg_start)
                continue
            if pos + k < n and source[pos + k] == "/":
                seg_start = pos
                seg_line = line
                pounds = "#" * k
                esc_prefix = "\\" + pounds
                close_delim = "/" + pounds
                pos += k + 1
                closed = False
                while pos < n:
                    if source.startswith(esc_prefix, pos):
                        after = pos + len(esc_prefix)
                        if after >= n:
                            raise SwiftParseError(f"Unterminated raw regex escape at line {line}")
                        if source[after] == "\n":
                            line += 1
                        pos = after + 1
                        continue
                    if source.startswith(close_delim, pos):
                        pos += len(close_delim)
                        emit("STRING", source[seg_start:pos], seg_start, pos, seg_line)
                        closed = True
                        break
                    if source[pos] == "\n":
                        line += 1
                    pos += 1
                if not closed:
                    raise SwiftParseError(f"Unterminated raw regex literal at line {seg_line}")
                continue
            emit("PUNCT", "#", pos, pos + 1, line)
            pos += 1
            continue

        # Normal or multiline string literal
        if ch == '"':
            seg_start = pos
            is_multiline = source.startswith('"""', pos)
            pos += 3 if is_multiline else 1
            scan_string_body(0, is_multiline, seg_start)
            continue

        # String interpolation paren tracking
        if ch == "(":
            if string_stack:
                string_stack[-1][2] = int(string_stack[-1][2]) + 1
            emit("PUNCT", "(", pos, pos + 1, line)
            pos += 1
            continue

        if ch == ")":
            if string_stack and int(string_stack[-1][2]) == 0:
                pound_count = int(string_stack[-1][0])
                is_multiline = bool(string_stack[-1][1])
                string_stack.pop()
                emit("INTERP_CLOSE", ")", pos, pos + 1, line)
                pos += 1
                scan_string_body(pound_count, is_multiline, pos)
                continue
            if string_stack:
                string_stack[-1][2] = int(string_stack[-1][2]) - 1
            emit("PUNCT", ")", pos, pos + 1, line)
            pos += 1
            continue

        # Backtick-escaped identifier
        if ch == "`":
            start = pos
            start_line = line
            pos += 1
            while pos < n and source[pos] not in ("`", "\n", "\r"):
                pos += 1
            if pos >= n or source[pos] != "`" or pos == start + 1:
                raise SwiftParseError(f"Unterminated backtick identifier at line {start_line}")
            pos += 1
            emit("WORD", source[start:pos], start, pos, start_line)
            continue

        # Identifier or implicit closure parameter ($0, $1)
        if _is_ident_start(ch) or (ch == "$" and pos + 1 < n and _is_ident_continue(source[pos + 1])):
            start = pos
            pos += 1
            while pos < n and _is_ident_continue(source[pos]):
                pos += 1
            emit("WORD", source[start:pos], start, pos, line)
            continue

        # Numeric literal
        if "0" <= ch <= "9":
            start = pos
            pos += 1
            while pos < n and (_is_ident_continue(source[pos])):
                pos += 1
            if pos + 1 < n and source[pos] == "." and ("0" <= source[pos + 1] <= "9"):
                pos += 1
                while pos < n and (_is_ident_continue(source[pos])):
                    pos += 1
            if pos < n and source[pos] in ("e", "E", "p", "P"):
                if pos + 1 < n and source[pos + 1] in ("+", "-"):
                    pos += 2
                else:
                    pos += 1
                while pos < n and (_is_ident_continue(source[pos])):
                    pos += 1
            emit("NUMBER", source[start:pos], start, pos, line)
            continue

        # Multi-character operators
        matched_op = None
        for op in MULTI_CHAR_OPS:
            if source.startswith(op, pos):
                matched_op = op
                break
        if matched_op is not None:
            emit("OP", matched_op, pos, pos + len(matched_op), line)
            pos += len(matched_op)
            continue

        # Single-character punctuation or operator
        kind = "PUNCT" if ch in "()[]{};:,.@#?!" else "OP"
        emit(kind, ch, pos, pos + 1, line)
        pos += 1

    if string_stack:
        raise SwiftParseError("Unterminated string interpolation at end of file")

    return tokens


def _build_brace_map(tokens: list[Token]) -> dict[int, int]:
    """Return {open_idx: close_idx} for every '{' and fail closed on unbalanced braces."""
    stack: list[int] = []
    mapping: dict[int, int] = {}
    for idx, tok in enumerate(tokens):
        if tok.text == "{":
            stack.append(idx)
        elif tok.text == "}":
            if not stack:
                raise SwiftParseError(f"Unmatched '}}' at line {tok.line}")
            open_idx = stack.pop()
            mapping[open_idx] = idx
    if stack:
        open_tok = tokens[stack[-1]]
        raise SwiftParseError(f"Unclosed '{{' at line {open_tok.line}")
    return mapping


def _skip_balanced(tokens: list[Token], idx: int, end: int, open_ch: str, close_ch: str) -> int:
    if idx >= end or tokens[idx].text != open_ch:
        raise SwiftParseError(f"Expected '{open_ch}' at token {idx}")
    depth = 0
    while idx < end:
        text = tokens[idx].text
        if text == open_ch:
            depth += 1
        elif text == close_ch:
            depth -= 1
            if depth == 0:
                return idx + 1
        idx += 1
    raise SwiftParseError(f"Unclosed '{open_ch}' before end of container")


def _skip_attribute(tokens: list[Token], idx: int, end: int) -> int:
    idx += 1
    if idx < end and tokens[idx].kind == "WORD":
        idx += 1
        while idx + 1 < end and tokens[idx].text == "." and tokens[idx + 1].kind == "WORD":
            idx += 2
    if idx < end and tokens[idx].text == "(":
        idx = _skip_balanced(tokens, idx, end, "(", ")")
    return idx


def _is_class_modifier(tokens: list[Token], idx: int, end: int) -> bool:
    """True when `class` acts as a member modifier (e.g. `class func`) rather than `class Name`."""
    k = idx + 1
    while k < end:
        tok = tokens[k]
        if tok.text == "@":
            k = _skip_attribute(tokens, k, end)
            continue
        if tok.text in MODIFIERS:
            mod = tok.text
            k += 1
            if mod in PAREN_MODIFIERS and k < end and tokens[k].text == "(":
                k = _skip_balanced(tokens, k, end, "(", ")")
            continue
        return tok.text in {"func", "var", "let", "subscript", "class"}
    return False


def _is_decl_start(tokens: list[Token], idx: int, end: int, prev_text: str) -> bool:
    if idx >= end:
        return True
    text = tokens[idx].text
    if text in ("}", ";"):
        return True
    if text == "#" and idx + 1 < end and tokens[idx + 1].text in DIRECTIVE_KEYWORDS:
        return True
    if prev_text in LINE_CONTINUATION_PREV:
        return False
    if text == "@":
        return True
    if text in ALL_DECL_KEYWORDS:
        return True
    if text in MODIFIERS:
        k = idx
        while k < end:
            cur = tokens[k].text
            if cur == "@":
                k = _skip_attribute(tokens, k, end)
            elif cur in MODIFIERS:
                k += 1
                if cur in PAREN_MODIFIERS and k < end and tokens[k].text == "(":
                    k = _skip_balanced(tokens, k, end, "(", ")")
            elif cur == "class":
                return _is_class_modifier(tokens, k, end)
            else:
                return cur in ALL_DECL_KEYWORDS
    return False


def _end_of_statement(tokens: list[Token], idx: int, end: int) -> int:
    paren = 0
    bracket = 0
    brace = 0
    k = idx
    while k < end:
        tok = tokens[k]
        if paren == 0 and bracket == 0 and brace == 0:
            if tok.text == ";":
                return k + 1
            if tok.text == "}":
                return k
            if tok.has_newline_before:
                prev_text = tokens[k - 1].text if k > 0 else ""
                if _is_decl_start(tokens, k, end, prev_text):
                    return k
        if tok.text == "(":
            paren += 1
        elif tok.text == ")":
            paren -= 1
        elif tok.text == "[":
            bracket += 1
        elif tok.text == "]":
            bracket -= 1
        elif tok.text == "{":
            brace += 1
        elif tok.text == "}":
            brace -= 1
        if paren < 0 or bracket < 0 or brace < 0:
            raise SwiftParseError(f"Unbalanced delimiter '{tok.text}' at line {tok.line}")
        k += 1
    return k


def extract_declarations(source: str) -> list[Declaration]:
    """Extract all brace-delimited Swift declarations at file/type/extension scope."""
    tokens = tokenize_swift(source)
    brace_map = _build_brace_map(tokens)
    declarations: list[Declaration] = []

    def record(decl_start: int, open_brace: int, close_brace: int) -> None:
        header = tuple(tok.text for tok in tokens[decl_start:open_brace])
        full = tuple(tok.text for tok in tokens[decl_start : close_brace + 1])
        declarations.append(
            Declaration(
                header_tokens=header,
                full_tokens=full,
                normalized=" ".join(full),
                start_line=tokens[decl_start].line,
                end_line=tokens[close_brace].line,
            )
        )

    def scan_container(start: int, end: int, in_protocol: bool) -> None:
        i = start
        while i < end:
            if tokens[i].text in (";", "}"):
                i += 1
                continue
            if tokens[i].text == "#" and i + 1 < end and tokens[i + 1].text in DIRECTIVE_KEYWORDS:
                k = i + 2
                while k < end and not tokens[k].has_newline_before:
                    k += 1
                i = k
                continue

            decl_start = i
            j = i
            while j < end:
                cur = tokens[j].text
                if cur == "@":
                    j = _skip_attribute(tokens, j, end)
                elif cur in MODIFIERS:
                    j += 1
                    if cur in PAREN_MODIFIERS and j < end and tokens[j].text == "(":
                        j = _skip_balanced(tokens, j, end, "(", ")")
                elif cur == "class" and _is_class_modifier(tokens, j, end):
                    j += 1
                else:
                    break

            if j >= end:
                break

            kw = tokens[j].text
            if kw in TYPE_KEYWORDS:
                k = j + 1
                paren = 0
                bracket = 0
                open_brace = None
                while k < end:
                    t = tokens[k].text
                    if paren == 0 and bracket == 0 and t == "{":
                        open_brace = k
                        break
                    if t == "(":
                        paren += 1
                    elif t == ")":
                        paren -= 1
                    elif t == "[":
                        bracket += 1
                    elif t == "]":
                        bracket -= 1
                    k += 1
                if open_brace is None:
                    raise SwiftParseError(f"Expected '{{' for '{kw}' at line {tokens[j].line}")
                close_brace = brace_map[open_brace]
                record(decl_start, open_brace, close_brace)
                scan_container(open_brace + 1, close_brace, in_protocol=(kw == "protocol"))
                i = close_brace + 1
                continue

            if kw in FUNC_KEYWORDS:
                if in_protocol:
                    i = _end_of_statement(tokens, j + 1, end)
                    continue
                k = j + 1
                paren = 0
                bracket = 0
                open_brace = None
                while k < end:
                    t = tokens[k].text
                    if paren == 0 and bracket == 0 and t == "{":
                        open_brace = k
                        break
                    if t == "(":
                        paren += 1
                    elif t == ")":
                        paren -= 1
                    elif t == "[":
                        bracket += 1
                    elif t == "]":
                        bracket -= 1
                    k += 1
                if open_brace is None:
                    raise SwiftParseError(f"Expected '{{' for '{kw}' at line {tokens[j].line}")
                close_brace = brace_map[open_brace]
                record(decl_start, open_brace, close_brace)
                i = close_brace + 1
                continue

            if kw == "var":
                k = j + 1
                paren = 0
                bracket = 0
                handled = False
                while k < end:
                    tok = tokens[k]
                    if paren == 0 and bracket == 0:
                        if tok.text == "=":
                            i = _end_of_statement(tokens, k + 1, end)
                            handled = True
                            break
                        if tok.text == "{":
                            close_brace = brace_map[k]
                            record(decl_start, k, close_brace)
                            i = close_brace + 1
                            handled = True
                            break
                        if tok.text == ";":
                            i = k + 1
                            handled = True
                            break
                        if tok.has_newline_before:
                            prev_text = tokens[k - 1].text if k > 0 else ""
                            if _is_decl_start(tokens, k, end, prev_text):
                                i = k
                                handled = True
                                break
                    if tok.text == "(":
                        paren += 1
                    elif tok.text == ")":
                        paren -= 1
                    elif tok.text == "[":
                        bracket += 1
                    elif tok.text == "]":
                        bracket -= 1
                    k += 1
                if not handled:
                    i = k
                continue

            i = _end_of_statement(tokens, j + 1, end)

    scan_container(0, len(tokens), in_protocol=False)
    return declarations


def normalize_signature_prefix(signature: str) -> tuple[str, ...]:
    """Tokenize a tracked signature prefix using the same Swift lexer."""
    tokens = tokenize_swift(signature)
    if not tokens:
        raise SwiftParseError("Empty symbol signature prefix")
    return tuple(tok.text for tok in tokens)


def find_matching_declarations(
    declarations: Iterable[Declaration], signature_prefix: str
) -> list[Declaration]:
    """Return every extracted declaration whose normalized tokens start with `signature_prefix`."""
    prefix = normalize_signature_prefix(signature_prefix)
    n = len(prefix)
    return [decl for decl in declarations if len(decl.full_tokens) >= n and decl.full_tokens[:n] == prefix]


def resolve_unique_declaration(
    path: str,
    symbol: str,
    declarations: list[Declaration],
    side: str,
) -> tuple[Declaration | None, DriftFailure | None]:
    """Resolve `symbol` uniquely (exactly 1 match); fail closed on 0 or >1 matches."""
    matches = find_matching_declarations(declarations, symbol)
    if len(matches) == 0:
        return None, DriftFailure(
            path=path,
            symbol=symbol,
            kind="missing",
            detail=f"0 matches in {side} (missing, renamed, or signature changed)",
        )
    if len(matches) > 1:
        lines = ", ".join(str(m.start_line) for m in matches)
        return None, DriftFailure(
            path=path,
            symbol=symbol,
            kind="ambiguous",
            detail=f"{len(matches)} matches in {side} at lines {lines}",
        )
    return matches[0], None


def _git_show_bytes(repo_root: Path, commit: str, rel_path: str) -> bytes:
    result = subprocess.run(
        ["git", "show", f"{commit}:{rel_path}"],
        cwd=repo_root,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip() or "git show failed"
        raise RuntimeError(detail)
    return result.stdout


def _load_sync_config(sync_path: Path) -> tuple[str, list[str], dict[str, list[str]]]:
    data = json.loads(sync_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError(f"{sync_path}: root must be a JSON object")
    commit = data.get("commit")
    whole_files = data.get("wholeFiles")
    symbol_files = data.get("symbolFiles")
    if not isinstance(commit, str) or not commit.strip():
        raise RuntimeError(f"{sync_path}: missing non-empty 'commit'")
    if not isinstance(whole_files, list) or not all(isinstance(p, str) and p for p in whole_files):
        raise RuntimeError(f"{sync_path}: 'wholeFiles' must be a list of file paths")
    if not isinstance(symbol_files, dict) or not symbol_files:
        raise RuntimeError(f"{sync_path}: 'symbolFiles' must be a non-empty object")
    overlap = set(whole_files) & set(symbol_files)
    if overlap:
        raise RuntimeError(f"{sync_path}: paths listed in both wholeFiles and symbolFiles: {sorted(overlap)}")
    if len(set(whole_files)) != len(whole_files):
        raise RuntimeError(f"{sync_path}: duplicate paths in 'wholeFiles'")
    cleaned_symbols: dict[str, list[str]] = {}
    for path, syms in symbol_files.items():
        if not isinstance(path, str) or not path:
            raise RuntimeError(f"{sync_path}: invalid path key in 'symbolFiles'")
        if not isinstance(syms, list) or not syms or not all(isinstance(s, str) and s.strip() for s in syms):
            raise RuntimeError(f"{sync_path}: symbols for '{path}' must be a non-empty list of strings")
        if len(set(syms)) != len(syms):
            raise RuntimeError(f"{sync_path}: duplicate symbol entry under '{path}'")
        cleaned_symbols[path] = syms
    return commit, whole_files, cleaned_symbols


def check_drift(repo_root: Path, sync_path: Path, target_ref: str | None = None) -> DriftReport:
    """Verify whole-file and symbol-scoped correspondence between baseline commit and target/working tree."""
    commit, whole_files, symbol_files = _load_sync_config(sync_path)

    verify_commit = subprocess.run(
        ["git", "rev-parse", "--verify", f"{commit}^{{commit}}"],
        cwd=repo_root,
        text=True,
        capture_output=True,
    )
    if verify_commit.returncode != 0:
        raise RuntimeError(f"Invalid baseline sync commit '{commit}': {verify_commit.stderr.strip()}")

    failures: list[DriftFailure] = []
    target_label = target_ref or "working tree"

    def read_target_bytes(rel_path: str) -> bytes:
        if target_ref is not None:
            return _git_show_bytes(repo_root, target_ref, rel_path)
        file_path = repo_root / rel_path
        if not file_path.is_file():
            raise FileNotFoundError(f"missing in working tree")
        return file_path.read_bytes()

    # 1. Whole-file checks (fail closed if missing on either side or bytes differ)
    for rel_path in whole_files:
        try:
            baseline_bytes = _git_show_bytes(repo_root, commit, rel_path)
        except RuntimeError as error:
            failures.append(DriftFailure(rel_path, None, "missing", f"baseline {commit[:12]}: {error}"))
            continue
        try:
            current_bytes = read_target_bytes(rel_path)
        except (FileNotFoundError, RuntimeError) as error:
            failures.append(DriftFailure(rel_path, None, "missing", f"{target_label}: {error}"))
            continue
        if baseline_bytes != current_bytes:
            failures.append(
                DriftFailure(rel_path, None, "drift", f"whole-file content changed since {commit[:12]}")
            )

    # 2. Symbol-scoped checks
    for rel_path, symbols in symbol_files.items():
        try:
            baseline_text = _git_show_bytes(repo_root, commit, rel_path).decode("utf-8")
        except (RuntimeError, UnicodeDecodeError) as error:
            for sym in symbols:
                failures.append(DriftFailure(rel_path, sym, "missing", f"baseline {commit[:12]}: {error}"))
            continue
        try:
            current_text = read_target_bytes(rel_path).decode("utf-8")
        except (FileNotFoundError, RuntimeError, UnicodeDecodeError) as error:
            for sym in symbols:
                failures.append(DriftFailure(rel_path, sym, "missing", f"{target_label}: {error}"))
            continue

        try:
            baseline_decls = extract_declarations(baseline_text)
        except SwiftParseError as error:
            for sym in symbols:
                failures.append(
                    DriftFailure(rel_path, sym, "parse-error", f"baseline {commit[:12]}: {error}")
                )
            continue

        try:
            current_decls = extract_declarations(current_text)
        except SwiftParseError as error:
            for sym in symbols:
                failures.append(
                    DriftFailure(rel_path, sym, "parse-error", f"{target_label}: {error}")
                )
            continue

        for sym in symbols:
            try:
                base_decl, base_err = resolve_unique_declaration(
                    rel_path, sym, baseline_decls, f"baseline {commit[:12]}"
                )
                cur_decl, cur_err = resolve_unique_declaration(
                    rel_path, sym, current_decls, target_label
                )
            except SwiftParseError as error:
                failures.append(DriftFailure(rel_path, sym, "invalid-symbol", str(error)))
                continue

            if base_err is not None:
                failures.append(base_err)
            if cur_err is not None:
                failures.append(cur_err)
            if base_decl is not None and cur_decl is not None and base_decl.normalized != cur_decl.normalized:
                failures.append(
                    DriftFailure(
                        rel_path,
                        sym,
                        "drift",
                        f"declaration changed (baseline lines {base_decl.start_line}-{base_decl.end_line}, "
                        f"{target_label} lines {cur_decl.start_line}-{cur_decl.end_line})",
                    )
                )

    total_symbols = sum(len(syms) for syms in symbol_files.values())
    return DriftReport(
        commit=commit,
        whole_files=tuple(whole_files),
        symbol_count=total_symbols,
        symbol_file_count=len(symbol_files),
        failures=tuple(failures),
    )

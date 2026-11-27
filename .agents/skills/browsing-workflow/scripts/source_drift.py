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
LINE_CONTINUATION_PREV = frozenset(
    {"=", "->", ".", ",", "&", "where", "+", "*", "/", "&&", "||", "??", ":"}
)
OP_RUN_CHARS = frozenset("=+-*/%<>|&^~")


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
    scope: tuple[tuple[str, ...], ...]
    conditions: tuple[tuple[tuple[str, ...], ...], ...]
    header_tokens: tuple[str, ...]
    full_tokens: tuple[str, ...]
    token_kinds: tuple[str, ...]
    normalized: str
    start_line: int
    end_line: int

    @property
    def fingerprint(self) -> tuple[object, ...]:
        return (self.scope, self.conditions, self.full_tokens, self.token_kinds)


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
    string interpolations (\\(...) / \\#(...)), raw regex literals (#/.../#),
    and maximal operator runs respecting whitespace boundaries.
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
            while pos < n and _is_ident_continue(source[pos]):
                pos += 1
            if pos + 1 < n and source[pos] == "." and ("0" <= source[pos + 1] <= "9"):
                pos += 1
                while pos < n and _is_ident_continue(source[pos]):
                    pos += 1
            if pos < n and source[pos] in ("e", "E", "p", "P"):
                if pos + 1 < n and source[pos + 1] in ("+", "-"):
                    pos += 2
                else:
                    pos += 1
                while pos < n and _is_ident_continue(source[pos]):
                    pos += 1
            emit("NUMBER", source[start:pos], start, pos, line)
            continue

        # Dot operators (..., ..<, etc.) vs member-access dot (.)
        if ch == ".":
            if pos + 1 < n and source[pos + 1] == ".":
                start = pos
                pos += 2
                while pos < n and (source[pos] == "." or source[pos] in OP_RUN_CHARS):
                    if source.startswith("//", pos) or source.startswith("/*", pos):
                        break
                    pos += 1
                emit("OP", source[start:pos], start, pos, line)
            else:
                emit("PUNCT", ".", pos, pos + 1, line)
                pos += 1
            continue

        # Special ?, ! operator forms (??, !=, !==) vs single ? / ! punctuation
        if ch == "?":
            if source.startswith("??", pos):
                emit("OP", "??", pos, pos + 2, line)
                pos += 2
            else:
                emit("PUNCT", "?", pos, pos + 1, line)
                pos += 1
            continue

        if ch == "!":
            if source.startswith("!==", pos):
                emit("OP", "!==", pos, pos + 3, line)
                pos += 3
            elif source.startswith("!=", pos):
                emit("OP", "!=", pos, pos + 2, line)
                pos += 2
            else:
                emit("PUNCT", "!", pos, pos + 1, line)
                pos += 1
            continue

        # Maximal operator runs respecting whitespace boundaries (a + +b != a ++ b)
        if ch in OP_RUN_CHARS:
            start = pos
            pos += 1
            while pos < n and source[pos] in OP_RUN_CHARS:
                if source.startswith("//", pos) or source.startswith("/*", pos):
                    break
                pos += 1
            emit("OP", source[start:pos], start, pos, line)
            continue

        # Single-character punctuation
        kind = "PUNCT" if ch in "()[]{};:,@" else "OP"
        emit(kind, ch, pos, pos + 1, line)
        pos += 1

    if string_stack:
        raise SwiftParseError("Unterminated string interpolation at end of file")

    return tokens


def _is_punct(tok: Token, text: str) -> bool:
    return tok.kind == "PUNCT" and tok.text == text


def _is_word(tok: Token, text: str | frozenset[str]) -> bool:
    if tok.kind != "WORD":
        return False
    if isinstance(text, str):
        return tok.text == text
    return tok.text in text


def _is_op(tok: Token, text: str | frozenset[str]) -> bool:
    if tok.kind != "OP":
        return False
    if isinstance(text, str):
        return tok.text == text
    return tok.text in text


def _build_brace_map(tokens: list[Token]) -> dict[int, int]:
    """Return {open_idx: close_idx} for every PUNCT '{' and fail closed on unbalanced braces."""
    stack: list[int] = []
    mapping: dict[int, int] = {}
    for idx, tok in enumerate(tokens):
        if _is_punct(tok, "{"):
            stack.append(idx)
        elif _is_punct(tok, "}"):
            if not stack:
                raise SwiftParseError(f"Unmatched '}}' at line {tok.line}")
            open_idx = stack.pop()
            mapping[open_idx] = idx
    if stack:
        open_tok = tokens[stack[-1]]
        raise SwiftParseError(f"Unclosed '{{' at line {open_tok.line}")
    return mapping


def _skip_balanced(tokens: list[Token], idx: int, end: int, open_ch: str, close_ch: str) -> int:
    if idx >= end or not _is_punct(tokens[idx], open_ch):
        raise SwiftParseError(f"Expected '{open_ch}' at token {idx}")
    depth = 0
    while idx < end:
        tok = tokens[idx]
        if _is_punct(tok, open_ch):
            depth += 1
        elif _is_punct(tok, close_ch):
            depth -= 1
            if depth == 0:
                return idx + 1
        idx += 1
    raise SwiftParseError(f"Unclosed '{open_ch}' before end of container")


def _skip_attribute(tokens: list[Token], idx: int, end: int) -> int:
    idx += 1
    if idx < end and tokens[idx].kind == "WORD":
        idx += 1
        while (
            idx + 1 < end
            and _is_punct(tokens[idx], ".")
            and tokens[idx + 1].kind == "WORD"
        ):
            idx += 2
    if idx < end and _is_punct(tokens[idx], "("):
        idx = _skip_balanced(tokens, idx, end, "(", ")")
    return idx


def _is_class_modifier(tokens: list[Token], idx: int, end: int) -> bool:
    """True when `class` acts as a member modifier (e.g. `class func`) rather than `class Name`."""
    k = idx + 1
    while k < end:
        tok = tokens[k]
        if _is_punct(tok, "@"):
            k = _skip_attribute(tokens, k, end)
            continue
        if _is_word(tok, MODIFIERS):
            mod = tok.text
            k += 1
            if mod in PAREN_MODIFIERS and k < end and _is_punct(tokens[k], "("):
                k = _skip_balanced(tokens, k, end, "(", ")")
            continue
        return _is_word(tok, {"func", "var", "let", "subscript", "class"})
    return False


def _is_directive(tokens: list[Token], idx: int, end: int) -> bool:
    return (
        idx + 1 < end
        and _is_punct(tokens[idx], "#")
        and _is_word(tokens[idx + 1], DIRECTIVE_KEYWORDS)
    )


def _is_decl_start(tokens: list[Token], idx: int, end: int, prev_tok: Token | None) -> bool:
    if idx >= end:
        return True
    tok = tokens[idx]
    if _is_punct(tok, "}") or _is_punct(tok, ";"):
        return True
    if _is_directive(tokens, idx, end):
        return True
    if prev_tok is not None and prev_tok.kind in ("PUNCT", "OP", "WORD"):
        if prev_tok.text in LINE_CONTINUATION_PREV and prev_tok.kind != "STRING":
            if prev_tok.kind != "WORD" or prev_tok.text == "where":
                return False
    if _is_punct(tok, "@"):
        return True
    if _is_word(tok, ALL_DECL_KEYWORDS):
        return True
    if _is_word(tok, MODIFIERS):
        k = idx
        while k < end:
            cur = tokens[k]
            if _is_punct(cur, "@"):
                k = _skip_attribute(tokens, k, end)
            elif _is_word(cur, MODIFIERS):
                mod = cur.text
                k += 1
                if mod in PAREN_MODIFIERS and k < end and _is_punct(tokens[k], "("):
                    k = _skip_balanced(tokens, k, end, "(", ")")
            elif _is_word(cur, "class"):
                return _is_class_modifier(tokens, k, end)
            else:
                return _is_word(cur, ALL_DECL_KEYWORDS)
    return False


def _end_of_statement(tokens: list[Token], idx: int, end: int) -> int:
    paren = 0
    bracket = 0
    brace = 0
    k = idx
    while k < end:
        tok = tokens[k]
        if paren == 0 and bracket == 0 and brace == 0:
            if _is_punct(tok, ";"):
                return k + 1
            if _is_punct(tok, "}"):
                return k
            if tok.has_newline_before:
                prev_tok = tokens[k - 1] if k > 0 else None
                if _is_decl_start(tokens, k, end, prev_tok):
                    return k
        if _is_punct(tok, "("):
            paren += 1
        elif _is_punct(tok, ")"):
            paren -= 1
        elif _is_punct(tok, "["):
            bracket += 1
        elif _is_punct(tok, "]"):
            bracket -= 1
        elif _is_punct(tok, "{"):
            brace += 1
        elif _is_punct(tok, "}"):
            brace -= 1
        if paren < 0 or bracket < 0 or brace < 0:
            raise SwiftParseError(f"Unbalanced delimiter '{tok.text}' at line {tok.line}")
        k += 1
    return k


def _find_open_brace(tokens: list[Token], idx: int, end: int, kw: str, kw_line: int) -> int:
    k = idx
    paren = 0
    bracket = 0
    while k < end:
        tok = tokens[k]
        if paren == 0 and bracket == 0 and _is_punct(tok, "{"):
            return k
        if _is_punct(tok, "("):
            paren += 1
        elif _is_punct(tok, ")"):
            paren -= 1
        elif _is_punct(tok, "["):
            bracket += 1
        elif _is_punct(tok, "]"):
            bracket -= 1
        if paren < 0 or bracket < 0:
            raise SwiftParseError(f"Unbalanced delimiter '{tok.text}' at line {tok.line}")
        k += 1
    raise SwiftParseError(f"Expected '{{' for '{kw}' at line {kw_line}")


def _format_conditions(conditions: tuple[tuple[tuple[str, ...], ...], ...]) -> str:
    if not conditions:
        return ""
    return " ; ".join(
        " / ".join("#" + " ".join(branch) for branch in block) for block in conditions
    )


def extract_declarations(source: str) -> list[Declaration]:
    """Extract brace-delimited and protocol-requirement Swift declarations with scope and #if context."""
    tokens = tokenize_swift(source)
    brace_map = _build_brace_map(tokens)
    declarations: list[Declaration] = []

    def record(
        decl_start: int,
        header_end: int,
        full_end: int,
        scope: tuple[tuple[str, ...], ...],
        cond_stack: list[list[tuple[str, ...]]],
    ) -> None:
        header = tuple(tok.text for tok in tokens[decl_start:header_end])
        full = tuple(tok.text for tok in tokens[decl_start:full_end])
        kinds = tuple(tok.kind for tok in tokens[decl_start:full_end])
        frozen_conds = tuple(tuple(block) for block in cond_stack)
        scope_str = " :: ".join(" ".join(part) for part in scope)
        cond_str = _format_conditions(frozen_conds)
        body_str = " ".join(full)
        if scope_str or cond_str:
            normalized = f"[scope={scope_str}] [if={cond_str}] {body_str}"
        else:
            normalized = body_str
        declarations.append(
            Declaration(
                scope=scope,
                conditions=frozen_conds,
                header_tokens=header,
                full_tokens=full,
                token_kinds=kinds,
                normalized=normalized,
                start_line=tokens[decl_start].line,
                end_line=tokens[full_end - 1].line,
            )
        )

    def scan_container(
        start: int,
        end: int,
        in_protocol: bool,
        scope: tuple[tuple[str, ...], ...],
        cond_stack: list[list[tuple[str, ...]]],
    ) -> None:
        initial_cond_depth = len(cond_stack)
        i = start
        while i < end:
            if _is_punct(tokens[i], ";") or _is_punct(tokens[i], "}"):
                i += 1
                continue
            if _is_directive(tokens, i, end):
                directive = tokens[i + 1].text
                directive_line = tokens[i].line
                k = i + 2
                cond_toks: list[str] = []
                while k < end and not tokens[k].has_newline_before:
                    cond_toks.append(tokens[k].text)
                    k += 1
                if directive == "if":
                    cond_stack.append([("if", *cond_toks)])
                elif directive == "elseif":
                    if len(cond_stack) <= initial_cond_depth:
                        raise SwiftParseError(f"Unmatched '#elseif' at line {directive_line}")
                    if cond_stack[-1][-1][0] == "else":
                        raise SwiftParseError(f"Unexpected '#elseif' after '#else' at line {directive_line}")
                    cond_stack[-1].append(("elseif", *cond_toks))
                elif directive == "else":
                    if len(cond_stack) <= initial_cond_depth:
                        raise SwiftParseError(f"Unmatched '#else' at line {directive_line}")
                    if cond_stack[-1][-1][0] == "else":
                        raise SwiftParseError(f"Duplicate '#else' at line {directive_line}")
                    cond_stack[-1].append(("else",))
                elif directive == "endif":
                    if len(cond_stack) <= initial_cond_depth:
                        raise SwiftParseError(f"Unmatched '#endif' at line {directive_line}")
                    cond_stack.pop()
                i = k
                continue

            decl_start = i
            j = i
            while j < end:
                cur = tokens[j]
                if _is_punct(cur, "@"):
                    j = _skip_attribute(tokens, j, end)
                elif _is_word(cur, MODIFIERS):
                    mod = cur.text
                    j += 1
                    if mod in PAREN_MODIFIERS and j < end and _is_punct(tokens[j], "("):
                        j = _skip_balanced(tokens, j, end, "(", ")")
                elif _is_word(cur, "class") and _is_class_modifier(tokens, j, end):
                    j += 1
                else:
                    break

            if j >= end:
                break

            kw_tok = tokens[j]
            if kw_tok.kind != "WORD":
                i = _end_of_statement(tokens, j + 1, end)
                continue

            kw = kw_tok.text
            if kw in TYPE_KEYWORDS:
                open_brace = _find_open_brace(tokens, j + 1, end, kw, kw_tok.line)
                close_brace = brace_map[open_brace]
                record(decl_start, open_brace, close_brace + 1, scope, cond_stack)
                child_scope = scope + (tuple(tok.text for tok in tokens[decl_start:open_brace]),)
                scan_container(
                    open_brace + 1,
                    close_brace,
                    in_protocol=(kw == "protocol"),
                    scope=child_scope,
                    cond_stack=cond_stack,
                )
                i = close_brace + 1
                continue

            if kw in FUNC_KEYWORDS:
                if in_protocol and kw in {"func", "init"}:
                    stmt_end = _end_of_statement(tokens, j + 1, end)
                    full_end = stmt_end - 1 if stmt_end > decl_start and _is_punct(tokens[stmt_end - 1], ";") else stmt_end
                    record(decl_start, full_end, full_end, scope, cond_stack)
                    i = stmt_end
                    continue
                open_brace = _find_open_brace(tokens, j + 1, end, kw, kw_tok.line)
                close_brace = brace_map[open_brace]
                record(decl_start, open_brace, close_brace + 1, scope, cond_stack)
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
                        if _is_op(tok, "="):
                            i = _end_of_statement(tokens, k + 1, end)
                            handled = True
                            break
                        if _is_punct(tok, "{"):
                            close_brace = brace_map[k]
                            record(decl_start, k, close_brace + 1, scope, cond_stack)
                            i = close_brace + 1
                            handled = True
                            break
                        if _is_punct(tok, ";"):
                            i = k + 1
                            handled = True
                            break
                        if tok.has_newline_before:
                            prev_tok = tokens[k - 1] if k > 0 else None
                            if _is_decl_start(tokens, k, end, prev_tok):
                                i = k
                                handled = True
                                break
                    if _is_punct(tok, "("):
                        paren += 1
                    elif _is_punct(tok, ")"):
                        paren -= 1
                    elif _is_punct(tok, "["):
                        bracket += 1
                    elif _is_punct(tok, "]"):
                        bracket -= 1
                    k += 1
                if not handled:
                    i = k
                continue

            i = _end_of_statement(tokens, j + 1, end)

        if len(cond_stack) != initial_cond_depth:
            raise SwiftParseError("Unclosed '#if' directive in container")

    scan_container(0, len(tokens), in_protocol=False, scope=(), cond_stack=[])
    return declarations


def _split_scoped_symbol(signature: str) -> tuple[list[tuple[str, ...]], tuple[str, ...]]:
    """Split `<scope> :: <member>` using the Swift lexer so `"::"` inside strings is ignored."""
    tokens = tokenize_swift(signature)
    if not tokens:
        raise SwiftParseError("Empty symbol signature prefix")

    parts: list[tuple[str, ...]] = []
    cur: list[str] = []
    idx = 0
    while idx < len(tokens):
        if (
            idx + 1 < len(tokens)
            and _is_punct(tokens[idx], ":")
            and _is_punct(tokens[idx + 1], ":")
        ):
            if not cur:
                raise SwiftParseError(f"Empty scope segment in symbol '{signature}'")
            parts.append(tuple(cur))
            cur = []
            idx += 2
            continue
        cur.append(tokens[idx].text)
        idx += 1

    if not cur:
        raise SwiftParseError(f"Missing member signature after '::' in '{signature}'")
    parts.append(tuple(cur))
    return parts[:-1], parts[-1]


def normalize_signature_prefix(signature: str) -> tuple[str, ...]:
    """Tokenize a tracked signature prefix using the same Swift lexer."""
    tokens = tokenize_swift(signature)
    if not tokens:
        raise SwiftParseError("Empty symbol signature prefix")
    return tuple(tok.text for tok in tokens)


def _scope_matches(decl_scope: tuple[tuple[str, ...], ...], scope_prefixes: list[tuple[str, ...]]) -> bool:
    if not scope_prefixes:
        return True
    if len(decl_scope) < len(scope_prefixes):
        return False
    tail = decl_scope[-len(scope_prefixes) :]
    return all(
        len(actual) >= len(expected) and actual[: len(expected)] == expected
        for actual, expected in zip(tail, scope_prefixes)
    )


def find_matching_declarations(
    declarations: Iterable[Declaration], signature_prefix: str
) -> list[Declaration]:
    """Return every extracted declaration matching optional enclosing scope and signature prefix."""
    scope_prefixes, member_prefix = _split_scoped_symbol(signature_prefix)
    n = len(member_prefix)
    return [
        decl
        for decl in declarations
        if _scope_matches(decl.scope, scope_prefixes)
        and len(decl.full_tokens) >= n
        and decl.full_tokens[:n] == member_prefix
    ]


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
            raise FileNotFoundError("missing in working tree")
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
            if base_decl is not None and cur_decl is not None and base_decl.fingerprint != cur_decl.fingerprint:
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

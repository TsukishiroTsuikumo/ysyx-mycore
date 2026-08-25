#!/usr/bin/env python3
"""Reject SystemVerilog source and common SV-only syntax under dut/.

This is a fast lexical companion to the authoritative Verilator
``--language 1364-2005`` lint.  Keeping it separate makes accidental uses of
syntax that Verilator accepts as an extension visible in local runs and CI.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DUT = ROOT / "dut"


def strip_comments_and_strings(source: str) -> str:
    """Replace comments and strings with spaces while preserving newlines."""

    out: list[str] = []
    index = 0
    state = "code"
    while index < len(source):
        char = source[index]
        next_char = source[index + 1] if index + 1 < len(source) else ""

        if state == "code":
            if char == "/" and next_char == "/":
                out.extend((" ", " "))
                index += 2
                state = "line_comment"
                continue
            if char == "/" and next_char == "*":
                out.extend((" ", " "))
                index += 2
                state = "block_comment"
                continue
            if char == '"':
                out.append(" ")
                index += 1
                state = "string"
                continue
            out.append(char)
            index += 1
            continue

        if state == "line_comment":
            if char == "\n":
                out.append("\n")
                state = "code"
            else:
                out.append(" ")
            index += 1
            continue

        if state == "block_comment":
            if char == "*" and next_char == "/":
                out.extend((" ", " "))
                index += 2
                state = "code"
                continue
            out.append("\n" if char == "\n" else " ")
            index += 1
            continue

        if state == "string":
            if char == "\\" and next_char:
                out.extend((" ", "\n" if next_char == "\n" else " "))
                index += 2
                continue
            if char == '"':
                out.append(" ")
                index += 1
                state = "code"
                continue
            out.append("\n" if char == "\n" else " ")
            index += 1

    return "".join(out)


FORBIDDEN = (
    (
        "SystemVerilog declaration/type keyword",
        re.compile(
            r"\b(?:logic|bit|byte|shortint|int|longint|struct|union|enum|"
            r"typedef|interface|modport|package|import|export|class|virtual|"
            r"extends|implements|chandle|string)\b"
        ),
    ),
    (
        "SystemVerilog procedural keyword",
        re.compile(
            r"\b(?:always_comb|always_ff|always_latch|final|foreach|inside|"
            r"dist|unique|unique0|priority|rand|randc|constraint)\b"
        ),
    ),
    ("SystemVerilog assertion keyword", re.compile(r"\b(?:assert|assume|cover|property|sequence)\b")),
    ("SystemVerilog scope operator", re.compile(r"::")),
    ("SystemVerilog assignment pattern", re.compile(r"'\s*\{")),
    ("SystemVerilog unbased literal", re.compile(r"(?<![A-Za-z0-9_])'[01xXzZ](?![A-Za-z0-9_])")),
    ("SystemVerilog increment/decrement operator", re.compile(r"\+\+|--")),
    ("SystemVerilog compound assignment", re.compile(r"(?:\+=|-=|\*=|/=|%=|&=|\|=|\^=|<<=|>>=)")),
    ("verification-only system task", re.compile(r"\$(?:error|fatal|warning|info)\b")),
)


def line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def main() -> int:
    bad_extensions = sorted(
        path.relative_to(ROOT)
        for path in DUT.rglob("*")
        if path.is_file() and path.suffix.lower() in {".sv", ".svh"}
    )

    failures: list[str] = []
    for path in bad_extensions:
        failures.append(f"{path}: SystemVerilog file extension is forbidden in dut/")

    sources = sorted(
        path for path in DUT.rglob("*") if path.is_file() and path.suffix.lower() in {".v", ".vh"}
    )
    for path in sources:
        text = strip_comments_and_strings(path.read_text(encoding="utf-8"))
        for description, pattern in FORBIDDEN:
            for match in pattern.finditer(text):
                relative = path.relative_to(ROOT)
                failures.append(
                    f"{relative}:{line_number(text, match.start())}: "
                    f"{description}: {match.group(0)!r}"
                )

    if failures:
        print("DUT_VERILOG_SYNTAX FAIL", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(f"DUT_VERILOG_SYNTAX PASS files={len(sources)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

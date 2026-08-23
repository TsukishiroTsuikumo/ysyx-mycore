#!/usr/bin/env python3
"""Enforce repository code-coverage thresholds on Verilator databases.

Verilator's ``SystemC::Coverage-3`` format stores compact key/value fields
separated by ASCII SOH/STX characters.  This checker reads that format
directly so line and toggle points can be kept separate (LCOV output does not
retain toggle coverage).  Multiple input databases are merged by normalized
source point before percentages are calculated.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping, Sequence


DEFAULT_THRESHOLDS = Path(__file__).with_name("coverage_thresholds.json")
SUPPORTED_METRICS = ("line", "toggle", "branch")
RECORD_RE = re.compile(r"^C\s+'(.*)'\s+(-?\d+)\s*$")


class CoverageError(ValueError):
    """Raised for malformed coverage input or threshold configuration."""


@dataclass(frozen=True)
class Scope:
    source_root: str
    excluded_path_parts: frozenset[str]


@dataclass(frozen=True)
class MetricPolicy:
    minimum_percent: float
    blocking: bool


@dataclass(frozen=True)
class CoverageConfig:
    covered_min_hits: int
    scope: Scope
    metrics: Mapping[str, MetricPolicy]


@dataclass(frozen=True)
class CoveragePoint:
    source: str
    metric: str
    line: str
    column: str
    page: str
    operation: str
    span: str


@dataclass(frozen=True)
class MetricResult:
    covered: int
    total: int
    percent: float
    policy: MetricPolicy

    @property
    def passes(self) -> bool:
        return self.total > 0 and self.percent + 1e-12 >= self.policy.minimum_percent


def _require_number(value: object, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CoverageError(f"{field} must be a number")
    number = float(value)
    if not 0.0 <= number <= 100.0:
        raise CoverageError(f"{field} must be between 0 and 100")
    return number


def load_config(path: Path) -> CoverageConfig:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CoverageError(f"cannot read threshold config {path}: {exc}") from exc

    if not isinstance(raw, dict):
        raise CoverageError("threshold config must contain a JSON object")

    covered_min_hits = raw.get("covered_min_hits")
    if isinstance(covered_min_hits, bool) or not isinstance(covered_min_hits, int):
        raise CoverageError("covered_min_hits must be an integer")
    if covered_min_hits < 1:
        raise CoverageError("covered_min_hits must be at least 1")

    raw_scope = raw.get("scope")
    if not isinstance(raw_scope, dict):
        raise CoverageError("scope must contain a JSON object")
    source_root = raw_scope.get("source_root")
    if not isinstance(source_root, str) or not source_root or "/" in source_root:
        raise CoverageError("scope.source_root must be one path component")
    raw_exclusions = raw_scope.get("excluded_path_parts", [])
    if not isinstance(raw_exclusions, list) or not all(
        isinstance(part, str) and part for part in raw_exclusions
    ):
        raise CoverageError("scope.excluded_path_parts must be a string array")

    raw_metrics = raw.get("metrics")
    if not isinstance(raw_metrics, dict):
        raise CoverageError("metrics must contain a JSON object")
    metrics: dict[str, MetricPolicy] = {}
    for metric in SUPPORTED_METRICS:
        raw_policy = raw_metrics.get(metric)
        if not isinstance(raw_policy, dict):
            raise CoverageError(f"metrics.{metric} must contain a JSON object")
        blocking = raw_policy.get("blocking")
        if not isinstance(blocking, bool):
            raise CoverageError(f"metrics.{metric}.blocking must be boolean")
        minimum = _require_number(
            raw_policy.get("minimum_percent"),
            f"metrics.{metric}.minimum_percent",
        )
        metrics[metric] = MetricPolicy(minimum, blocking)

    return CoverageConfig(
        covered_min_hits=covered_min_hits,
        scope=Scope(source_root, frozenset(raw_exclusions)),
        metrics=metrics,
    )


def normalize_source_path(raw_path: str, scope: Scope) -> str | None:
    """Return a stable ``dut/...`` path, or ``None`` when outside the scope.

    Coverage may be generated with relative paths, GitHub workspace absolute
    paths, or Windows separators.  Matching complete path components prevents
    directories such as ``some_dut`` from entering the DUT-only denominator.
    Known testbench/build components are rejected even if they contain a nested
    directory named ``dut``.
    """

    path = raw_path.replace("\\", "/")
    parts: list[str] = []
    for part in path.split("/"):
        if not part or part == ".":
            continue
        if part == "..":
            if parts and parts[-1] != "..":
                parts.pop()
            else:
                parts.append(part)
            continue
        parts.append(part)

    root_indexes = [
        index for index, part in enumerate(parts) if part == scope.source_root
    ]
    if not root_indexes:
        return None

    root_index = root_indexes[-1]
    if any(part in scope.excluded_path_parts for part in parts[:root_index]):
        return None
    relative_parts = parts[root_index:]
    if len(relative_parts) < 2:
        return None
    if any(part in scope.excluded_path_parts for part in relative_parts[1:]):
        return None
    return "/".join(relative_parts)


def _decode_fields(payload: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for encoded_field in payload.split("\x01"):
        if "\x02" not in encoded_field:
            continue
        key, value = encoded_field.split("\x02", 1)
        if key:
            fields[key] = value
    return fields


def _coverage_type(fields: Mapping[str, str]) -> str | None:
    metric = fields.get("t")
    if metric in SUPPORTED_METRICS:
        return metric
    page = fields.get("page", "")
    for candidate in SUPPORTED_METRICS:
        if page == f"v_{candidate}" or page.startswith(f"v_{candidate}/"):
            return candidate
    return None


def parse_database(path: Path, scope: Scope) -> dict[CoveragePoint, int]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        raise CoverageError(f"cannot read coverage database {path}: {exc}") from exc
    if not lines or lines[0].lstrip("\ufeff") != "# SystemC::Coverage-3":
        raise CoverageError(f"{path} is not a SystemC::Coverage-3 database")

    points: dict[CoveragePoint, int] = {}
    for line_number, record in enumerate(lines[1:], start=2):
        if not record or record.startswith("#"):
            continue
        if not record.startswith("C"):
            continue
        match = RECORD_RE.fullmatch(record)
        if match is None:
            raise CoverageError(f"{path}:{line_number}: malformed coverage record")
        fields = _decode_fields(match.group(1))
        metric = _coverage_type(fields)
        if metric is None:
            continue
        source = normalize_source_path(fields.get("f", ""), scope)
        if source is None:
            continue
        point = CoveragePoint(
            source=source,
            metric=metric,
            line=fields.get("l", ""),
            column=fields.get("n", ""),
            page=fields.get("page", ""),
            operation=fields.get("o", ""),
            span=fields.get("S", ""),
        )
        points[point] = points.get(point, 0) + int(match.group(2))
    return points


def merge_databases(paths: Iterable[Path], scope: Scope) -> dict[CoveragePoint, int]:
    merged: dict[CoveragePoint, int] = {}
    for path in paths:
        for point, count in parse_database(path, scope).items():
            merged[point] = merged.get(point, 0) + count
    return merged


def evaluate(
    points: Mapping[CoveragePoint, int], config: CoverageConfig
) -> dict[str, MetricResult]:
    results: dict[str, MetricResult] = {}
    for metric in SUPPORTED_METRICS:
        counts = [count for point, count in points.items() if point.metric == metric]
        covered = sum(count >= config.covered_min_hits for count in counts)
        total = len(counts)
        percent = (covered * 100.0 / total) if total else 0.0
        results[metric] = MetricResult(
            covered=covered,
            total=total,
            percent=percent,
            policy=config.metrics[metric],
        )
    return results


def gate_passes(results: Mapping[str, MetricResult]) -> bool:
    return all(not result.policy.blocking or result.passes for result in results.values())


def format_marker(
    status: str,
    results: Mapping[str, MetricResult],
    input_count: int,
    covered_min_hits: int,
) -> str:
    fields = [
        "CODE_COVERAGE",
        f"status={status}",
        "scope=dut/**",
        f"inputs={input_count}",
        f"covered_min_hits={covered_min_hits}",
    ]
    for metric in SUPPORTED_METRICS:
        result = results[metric]
        fields.extend(
            [
                f"{metric}_pct={result.percent:.2f}",
                f"{metric}_covered={result.covered}",
                f"{metric}_total={result.total}",
                f"{metric}_min={result.policy.minimum_percent:.2f}",
                f"{metric}_blocking={int(result.policy.blocking)}",
            ]
        )
    return " ".join(fields)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="merge Verilator coverage databases and enforce DUT thresholds"
    )
    parser.add_argument(
        "coverage_dat",
        nargs="+",
        type=Path,
        help="one or more SystemC::Coverage-3 databases",
    )
    parser.add_argument(
        "--thresholds",
        type=Path,
        default=DEFAULT_THRESHOLDS,
        help=f"threshold JSON (default: {DEFAULT_THRESHOLDS})",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        config = load_config(args.thresholds)
        points = merge_databases(args.coverage_dat, config.scope)
        results = evaluate(points, config)
    except CoverageError as exc:
        print(f"CODE_COVERAGE status=ERROR reason={json.dumps(str(exc))}")
        return 2

    passed = gate_passes(results)
    print(
        format_marker(
            "PASS" if passed else "FAIL",
            results,
            len(args.coverage_dat),
            config.covered_min_hits,
        )
    )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

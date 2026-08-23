"""Compile program images and run the UVM differential regression.

The script deliberately returns a non-zero status for build failures, simulator
failures, UVM errors, timeouts, or missing PASS markers so it can be used as a
CI gate.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IMAGE_DIR = ROOT / "csrc" / "image"
LOG_DIR = ROOT / "log"
COVERAGE_DIR = ROOT / "coverage"


@dataclass(frozen=True)
class TestResult:
    name: str
    passed: bool
    detail: str


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=ROOT, text=True, check=False)


def compile_image(cpp_file: Path) -> Path | None:
    image = IMAGE_DIR / f"{cpp_file.stem}_image.mem"
    result = run([
        "make",
        "image",
        str(cpp_file),
        f"IMAGE_TARGET={image.name}",
    ])
    return image if result.returncode == 0 and image.exists() else None


def run_test(image: Path, coverage: bool) -> tuple[int, Path]:
    log_file = LOG_DIR / f"{image.stem}.log"
    command = [
        "make",
        "run-only",
        "TEST=mem_image_test",
        f"MEM_FILE={image}",
        f"LOG={log_file}",
    ]
    if coverage:
        coverage_file = COVERAGE_DIR / f"{image.stem}.dat"
        command.extend(["COVERAGE=1", f"COVERAGE_FILE={coverage_file}"])
    result = run(command)
    return result.returncode, log_file


def build_simulator(coverage: bool) -> int:
    command = ["make", "build"]
    if coverage:
        command.append("COVERAGE=1")
    return run(command).returncode


def is_error_line(line: str) -> bool:
    stripped = line.strip()
    if re.fullmatch(r"UVM_(?:ERROR|FATAL)\s*:\s*0", stripped):
        return False
    return bool(
        re.search(r"\b(?:UVM_ERROR|UVM_FATAL)\b", line)
        or re.search(r"^\s*%Error\b", line)
        or "SIM_TIMEOUT:" in line
    )


def parse_log(log_file: Path, simulator_status: int) -> TestResult:
    if not log_file.exists():
        return TestResult(log_file.stem, False, "simulator produced no log")

    lines = log_file.read_text(errors="replace").splitlines()
    first_error = next(
        (
            f"line {line_no}: {line.strip()}"
            for line_no, line in enumerate(lines, start=1)
            if is_error_line(line)
        ),
        None,
    )
    score_line = next(
        (line.strip() for line in reversed(lines) if "PROGRAM_SCORE" in line and "PASS=" in line),
        None,
    )
    score_match = re.search(
        r"PASS=(\d+)\s+FAIL=(\d+)\s+MISSING=(\d+)\s+EXTRA=(\d+)",
        score_line or "",
    )
    score_failed = (
        score_match is None
        or int(score_match.group(1)) == 0
        or any(int(score_match.group(index)) != 0 for index in range(2, 5))
    )

    if simulator_status != 0:
        return TestResult(log_file.stem, False, first_error or f"simulator exit={simulator_status}")
    if first_error:
        return TestResult(log_file.stem, False, first_error)
    if score_failed:
        return TestResult(log_file.stem, False, score_line or "missing PROGRAM_SCORE summary")
    return TestResult(log_file.stem, True, score_line)


def discover_sources(cli_sources: list[str]) -> list[Path]:
    if cli_sources:
        sources = [Path(source).resolve() for source in cli_sources]
    else:
        sources = sorted((ROOT / "csrc").glob("*.cpp"))
    return [source for source in sources if source.suffix == ".cpp"]


def duplicate_source_stems(sources: list[Path]) -> dict[str, list[Path]]:
    """Return source stems that would collide in IMAGE_DIR.

    ``compile_image`` intentionally preserves the long-standing
    ``<stem>_image.mem`` artifact name. Rejecting ambiguous stems is safer than
    silently overwriting one program image and running another program twice.
    """

    by_stem: dict[str, list[Path]] = {}
    for source in sources:
        by_stem.setdefault(source.stem, []).append(source)
    return {
        stem: stem_sources
        for stem, stem_sources in by_stem.items()
        if len(stem_sources) > 1
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("sources", nargs="*", help="C/C++ programs to compile and run")
    parser.add_argument("--no-clean", action="store_true", help="keep the existing simulator build")
    parser.add_argument("--coverage", action="store_true", help="build with Verilator coverage")
    args = parser.parse_args()

    if not args.no_clean and run(["make", "clean"]).returncode != 0:
        print("ERROR: make clean failed", file=sys.stderr)
        return 2

    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    if args.coverage:
        COVERAGE_DIR.mkdir(parents=True, exist_ok=True)

    sources = discover_sources(args.sources)
    if not sources:
        print("ERROR: no C/C++ regression sources found", file=sys.stderr)
        return 2

    duplicate_stems = duplicate_source_stems(sources)
    if duplicate_stems:
        for stem, stem_sources in sorted(duplicate_stems.items()):
            joined_sources = ", ".join(str(source) for source in stem_sources)
            print(
                f"ERROR: duplicate regression source stem '{stem}' would "
                f"overwrite {stem}_image.mem: {joined_sources}",
                file=sys.stderr,
            )
        return 2

    images: list[Path] = []
    build_failures: list[str] = []
    for source in sources:
        image = compile_image(source)
        if image is None:
            build_failures.append(str(source))
        else:
            images.append(image)

    results: list[TestResult] = []
    if images:
        simulator_status = build_simulator(args.coverage)
        if simulator_status != 0:
            results.append(
                TestResult("simulator_build", False, f"build exit={simulator_status}")
            )
        else:
            for image in images:
                status, log_file = run_test(image, args.coverage)
                results.append(parse_log(log_file, status))

    for source in build_failures:
        results.append(TestResult(Path(source).stem, False, "image compilation failed"))

    print("\nRegression summary")
    for result in results:
        marker = "PASS" if result.passed else "FAIL"
        print(f"  [{marker}] {result.name}: {result.detail}")

    passed = sum(result.passed for result in results)
    failed = len(results) - passed
    print(f"\nPassed: {passed}  Failed: {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

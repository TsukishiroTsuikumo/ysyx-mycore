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
        f"IMAGE_TARGET={image}",
    ])
    return image if result.returncode == 0 and image.exists() else None


def run_test(image: Path, coverage: bool) -> tuple[int, Path]:
    log_file = LOG_DIR / f"{image.stem}.log"
    command = [
        "make",
        "run",
        "TEST=mem_image_test",
        f"MEM_FILE={image}",
        f"LOG={log_file}",
    ]
    if coverage:
        command.append("COVERAGE=1")
    result = run(command)
    return result.returncode, log_file


def parse_log(log_file: Path, simulator_status: int) -> TestResult:
    if not log_file.exists():
        return TestResult(log_file.stem, False, "simulator produced no log")

    lines = log_file.read_text(errors="replace").splitlines()
    first_error = next(
        (
            f"line {line_no}: {line.strip()}"
            for line_no, line in enumerate(lines, start=1)
            if re.search(r"\b(UVM_ERROR|UVM_FATAL|%Error|SIM_TIMEOUT)\b", line)
        ),
        None,
    )
    score_line = next(
        (line.strip() for line in reversed(lines) if "PROGRAM_SCORE" in line and "PASS=" in line),
        None,
    )
    score_failed = score_line is None or not re.search(r"FAIL=0\s+MISSING=0\s+EXTRA=0", score_line)

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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("sources", nargs="*", help="C/C++ programs to compile and run")
    parser.add_argument("--no-clean", action="store_true", help="keep the existing simulator build")
    parser.add_argument("--coverage", action="store_true", help="build with Verilator coverage")
    args = parser.parse_args()

    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    if not args.no_clean and run(["make", "clean"]).returncode != 0:
        print("ERROR: make clean failed", file=sys.stderr)
        return 2

    sources = discover_sources(args.sources)
    if not sources:
        print("ERROR: no C/C++ regression sources found", file=sys.stderr)
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

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from scripts.check_coverage import (
    CoveragePoint,
    Scope,
    main,
    merge_databases,
    normalize_source_path,
)


SOH = "\x01"
STX = "\x02"


def record(
    source: str,
    metric: str,
    line: int,
    count: int,
    operation: str = "point",
) -> str:
    fields = {
        "f": source,
        "l": str(line),
        "n": "1",
        "t": metric,
        "page": f"v_{metric}/unit",
        "o": operation,
        "h": "test_bench.dut",
    }
    payload = "".join(f"{SOH}{key}{STX}{value}" for key, value in fields.items()) + SOH
    return f"C '{payload}' {count}\n"


class CoverageGateTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def write_config(self, line: float = 75.0, toggle: float = 35.0) -> Path:
        path = self.root / "thresholds.json"
        path.write_text(
            json.dumps(
                {
                    "covered_min_hits": 1,
                    "scope": {
                        "source_root": "dut",
                        "excluded_path_parts": ["obj_dir", "test_bench"],
                    },
                    "metrics": {
                        "line": {"minimum_percent": line, "blocking": True},
                        "toggle": {"minimum_percent": toggle, "blocking": True},
                        "branch": {"minimum_percent": 0.0, "blocking": False},
                    },
                }
            ),
            encoding="utf-8",
        )
        return path

    def write_database(self, name: str, records: list[str]) -> Path:
        path = self.root / name
        path.write_text("# SystemC::Coverage-3\n" + "".join(records), encoding="utf-8")
        return path

    def run_gate(self, database: Path, config: Path) -> tuple[int, str]:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = main(["--thresholds", str(config), str(database)])
        return status, output.getvalue().strip()

    def test_passing_thresholds_emit_machine_readable_marker(self):
        database = self.write_database(
            "passing.dat",
            [
                record("dut/core.v", "line", 10, 1),
                record("dut/core.v", "line", 11, 1),
                record("dut/core.v", "line", 12, 1),
                record("dut/core.v", "line", 13, 0),
                record("dut/core.v", "toggle", 20, 1, "a:0->1"),
                record("dut/core.v", "toggle", 20, 0, "a:1->0"),
            ],
        )
        status, output = self.run_gate(database, self.write_config())
        self.assertEqual(status, 0)
        self.assertIn("CODE_COVERAGE status=PASS", output)
        self.assertIn("line_pct=75.00", output)
        self.assertIn("toggle_pct=50.00", output)
        self.assertIn("branch_blocking=0", output)

    def test_blocking_metric_below_threshold_fails(self):
        database = self.write_database(
            "failing.dat",
            [
                record("dut/core.v", "line", 10, 1),
                record("dut/core.v", "line", 11, 0),
                record("dut/core.v", "toggle", 20, 1, "a:0->1"),
                record("dut/core.v", "toggle", 20, 1, "a:1->0"),
            ],
        )
        status, output = self.run_gate(database, self.write_config())
        self.assertEqual(status, 1)
        self.assertIn("CODE_COVERAGE status=FAIL", output)
        self.assertIn("line_pct=50.00", output)

    def test_path_normalization_keeps_only_dut_sources(self):
        scope = Scope("dut", frozenset({"obj_dir", "test_bench"}))
        self.assertEqual(
            normalize_source_path(
                "/__w/ysyx-mycore/ysyx-mycore/dut/mycore/core.v", scope
            ),
            "dut/mycore/core.v",
        )
        self.assertEqual(
            normalize_source_path(r"C:\work\ysyx-mycore\dut\mem\cache.v", scope),
            "dut/mem/cache.v",
        )
        self.assertEqual(
            normalize_source_path("./rtl/../dut/axi/adapter.v", scope),
            "dut/axi/adapter.v",
        )
        self.assertIsNone(normalize_source_path("test_bench/tb.sv", scope))
        self.assertIsNone(normalize_source_path("some_dut/core.v", scope))
        self.assertIsNone(normalize_source_path("obj_dir/dut/generated.v", scope))
        self.assertIsNone(normalize_source_path("test_bench/dut/fake.sv", scope))

    def test_multiple_inputs_merge_the_same_normalized_points(self):
        first = self.write_database(
            "first.dat",
            [
                record("dut/core.v", "line", 10, 0),
                record("dut/core.v", "line", 11, 1),
                record("test_bench/tb.sv", "line", 1, 1),
            ],
        )
        second = self.write_database(
            "second.dat",
            [
                record("/__w/repo/repo/dut/core.v", "line", 10, 3),
                record("/__w/repo/repo/dut/core.v", "line", 11, 0),
            ],
        )
        scope = Scope("dut", frozenset({"obj_dir", "test_bench"}))
        merged = merge_databases([first, second], scope)
        line_points = {
            point: count for point, count in merged.items() if point.metric == "line"
        }
        self.assertEqual(len(line_points), 2)
        self.assertEqual(
            line_points[
                CoveragePoint(
                    "dut/core.v", "line", "10", "1", "v_line/unit", "point", ""
                )
            ],
            3,
        )
        self.assertEqual(sum(count > 0 for count in line_points.values()), 2)


if __name__ == "__main__":
    unittest.main()

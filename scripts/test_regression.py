import tempfile
import unittest
from pathlib import Path

from scripts.regression import duplicate_source_stems, is_error_line, parse_log


class RegressionLogTests(unittest.TestCase):
    def parse(self, contents: str, status: int = 0):
        with tempfile.TemporaryDirectory() as temp_dir:
            log_file = Path(temp_dir) / "test.log"
            log_file.write_text(contents)
            return parse_log(log_file, status)

    def test_zero_severity_summary_is_not_an_error(self):
        result = self.parse(
            "PROGRAM_SCORE PASS=12 FAIL=0 MISSING=0 EXTRA=0\n"
            "UVM_ERROR : 0\n"
            "UVM_FATAL : 0\n"
        )
        self.assertTrue(result.passed)

    def test_real_uvm_error_fails(self):
        result = self.parse(
            "UVM_ERROR test.svh(1) @ 10: mismatch\n"
            "PROGRAM_SCORE PASS=12 FAIL=0 MISSING=0 EXTRA=0\n"
        )
        self.assertFalse(result.passed)

    def test_zero_pass_count_fails(self):
        result = self.parse("PROGRAM_SCORE PASS=0 FAIL=0 MISSING=0 EXTRA=0\n")
        self.assertFalse(result.passed)

    def test_nonzero_simulator_status_fails(self):
        result = self.parse(
            "PROGRAM_SCORE PASS=12 FAIL=0 MISSING=0 EXTRA=0\n", status=7
        )
        self.assertFalse(result.passed)

    def test_error_line_filter(self):
        self.assertFalse(is_error_line("UVM_ERROR : 0"))
        self.assertTrue(is_error_line("UVM_FATAL : 1"))
        self.assertTrue(is_error_line("%Error: simulation aborted"))
        self.assertTrue(is_error_line("SIM_TIMEOUT: exceeded limit"))

    def test_duplicate_source_stems_are_rejected_before_compilation(self):
        duplicates = duplicate_source_stems([
            Path("tests/a/main.cpp"),
            Path("tests/b/main.cpp"),
            Path("tests/unique.cpp"),
        ])
        self.assertEqual(set(duplicates), {"main"})
        self.assertEqual(len(duplicates["main"]), 2)

    def test_unique_source_stems_have_no_image_collision(self):
        self.assertEqual(
            duplicate_source_stems([
                Path("tests/add.cpp"),
                Path("tests/sub.cpp"),
            ]),
            {},
        )


if __name__ == "__main__":
    unittest.main()

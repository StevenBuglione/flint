"""Exercise the constants-only Java enum slice using the native helper."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_annotations import HELPER


class EnumTests(unittest.TestCase):
    def translate(self, declaration):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "SpringMode.java"
            path.write_text("package org.springframework.demo;\n" + declaration, encoding="utf-8")
            return subprocess.run([HELPER, path], capture_output=True, check=False)

    def test_constants_keep_ordinal_and_apply_name_rules(self):
        result = self.translate("public enum SpringMode { FAST, SLOW, version; }")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        value = json.loads(result.stdout)
        self.assertEqual(value["kind"], "enum")
        self.assertEqual(value["symbol"], "FlintMode")
        self.assertEqual(value["members"][-1], {"name": "version", "symbol": "version_"})
        probe = """module flint.demo;
@safe:
""" + value["body"] + """
static assert(cast(int) FlintMode.FAST == 0);
static assert(cast(int) FlintMode.SLOW == 1);
static assert(cast(int) FlintMode.version_ == 2);
"""
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "demo.d"
            path.write_text(probe, encoding="utf-8")
            for compiler in ("dmd", "ldc2"):
                subprocess.run([compiler, "-preview=dip1000", "-o-", "-c", path],
                               cwd=scratch, check=True)

    def test_other_enum_rules_do_not_produce_a_partial_candidate(self):
        for java in (
            "public enum SpringMode implements Runnable { FAST; public void run() {} }",
            "public enum SpringMode { FAST; public int number() { return 5; } }",
            "public enum SpringMode { FAST(1); SpringMode(int code) {} }",
            "public enum SpringMode { FAST {}; }",
            "public enum SpringMode {}",
        ):
            with self.subTest(java=java):
                result = self.translate(java)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, b"")
                self.assertIn(b"unsupported enum", result.stderr)


if __name__ == "__main__":
    unittest.main()

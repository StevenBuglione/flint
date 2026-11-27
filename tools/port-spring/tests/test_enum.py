"""Exercise ordinal preservation and checked enum method lowering with the native helper."""

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

    ORDINAL_CAP = """import org.springframework.util.Assert;
public enum SpringMode {
    FAST, SLOW;
    public SpringMode cap(SpringMode maxPermitted) {
        Assert.notNull(maxPermitted, "'maxPermitted' must not be null");
        return (ordinal() <= maxPermitted.ordinal()) ? this : maxPermitted;
    }
}
"""

    def test_ordinal_cap_emits_safe_ufcs_and_rejects_null(self):
        result = self.translate(self.ORDINAL_CAP)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        value = json.loads(result.stdout)
        self.assertEqual(value["members"], [
            {"name": "FAST", "symbol": "FAST"},
            {"name": "SLOW", "symbol": "SLOW"},
            {"name": "cap", "symbol": "cap", "enumParameter": "maxPermitted"},
        ])
        self.assertIn("FlintMode cap(FlintMode flintMode, FlintMode maxPermitted) pure nothrow @nogc", value["body"])
        self.assertIn("return flintMode <= maxPermitted ? flintMode : maxPermitted;", value["body"])
        self.assertNotIn("typeof(null)", value["body"])
        self.assertNotIn("IllegalArgumentException", value["body"])
        probe = "module flint.demo;\n@safe:\n" + value["body"] + """
static assert(FlintMode.SLOW.cap(FlintMode.FAST) == FlintMode.FAST);
static assert(!__traits(compiles, FlintMode.FAST.cap(null)));
"""
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "demo.d"
            path.write_text(probe, encoding="utf-8")
            for compiler in ("dmd", "ldc2"):
                subprocess.run([compiler, "-preview=dip1000", "-o-", "-c", path], cwd=scratch, check=True)

    def test_ordinal_cap_receiver_avoids_keywords_and_the_parameter(self):
        scope = self.ORDINAL_CAP.replace("SpringMode", "Scope")
        result = self.translate(scope)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertIn("Scope cap(Scope scope_, Scope maxPermitted)", json.loads(result.stdout)["body"])
        clash = self.ORDINAL_CAP.replace("SpringMode", "MaxPermitted")
        result = self.translate(clash)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertIn("MaxPermitted cap(MaxPermitted receiver, MaxPermitted maxPermitted)",
                      json.loads(result.stdout)["body"])

    def test_enum_method_requires_checked_ordinal_behavior(self):
        for declaration in (
            self.ORDINAL_CAP.replace("org.springframework.util.Assert", "example.Assert"),
            self.ORDINAL_CAP.replace(" ? this : maxPermitted", " ? maxPermitted : this"),
            self.ORDINAL_CAP.replace(" <= ", " >= "),
            self.ORDINAL_CAP.replace('Assert.notNull(maxPermitted, "\'maxPermitted\' must not be null");', ""),
            self.ORDINAL_CAP.replace("FAST, SLOW;", "FAST, SLOW; private int rank;"),
            self.ORDINAL_CAP.replace("public SpringMode cap", "public static SpringMode cap"),
        ):
            with self.subTest(declaration=declaration):
                result = self.translate(declaration)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(result.stdout)
                self.assertIn(b"unsupported enum", result.stderr)

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

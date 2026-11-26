"""Check the native proof of a final class with literal static string fields."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_annotations import HELPER


SOURCE = """package org.springframework.ai.model;
public final class SpringAIModels {
    private SpringAIModels() { /* no instances */ }
    public static final String OPENAI = "openai";
    static final public java.lang.String ON_PREM = "on-prem";
}
"""


class HolderTests(unittest.TestCase):
    def translate(self, source):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "SpringAIModels.java"
            path.write_text(source, encoding="utf-8")
            return subprocess.run([HELPER, path], capture_output=True, check=False)

    def test_proves_static_fields_and_preserves_literals_and_order(self):
        result = self.translate(SOURCE)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        candidate = json.loads(result.stdout)
        self.assertEqual(candidate["kind"], "class")
        self.assertEqual(candidate["symbol"], "FlintAIModels")
        self.assertTrue(candidate["staticHolder"])
        self.assertTrue(candidate["implicitString"])
        self.assertEqual(candidate["members"], [
            {"name": "OPENAI", "symbol": "OPENAI", "stringType": "String", "literal": '"openai"'},
            {"name": "ON_PREM", "symbol": "ON_PREM", "stringType": "java.lang.String", "literal": '"on-prem"'},
        ])

    def test_rejects_state_behavior_and_nonliteral_fields(self):
        for source in (
            SOURCE.replace("private", "public"),
            SOURCE.replace("    private SpringAIModels() { /* no instances */ }\n", ""),
            SOURCE.replace("/* no instances */", "recordCreation();"),
            SOURCE.replace("private SpringAIModels()", "private SpringAIModels(String name)"),
            SOURCE.replace("    public static final", "    private static final"),
            SOURCE.replace("    public static final", "    public final"),
            SOURCE.replace("    public static final", "    public static"),
            SOURCE.replace('"openai";', 'null;'),
            SOURCE.replace('"openai";', '"open" + "ai";'),
            SOURCE.replace('"openai";', '"spring.ai.model";'),
            SOURCE.replace('"openai";', '"openai", OTHER = "other";'),
            SOURCE.replace('String OPENAI', 'String OPENAI[]'),
            SOURCE.replace('"openai";', '"openai"; static { register(); }'),
            SOURCE.replace("public final class", "@Deprecated public final class"),
            SOURCE.replace("public final class", "import example.String; public final class"),
        ):
            with self.subTest(source=source):
                result = self.translate(source)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(result.stdout)
                self.assertIn(b"unsupported constant holder", result.stderr)


if __name__ == "__main__":
    unittest.main()

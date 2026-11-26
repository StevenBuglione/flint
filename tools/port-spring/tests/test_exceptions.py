"""Exercise the native proof for a message-forwarding exception constructor."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_annotations import HELPER


SOURCE = """package org.springframework.transaction;
@SuppressWarnings("serial")
public class InvalidIsolationLevelException extends TransactionUsageException {
    public InvalidIsolationLevelException(String msg) {
        super(msg);
    }
}
"""


class ExceptionTests(unittest.TestCase):
    def translate(self, source):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "InvalidIsolationLevelException.java"
            path.write_text(source, encoding="utf-8")
            return subprocess.run([HELPER, path], capture_output=True, check=False)

    def test_records_the_superclass_and_exact_forwarded_constructor(self):
        result = self.translate(SOURCE)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        candidate = json.loads(result.stdout)
        self.assertEqual(candidate["kind"], "class")
        self.assertEqual(candidate["exception"], {
            "base": "TransactionUsageException", "parameter": "msg", "parameterType": "String",
            "implicitString": True, "implicitSuppressWarnings": True,
        })
        self.assertEqual(candidate["members"], [{"name": "<init>", "symbol": "this"}])
        self.assertNotIn("body", candidate)

    def test_rejects_constructors_that_do_more_than_forward_a_string(self):
        for source in (
            SOURCE.replace("super(msg);", 'super("fixed");'),
            SOURCE.replace("super(msg);", "this(msg);"),
            SOURCE.replace("super(msg);", "super(msg); log(msg);"),
            SOURCE.replace("String msg", "Throwable msg"),
            SOURCE.replace("String msg", "java.lang.String[] msg"),
            SOURCE.replace("public InvalidIsolationLevelException(", "protected InvalidIsolationLevelException("),
            SOURCE.replace("extends TransactionUsageException {",
                           "extends TransactionUsageException implements Runnable {"),
            SOURCE.replace("super(msg);\n    }", "super(msg);\n    }\n    private int field;"),
            SOURCE.replace('SuppressWarnings("serial")', 'SuppressWarnings("unchecked")'),
        ):
            with self.subTest(source=source):
                result = self.translate(source)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(result.stdout)
                self.assertIn(b"unsupported exception", result.stderr)


if __name__ == "__main__":
    unittest.main()

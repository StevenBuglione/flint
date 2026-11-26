"""Check the native proof for an empty interface with a single parent."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_annotations import HELPER


class InterfaceTests(unittest.TestCase):
    def translate(self, declaration):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "PriorityOrdered.java"
            path.write_text("package org.springframework.core;\n" + declaration, encoding="utf-8")
            return subprocess.run([HELPER, path], capture_output=True, check=False)

    def test_defers_parent_resolution_to_the_cli(self):
        for parent in ("Ordered", "org.springframework.core.Ordered"):
            with self.subTest(parent=parent):
                result = self.translate(f"public interface PriorityOrdered extends {parent} {{ /* marker */ }}")
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                candidate = json.loads(result.stdout)
                self.assertEqual(candidate["kind"], "interface")
                self.assertEqual(candidate["interfaceParent"], parent)
                self.assertEqual(candidate["members"], [])
                self.assertNotIn("body", candidate)

    def test_rejects_declarations_that_need_other_r3_or_r16_rules(self):
        for declaration in (
            "import static example.Outer.Ordered; public interface PriorityOrdered extends Ordered {}",
            "import static example.Outer.*; public interface PriorityOrdered extends Ordered {}",
            "public interface PriorityOrdered {}",
            "public interface PriorityOrdered extends Ordered, Other {}",
            "public interface PriorityOrdered extends Ordered<String> {}",
            "public interface PriorityOrdered<T> extends Ordered {}",
            "public sealed interface PriorityOrdered extends Ordered permits Bean {}",
            "@Deprecated public interface PriorityOrdered extends Ordered {}",
            "public interface PriorityOrdered extends Ordered { int getOrder(); }",
            "public interface PriorityOrdered extends Ordered { default int getOrder() { return 0; } }",
            "public interface PriorityOrdered extends Ordered { static int getOrder() { return 0; } }",
            "public interface PriorityOrdered extends Ordered { int LOW = 0; }",
            "public interface PriorityOrdered extends Ordered { interface Nested {} }",
        ):
            with self.subTest(declaration=declaration):
                result = self.translate(declaration)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(result.stdout)
                self.assertIn(b"unsupported marker interface", result.stderr)


if __name__ == "__main__":
    unittest.main()

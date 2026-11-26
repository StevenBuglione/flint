"""Compile the native translator's unmodified output on both D compilers."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(os.environ.get("FLINT_PORT_SPRING_HELPER", ".flint/port-spring/flint-port-spring")).resolve()
ROOT = Path(__file__).resolve().parents[3]


class AnnotationTests(unittest.TestCase):
    def run_helper(self, source):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "Settings.java"
            path.write_text(source, encoding="utf-8")
            return subprocess.run([HELPER, path], capture_output=True, check=False)

    def test_value_first_and_defaults(self):
        source = """package org.springframework.demo;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;
import static java.lang.annotation.RetentionPolicy.RUNTIME;
import static java.lang.annotation.ElementType.TYPE;

@Retention(RUNTIME)
@Target(TYPE)
public @interface Settings {
    boolean enabled() default true;
    String value() default "café \\"quoted\\"";
    String[] names() default {"first", "second"};
    int version() default -3;
    long limit() default 4000000000L;
    String[] single() default "one";
    String[] empty() default {};
}
"""
        first = self.run_helper(source)
        self.assertEqual(first.returncode, 0, first.stderr.decode())
        self.assertEqual(first.stdout, self.run_helper(source).stdout)
        result = json.loads(first.stdout)
        self.assertEqual((result["package"], result["name"]), ("org.springframework.demo", "Settings"))
        self.assertEqual(result["fields"][0], {"name": "value", "symbol": "value"})
        self.assertIn({"name": "version", "symbol": "version_"}, result["fields"])
        probe = """module flint.demo;
@safe:
""" + result["body"] + """
@Settings("custom") struct Example {}
static assert(Settings.init.value == "café \\"quoted\\"");
static assert(Settings.init.enabled);
static assert(Settings.init.names == ["first", "second"]);
static assert(Settings.init.version_ == -3);
static assert(Settings.init.limit == 4_000_000_000L);
static assert(Settings.init.single == ["one"]);
static assert(Settings.init.empty.length == 0);
static assert(__traits(getAttributes, Example)[0].value == "custom");
"""
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "demo.d"
            path.write_text(probe, encoding="utf-8")
            for compiler in ("dmd", "ldc2"):
                with self.subTest(compiler=compiler):
                    subprocess.run(
                        [compiler, "-preview=dip1000", "-o-", "-c", path],
                        cwd=scratch,
                        check=True,
                    )

    def test_unsupported_default_yields_no_candidate(self):
        result = self.run_helper(
            "package example; public @interface Settings { int value() default 2 + 3; }"
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"unsupported annotation default", result.stderr)

    def test_integral_defaults_preserve_java_width_and_negation(self):
        result = self.run_helper("""package example;
public @interface Settings {
    int hex() default 0xffff_ffff;
    long widened() default -0x8000_0000;
    long wide() default 0xffffffffL;
    long minimum() default -0x8000_0000_0000_0000L;
    short octal() default 01_234;
    byte binary() default -0b1000_0000;
    byte narrowed() default 0xffff_ffff;
    int[] array() default { 0b101, -0XFFFF_FFFF, 077 };
}
""")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        probe = "module flint.demo;\n@safe:\n" + json.loads(result.stdout)["body"] + """
static assert(Settings.init.hex == -1);
static assert(Settings.init.widened == int.min);
static assert(Settings.init.wide == 4_294_967_295L);
static assert(Settings.init.minimum == long.min);
static assert(Settings.init.octal == 668);
static assert(Settings.init.binary == byte.min);
static assert(Settings.init.narrowed == -1);
static assert(Settings.init.array == [5, 1, 63]);
"""
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "demo.d"
            path.write_text(probe, encoding="utf-8")
            for compiler in ("dmd", "ldc2"):
                subprocess.run([compiler, "-preview=dip1000", "-o-", "-c", path],
                               cwd=scratch, check=True)

    def test_integral_defaults_reject_overflow_and_invalid_narrowing(self):
        for declaration in ("long value() default 0x1_0000_0000;",
                            "long value() default 0x1_0000_0000_0000_0000L;",
                            "byte value() default 0xff;",
                            "byte value() default 1L;"):
            with self.subTest(declaration=declaration):
                result = self.run_helper(
                    "package example; public @interface Settings { " + declaration + " }"
                )
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, b"")
                self.assertIn(b"unsupported annotation default", result.stderr)

    def test_class_tokens_use_the_leaf_classref_and_void_is_empty(self):
        result = self.run_helper("""package example;
public @interface Settings {
    Class<? extends Number>[] types() default {};
    Class<?> value() default void.class;
}""")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        candidate = json.loads(result.stdout)
        self.assertTrue(candidate["classRef"])
        probe = """module flint.demo;
import flint.java.classref : ClassRef;
@safe:
""" + candidate["body"] + """
static assert(Settings.init.value == ClassRef.init);
static assert(Settings.init.types.length == 0);
@Settings(ClassRef("flint.Foo")) struct Example {}
static assert(__traits(getAttributes, Example)[0].value.name == "flint.Foo");
"""
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "demo.d"
            path.write_text(probe, encoding="utf-8")
            for compiler in ("dmd", "ldc2"):
                subprocess.run(
                    [compiler, "-preview=dip1000", "-o-", "-c",
                     "-I" + str(ROOT / "framework/java/source"), path],
                    cwd=scratch,
                    check=True,
                )

    def test_custom_meta_annotation_is_never_dropped(self):
        result = self.run_helper(
            "package example; import example.metadata.Target; @Target public @interface Settings {}"
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"unsupported meta-annotation", result.stderr)

    def test_ambiguous_implicit_string_type_is_rejected(self):
        result = self.run_helper(
            "package example; import example.types.*; public @interface Settings { String value(); }"
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"unsupported annotation type", result.stderr)

    def test_malformed_java_yields_no_candidate(self):
        result = self.run_helper("package example; public @interface Settings { int value() default ; }")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"Java syntax error", result.stderr)

    def test_package_without_an_annotation_yields_no_candidate(self):
        result = self.run_helper("package example;")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"one public annotation", result.stderr)


if __name__ == "__main__":
    unittest.main()

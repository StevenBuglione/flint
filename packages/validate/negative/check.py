#!/usr/bin/env python3
"""Compile incompatible validation descriptors with DMD or LDC and require the field-local rejection."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PRELUDE = ("module fixture;\nimport flint.arena : Text;\n"
           "import flint.validate : Email, Max, Min, NotBlank, Pattern, Size, Valid, validate;\n"
           "struct Inner { @NotBlank string label; }\n")
CALL = "\nvoid check() @safe nothrow @nogc { Subject subject; cast(void) validate(subject, []); }\n"
CASES = (
    ("NotBlank on an integer", "struct Subject { @NotBlank uint count; }", "count: NotBlank requires UTF-8 text"),
    ("Min on a struct", "struct Subject { @Min(0) Inner label; }", "label: Min requires a numeric field"),
    ("Max on a string", "struct Subject { @Max(3) string label; }", "label: Max requires a numeric field"),
    ("inverted Min and Max", "struct Subject { @Min(9) @Max(5) int index; }",
     "index: contradictory Min and Max constraints"),
    ("contradictory duplicate Size", "struct Subject { @Size(5, 10) @Size(1, 4) string label; }",
     "label: contradictory Size constraints"),
    ("inverted Size interval", "struct Subject { @Size(4, 1) string label; }",
     "label: contradictory Size constraints"),
    ("Size on an integer", "struct Subject { @Size(1, 2) int count; }",
     "count: Size requires an array or UTF-8 text"),
    ("Pattern on bytes", "struct Subject { @Pattern(\"a\") ubyte[] bytes; }", "bytes: Pattern requires UTF-8 text"),
    ("Email on bytes", "struct Subject { @Email ubyte[] bytes; }", "bytes: Email requires UTF-8 text"),
    ("Min without arguments", "struct Subject { @Min int count; }", "count: constraint requires explicit arguments"),
    ("Valid on a scalar", "struct Subject { @Valid int count; }",
     "count: Valid requires a struct or an array of structs"),
    ("direct recursive descriptor", "struct Subject { @Valid Subject[] children; }",
     "recursive validation at children[].Subject"),
    ("mutual recursive descriptor",
     "struct Subject { @Valid Other[] others; }\nstruct Other { @Valid Subject[] subjects; }",
     "recursive validation at others[].subjects[].Subject"),
    ("nine collection index levels", "struct Subject { @Valid Inner[][][][][][][][][] deep; }",
     "array validation exceeds eight index levels at deep[][][][][][][][]"),
    ("backreference", "struct Subject { @Pattern(r\"(a)\\1\") string text; }",
     "text: backreferences and numeric escapes are unsupported"),
    ("look-ahead", "struct Subject { @Pattern(r\"(?=a)a\") string text; }",
     "text: look-around and extended groups are unsupported"),
    ("look-behind", "struct Subject { @Pattern(r\"(?<!a)b\") string text; }",
     "text: look-around and extended groups are unsupported"),
    ("Unicode property escape", "struct Subject { @Pattern(r\"\\p{L}\") string text; }",
     "text: unsupported pattern escape"),
    ("257 NFA states", "struct Subject { @Pattern(r\"a{256}\") string text; }",
     "text: pattern exceeds 256 NFA states"),
    ("nested quantifiers beyond 256 states", "struct Subject { @Pattern(r\"(a{16}){16}\") string text; }",
     "text: pattern exceeds 256 NFA states"),
    ("non-ASCII pattern literal", "struct Subject { @Pattern(\"\u00e9\") string text; }",
     "text: pattern literals must use ASCII"),
)
POSITIVE = ("struct Row { @Size(1, 4) @NotBlank Text label; @Min(0) @Max(9) ubyte score; }\n"
            "struct Subject { @Valid Row[][8] rows; @Email string mail; @Pattern(r\"(a{15}){17}\") string text;"
            " @Size(1, 2) wstring wide; }")


def compile_fixture(compiler, directory, body):
    fixture = Path(directory) / "fixture.d"
    fixture.write_text(PRELUDE + body + CALL)
    imports = ["-I" + str(ROOT / "packages" / name / "source") for name in ("arena", "validate")]
    result = subprocess.run([compiler, "-c", "-o-", "-preview=dip1000", *imports, str(fixture)],
                            text=True, capture_output=True, timeout=120)
    return result.returncode, result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="flint-validate-negative-") as temp:
        for name, body, diagnostic in CASES:
            code, output = compile_fixture(args.compiler, temp, body)
            assert 0 < code < 128, (name, code, output)
            assert re.search(r"static assert:\s+\"" + re.escape(diagnostic) + "\"", output), (name, output)
            assert not re.search(r"(?i)internal compiler error|segmentation fault", output), (name, output)
            print(name + " rejected")
        code, output = compile_fixture(args.compiler, temp, POSITIVE)
        assert code == 0, ("positive control", output)
        print("positive control compiled")


if __name__ == "__main__":
    main()

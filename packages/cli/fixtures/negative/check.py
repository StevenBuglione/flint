#!/usr/bin/env python3
"""CLI-03: compile each duplicate-binding fixture and require its field-qualified diagnostic."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
CASES = (
    ("duplicate_long.d", "duplicate-long.second: duplicate long option",
     ('@Option("first", \'b\', "") int second;', '@Option("second", \'b\', "") int second;')),
    ("duplicate_short.d", "duplicate-short.second: duplicate short alias",
     ('@Option("second", \'a\', "") int second;', '@Option("second", \'b\', "") int second;')),
    ("duplicate_positional.d", "duplicate-positional.second: duplicate positional index",
     ('@Arg(0, "") int second;', '@Arg(1, "") int second;')),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler")
    args = parser.parse_args()
    imports = ["-I" + str(ROOT / "packages" / name / "source") for name in ("arena", "validate", "cli")]
    compile_only = [args.compiler, "-c", "-o-", "-preview=dip1000", *imports]
    for filename, diagnostic, (old, new) in CASES:
        result = subprocess.run([*compile_only, str(HERE / filename)], capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        assert 0 < result.returncode < 128 and diagnostic in output, (filename, result.returncode, output)
        assert "internal compiler error" not in output.lower(), (filename, output)
        print(f"{filename} rejected: {diagnostic}")
        # Positive control: removing only the duplicate binding must compile.
        source = (HERE / filename).read_text()
        assert old in source, (filename, old)
        with tempfile.TemporaryDirectory(prefix="flint-cli-negative-control-") as temp:
            control = Path(temp) / filename
            control.write_text(source.replace(old, new))
            accepted = subprocess.run([*compile_only, str(control)], capture_output=True, text=True, timeout=60)
            assert accepted.returncode == 0, (filename, accepted.stdout + accepted.stderr)
        print(f"{filename} repaired control compiles")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check stable SQL descriptor diagnostics using both pinned D compilers."""

import argparse
from pathlib import Path
import subprocess

ENTITY = {
    "MissingId": "exactly one Id",
    "MissingTable": "exactly one Table",
    "DuplicateId": "duplicate Id field",
    "DuplicateColumn": "duplicate SQL column",
    "Pointer": "unsupported SQL field type",
    "Class": "unsupported SQL field type",
    "Delegate": "unsupported SQL field type",
    "InvalidTable": "invalid SQL table identifier",
    "InvalidColumn": "invalid or duplicate SQL column identifier",
    "DuplicateVersion": "duplicate Version field",
    "WrongKey": "identifier type must match",
}

QUERY = {
    "UnknownParameter": "unknown SQL parameter",
    "UnusedParameter": "mapped parameter is unused",
    "DuplicateParameter": "duplicate SQL column",
    "BoundMarker": "use named :parameter placeholders",
    "MultipleStatements": "must contain one statement",
    "UnterminatedLiteral": "unterminated SQL quote",
}

IMPORTS = ("arena", "conc", "data", "reactor", "serde", "sql", "validate")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent
    root = fixtures.parents[3]
    for compiler, flag in (("dmd", "-version="), ("ldc2", "-d-version=")):
        for module, cases in (("entity", ENTITY), ("query", QUERY)):
            for name, diagnostic in cases.items():
                command = [compiler, "-preview=dip1000", "-c", "-o-", flag + "FlintData" + name,
                           *("-Ipackages/" + dep + "/source" for dep in IMPORTS), str(fixtures / (module + ".d"))]
                result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=15)
                output = result.stdout + result.stderr
                (args.output / f"{compiler}-{name}.log").write_text(output)
                if result.returncode != 1 or diagnostic not in output:
                    raise SystemExit(f"{compiler} {name} did not fail with {diagnostic!r}\n{output}")
                print(f"{compiler} {name}: {diagnostic}")


if __name__ == "__main__":
    main()

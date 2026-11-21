#!/usr/bin/env python3
"""Generate explicit repository registrations for the bounded compiler fixture."""

import argparse
from pathlib import Path


def generate(count):
    yield "module scale_probe;\n"
    yield "import flint.data : Id, SqlRepository, Table;"
    yield "import flint.sql : Pool;\n"
    yield "@safe:\n"
    for index in range(count):
        name = f"Entity{index:03}"
        yield f'@Table("record_{index:03}")'
        yield f"private struct {name}"
        yield "{"
        yield "    @Id long id;"
        yield "    long payload;"
        yield "}\n"
        yield f"private alias Repo{index:03} = SqlRepository!({name}, long);\n"
    yield "/// Register every generated repository through its normal constructor."
    yield "void construct(ref Pool pool)"
    yield "{"
    for index in range(count):
        yield f"    new Repo{index:03}(pool);"
    yield "}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("count", type=int, choices=(1, 10, 100))
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text("\n".join(generate(args.count)) + "\n")


if __name__ == "__main__":
    main()

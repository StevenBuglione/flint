#!/usr/bin/env python3
"""compile_bench: compile the generated 1-, 10- and 100-entity repository fixtures and check the caps.

Each fixture is compiled to an object file by both pinned compilers with template-instance listing.
The instance count is the sum of the compiler's `vtemplate: N (M distinct) instantiation(s)` lines;
peak compiler RSS is the kernel's maximum resident set of the compiler process. The 100-entity
fixture must stay within the data manifest caps in policy/packages.json.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from generate import generate

IMPORTS = ("arena", "conc", "data", "log", "reactor", "serde", "sql", "validate")
FLAGS = {"dmd": ["-vtemplates=list-instances"], "ldc2": ["--vtemplates=list-instances"]}


def instances(text):
    return sum(int(n) for n in re.findall(r"vtemplate:\s+(\d+)\s+\(\d+\s+distinct\)\s+instantiation\(s\)", text))


def compile_fixture(compiler, source, output, root):
    command = [compiler, "-preview=dip1000", "-c", "-of=" + str(output.with_suffix(".o")), *FLAGS[compiler],
               *("-I" + str(root / "packages" / dep / "source") for dep in IMPORTS), str(source)]
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
        log = process.stdout.read()
        # wait4 reports this compiler process's own peak resident set in KiB.
        _, status, usage = os.wait4(process.pid, 0)
        process.returncode = os.waitstatus_to_exitcode(status)
    output.with_suffix(".log").write_text(log)
    if process.returncode != 0:
        raise SystemExit(f"{compiler} failed on {source.name}\n{log[-4000:]}")
    return instances(log), usage.ru_maxrss * 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[4]
    budget = json.loads((root / "policy/packages.json").read_text())["packages"]["data"]["budget"]
    rows = []
    for compiler in ("dmd", "ldc2"):
        for count in (1, 10, 100):
            source = args.output / f"scale_probe_{count}.d"
            source.write_text("\n".join(generate(count)) + "\n")
            templates, rss = compile_fixture(compiler, source, args.output / f"{compiler}-{count}", root)
            rows.append({"compiler": compiler, "entities": count, "template_instances": templates,
                         "compiler_peak_rss_bytes": rss})
            print(json.dumps(rows[-1]), flush=True)
    for row in rows:
        if row["entities"] != 100:
            continue
        if row["template_instances"] > budget["template_instances"]:
            raise SystemExit(f"{row['compiler']}: 100 entities exceed the template cap {budget['template_instances']}")
        if row["compiler_peak_rss_bytes"] > budget["compiler_peak_rss_bytes"]:
            raise SystemExit(f"{row['compiler']}: 100 entities exceed the RSS cap {budget['compiler_peak_rss_bytes']}")
    ordered = [row["template_instances"] for row in rows if row["compiler"] == "dmd"]
    if not ordered[0] <= ordered[1] <= ordered[2]:
        raise SystemExit("template instances do not grow monotonically with the entity count")
    print("compile_bench: 100-entity fixture within template and RSS caps")


if __name__ == "__main__":
    main()

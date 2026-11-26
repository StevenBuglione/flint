#!/usr/bin/env python3
"""Link the generated-shape mapping fixture on DMD and LDC against pinned PostgreSQL."""
import os
from pathlib import Path
import subprocess
import sys

fixture = Path(__file__).resolve().parent
repo = fixture.parents[3]
sys.path.insert(0, str(repo / "tools"))

from spring_bench import postgres_bin, postgres_cluster


def main():
    print("Pinned peer", postgres_bin(), flush=True)
    with postgres_cluster() as database:
        for compiler in ("dmd", "ldc2"):
            subprocess.run(["dub", "build", f"--root={fixture}", f"--compiler={compiler}"],
                           cwd=repo, check=True)
            subprocess.run([fixture / "build/engine-jpa-postgres"],
                           env={**os.environ, **database()}, check=True, timeout=30)
            print(compiler, "passed mapping, flush, propagation, fiber isolation and lease checks", flush=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Link the AOT-generated JPA table and exercise it against pinned PostgreSQL."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools"))

from spring_bench import postgres_bin, postgres_cluster


def main():
    print("Pinned peer", postgres_bin(), flush=True)
    with postgres_cluster() as database:
        for compiler in ("dmd", "ldc2"):
            env = {**os.environ, **database(), "FLINT_AOT_JPA_POSTGRES_COMPILER": compiler}
            subprocess.run(["flint", "test", "-C", "apps/flint", "--compiler", compiler, "--verbose"],
                           cwd=ROOT, env=env, check=True, timeout=300)
            print(compiler, "linked and ran the generated JPA mapping", flush=True)


if __name__ == "__main__":
    main()

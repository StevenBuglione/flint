"""Check the ordinal and mapping of generated Jakarta Persistence option enums."""

import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess
import tempfile

from test_jakarta import MODULE, PACKAGE, PROJECT, ROOT, TAG, command, proposed, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flint", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    opts = parser.parse_args()
    flint, helper, cache = opts.flint.resolve(), opts.helper.resolve(), opts.cache.resolve()
    manifest = json.loads((ROOT / f"api/upstream/{PROJECT}-{TAG}.json").read_text())
    enums = [t for t in manifest["types"] if t["package"] == PACKAGE and t["kind"] == "enum"]
    rejected = Counter()
    generated = 0
    entries = 0
    with tempfile.TemporaryDirectory() as scratch:
        for enum in enums:
            result = run(flint, *command(PROJECT, TAG, enum["id"], helper, cache), "--replace-ported")
            output = json.loads(result.stdout)
            if result.returncode:
                message = output["diagnostics"][0]["message"]
                assert output["diagnostics"][0]["code"] == "FLINT-E1009", output
                assert "unsupported" in message and not output["mapping"], output
                rejected[message.split(": ")[-1].strip()] += 1
                continue
            name = enum["id"].split(".")[-1]
            members = proposed(output["mapping"])
            expected = {enum["id"]: {"status": "ported", "d": f"{MODULE}.{name}"}}
            asserts = []
            for ordinal, constant in enumerate(enum["members"]):
                assert constant["kind"] == "constant", constant
                cname = constant["name"]
                expected[enum["id"] + "#" + cname] = {"status": "ported", "d": f"{MODULE}.{name}.{cname}"}
                asserts.append(f"static assert(cast(int) {name}.{cname} == {ordinal});")
            assert members == expected, (members, expected)
            path = Path(scratch) / f"{name}.d"
            path.write_text(output["source"] + "\n".join(asserts) + "\n", encoding="utf-8")
            for compiler in ("dmd", "ldc2"):
                subprocess.run([compiler, "-preview=dip1000", "-o-", "-c", path], cwd=scratch, check=True)
            generated += 1
            entries += len(expected)
        assert generated
        headers = run(flint, "api", "headers", scratch)
        assert headers.returncode == 0, (headers.stdout, headers.stderr)
    print(f"{generated}/{len(enums)} enums compile unchanged, with Java ordinals and {entries} mapping entries")
    print(f"Rejected: {dict(sorted(rejected.items()))}")


if __name__ == "__main__":
    main()

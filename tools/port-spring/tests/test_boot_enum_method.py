"""Translate the pinned Actuator Access.cap and exercise its R20 contract."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from test_jakarta import ROOT, command, run
from test_jakarta import proposed as without_provenance


PROJECT = "spring-boot"
TAG = "v4.2.0"
ACCESS = "org.springframework.boot.actuate.endpoint.Access"
MODULE = "flint.boot.actuate.endpoint"
HAND_PORT = ROOT / "boot/module/flint-boot-actuator/source/flint/boot/actuate/endpoint"


def hand_reference():
    enum_source = (HAND_PORT / "access.d").read_text(encoding="utf-8")
    functions = (HAND_PORT / "package.d").read_text(encoding="utf-8")
    enumeration = re.search(r"^enum Access\s*\{[^}]*\}", enum_source, re.MULTILINE)
    cap = re.search(r"^Access cap\(Access \w+, Access \w+\) pure nothrow @nogc\s*\{[^}]*\}",
                    functions, re.MULTILINE)
    assert enumeration is not None and cap is not None, "missing Actuator hand-port reference"
    return "module hand;\n@safe:\n" + enumeration[0] + "\n" + cap[0] + "\n"


def verify_behavior(source, scratch):
    draft = scratch / "endpoint.d"
    draft.write_text(source, encoding="utf-8")
    reference = scratch / "hand.d"
    reference.write_text(hand_reference(), encoding="utf-8")
    fixture = scratch / "access_test.d"
    fixture.write_text("""module access_test;
import flint.boot.actuate.endpoint : Access, cap;
static import hand;

@safe:

static assert(cast(int) Access.NONE == 0);
static assert(cast(int) Access.READ_ONLY == 1);
static assert(cast(int) Access.UNRESTRICTED == 2);
static assert(!__traits(compiles, Access.NONE.cap(null)));

pure nothrow @nogc Access capped(Access current, Access maximum)
{
    return current.cap(maximum);
}

void main()
{
    enum values = [Access.NONE, Access.READ_ONLY, Access.UNRESTRICTED];
    foreach (left; values)
        foreach (right; values)
            assert(cast(int) capped(left, right) == cast(int) hand.cap(cast(hand.Access) left, cast(hand.Access) right));
}
""", encoding="utf-8")
    for compiler in ("dmd", "ldc2"):
        binary = scratch / ("access-test-" + compiler)
        subprocess.run([compiler, "-preview=dip1000", "-of=" + str(binary), draft, reference, fixture],
                       cwd=scratch, check=True)
        subprocess.run([binary], cwd=scratch, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flint", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    options = parser.parse_args()
    flint, helper, cache = options.flint.resolve(), options.helper.resolve(), options.cache.resolve()
    arguments = command(PROJECT, TAG, ACCESS, helper, cache, MODULE)
    result = run(flint, *arguments)
    assert result.returncode == 0, (result.stdout, result.stderr)
    output = json.loads(result.stdout)
    assert json.loads(output["mapping"])["elements"] == {}, output
    audited = run(flint, *arguments, "--replace-ported")
    assert audited.returncode == 0, (audited.stdout, audited.stderr)
    proposed = json.loads(audited.stdout)
    assert proposed["source"] == output["source"], proposed
    tracked = json.loads((ROOT / "api/boot/mapping.json").read_text(encoding="utf-8"))["elements"]
    expected = {ACCESS + "#" + member: tracked[ACCESS + "#" + member]
                for member in ("NONE", "READ_ONLY", "UNRESTRICTED", "cap(Access)")}
    assert expected[ACCESS + "#cap(Access)"]["rules"] == ["R20"], expected
    assert without_provenance(proposed["mapping"]) == expected, proposed
    with tempfile.TemporaryDirectory() as scratch:
        verify_behavior(output["source"], Path(scratch))
    print("Actuator Access preserves Java ordinals, caps like the hand port, and rejects null on DMD and LDC")


if __name__ == "__main__":
    main()

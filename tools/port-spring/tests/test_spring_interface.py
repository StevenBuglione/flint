"""Compare the pinned R3 PriorityOrdered draft with Flint's existing interface."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from test_jakarta import ROOT, command, rejects, run


PROJECT = "spring-framework"
TAG = "v7.1.0"
TYPE = "org.springframework.core.PriorityOrdered"
MODULE = "flint.core"
CORE = ROOT / "framework/core/source/flint/core/package.d"


def interface_source(source, name):
    match = re.search(rf"^interface {name}[^\n]*\n\{{.*?^\}}", source, re.MULTILINE | re.DOTALL)
    assert match is not None, name
    return match[0]


def verify_inheritance(source, hand_port, scratch):
    module = scratch / "flint/core/package.d"
    module.parent.mkdir(parents=True)
    module.write_text(source + "\n" + interface_source(hand_port, "Ordered") + "\n", encoding="utf-8")
    probe = scratch / "probe.d"
    probe.write_text("""
import flint.core : Ordered, PriorityOrdered;

@safe:

interface InfrastructureOrder : PriorityOrdered
{
}

final class Infrastructure : InfrastructureOrder
{
    override int getOrder()
    {
        return 7;
    }
}

int orderOf(Ordered value)
{
    return value.getOrder();
}

void main()
{
    auto implementation = new Infrastructure;
    assert(orderOf(implementation) == 7);
    PriorityOrdered direct = implementation;
    assert(orderOf(direct) == 7);
    Ordered inherited = direct;
    assert(cast(PriorityOrdered) inherited is direct);
    assert(direct.getOrder() == 7);
}
""", encoding="utf-8")
    env = dict(os.environ, FLINT_DMD_SERVER="0")
    env.pop("FLINT_DMD_SERVER_PRELUDE", None)
    for compiler in ("dmd", "ldc2"):
        binary = scratch / ("interface-" + compiler)
        subprocess.run([compiler, "-preview=dip1000", "-of=" + str(binary), probe, module],
                       cwd=scratch, env=env, check=True)
        subprocess.run([binary], cwd=scratch, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flint", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    options = parser.parse_args()
    flint, helper, cache = options.flint.resolve(), options.helper.resolve(), options.cache.resolve()
    arguments = command(PROJECT, TAG, TYPE, helper, cache, MODULE)
    current = run(flint, *arguments)
    assert current.returncode == 0, (current.stdout, current.stderr)
    result = run(flint, *arguments, "--replace-ported")
    assert result.returncode == 0, (result.stdout, result.stderr)
    output = json.loads(result.stdout)
    assert output["source"] == json.loads(current.stdout)["source"]
    assert not json.loads(json.loads(current.stdout)["mapping"])["elements"]
    tracked = json.loads((ROOT / "api/framework/mapping.json").read_text(encoding="utf-8"))["elements"]
    assert json.loads(output["mapping"])["elements"] == {TYPE: tracked[TYPE]}, output
    rejects(flint, command(PROJECT, TAG, "org.springframework.core.Ordered", helper, cache, MODULE),
            "not a supported public type")
    rejects(flint, (*command(PROJECT, TAG, TYPE, helper, cache, "flint.other"), "--replace-ported"),
            "parent requires an exact ported mapping")
    rejects(flint, command(PROJECT, TAG, "org.springframework.transaction.ReactiveTransaction", helper, cache,
                           "flint.transaction"), "unsupported marker interface parent")
    hand_port = CORE.read_text(encoding="utf-8")
    assert interface_source(output["source"], "PriorityOrdered") == interface_source(hand_port, "PriorityOrdered")
    with tempfile.TemporaryDirectory() as scratch:
        verify_inheritance(output["source"], hand_port, Path(scratch))
    print("Spring PriorityOrdered matches the hand port and upcasts to Ordered on DMD and LDC")


if __name__ == "__main__":
    main()

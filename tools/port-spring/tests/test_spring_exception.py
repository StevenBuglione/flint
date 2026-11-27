"""Compare a pinned R8 port to the landed transaction exception and exercise the generated constructor."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from test_jakarta import ROOT, command, proposed, rejects, run


PROJECT = "spring-framework"
TAG = "v7.1.0"
TYPE = "org.springframework.transaction.InvalidIsolationLevelException"
MODULE = "flint.transaction"
TRANSACTION = ROOT / "framework/tx/source/flint/transaction/package.d"


def class_source(source, name):
    match = re.search(rf"^(?:abstract )?class {name} : [^\n]+\n\{{.*?^\}}", source, re.MULTILINE | re.DOTALL)
    assert match is not None, name
    return re.sub(r"^\s*///[^\n]*\n", "", match[0], flags=re.MULTILINE)


def verify_constructor(source, hand_port, scratch):
    probe = scratch / "exception.d"
    probe.write_text(source + "\nimport flint.core : NestedRuntimeException;\n\n"
                     + class_source(hand_port, "TransactionException") + "\n\n"
                     + class_source(hand_port, "TransactionUsageException") + "\n" + """
import std.algorithm.searching : canFind;

static assert(!__traits(isFinalClass, InvalidIsolationLevelException));
private enum constructorAttributes = [__traits(getFunctionAttributes, InvalidIsolationLevelException.__ctor)];
static assert(constructorAttributes.canFind("pure") && constructorAttributes.canFind("nothrow"));

void main()
{
    const expectedLine = __LINE__ + 1;
    auto error = new InvalidIsolationLevelException("unsupported isolation");
    assert(error.file == __FILE__);
    assert(error.line == expectedLine);
    assert(error.getCause() is null);
    auto cause = new Exception("cause");
    assert(error.initCause(cause) is error);

    auto empty = new InvalidIsolationLevelException(null, "transaction.d", 7);
    assert(empty.getMessage() is null);
    assert(empty.file == "transaction.d" && empty.line == 7);
    try
        throw error;
    catch (TransactionUsageException caught)
    {
        assert(caught is error);
        assert(caught.getMessage() == "unsupported isolation");
        assert(caught.getCause() is cause);
        return;
    }
    assert(0, "exception hierarchy did not match");
}
""", encoding="utf-8")
    includes = [
        "framework/core/source",
        "framework/engine-aot/source",
        "framework/jakarta-annotation/source",
        "framework/java/source",
        "packages/arena/source",
        "packages/conc/source",
        "packages/serde/source",
    ]
    flags = ["-preview=dip1000", *("-I" + str(ROOT / directory) for directory in includes)]
    env = dict(os.environ, FLINT_DMD_SERVER="0")
    env.pop("FLINT_DMD_SERVER_PRELUDE", None)
    for compiler in ("dmd", "ldc2"):
        binary = scratch / ("exception-" + compiler)
        subprocess.run([compiler, *flags, "-i", "-of=" + str(binary), probe], cwd=scratch, env=env, check=True)
        subprocess.run([binary], cwd=scratch, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flint", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    options = parser.parse_args()
    flint, helper, cache = options.flint.resolve(), options.helper.resolve(), options.cache.resolve()
    args = command(PROJECT, TAG, TYPE, helper, cache, MODULE)
    default = run(flint, *args)
    assert default.returncode == 0, (default.stdout, default.stderr)
    result = run(flint, *args, "--replace-ported")
    assert result.returncode == 0, (result.stdout, result.stderr)
    output = json.loads(result.stdout)
    assert output["source"] == json.loads(default.stdout)["source"]
    assert not json.loads(json.loads(default.stdout)["mapping"])["elements"]
    tracked = json.loads((ROOT / "api/framework/mapping.json").read_text(encoding="utf-8"))["elements"]
    ids = [TYPE, TYPE + "#<init>(String)"]
    assert proposed(output["mapping"]) == {key: tracked[key] for key in ids}, output
    rejects(flint, (*command(PROJECT, TAG, TYPE, helper, cache, "flint.other"), "--replace-ported"),
            "unsupported exception base or destination")
    other = "org.springframework.transaction.CannotCreateTransactionException"
    rejects(flint, command(PROJECT, TAG, other, helper, cache, MODULE), "not a supported public type")
    hand_port = TRANSACTION.read_text(encoding="utf-8")
    name = TYPE.rsplit(".", 1)[1]
    assert class_source(output["source"], name) == class_source(hand_port, name), output
    with tempfile.TemporaryDirectory() as scratch:
        verify_constructor(output["source"], hand_port, Path(scratch))
    print("Spring InvalidIsolationLevelException matches the hand port and runs on DMD and LDC")


if __name__ == "__main__":
    main()

"""Compare the Spring AI constant-holder draft and mapping with the landed Flint class."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from test_jakarta import ROOT, command, proposed, rejects, run


PROJECT = "spring-ai"
TAG = "v2.1.0"
TYPE = "org.springframework.ai.model.SpringAIModels"
MODULE = "flint.ai.model"
PORT = ROOT / "ai/ai-model/source/flint/ai/model.d"


def constant_holder(source):
    match = re.search(r"^final class FlintAIModels\n\{\n(.*?)^\}", source, re.MULTILINE | re.DOTALL)
    assert match is not None, source
    lines = [line.strip() for line in match[1].splitlines() if line.strip() and not line.lstrip().startswith("///")]
    assert lines[0] == "@disable this();"
    return lines[1:]


def verify_constants(source, fields, scratch):
    module = scratch / "flint/ai/model.d"
    module.parent.mkdir(parents=True)
    module.write_text(source, encoding="utf-8")
    consumer = scratch / "consumer.d"
    checks = []
    for field in fields:
        match = re.fullmatch(r'enum string (\w+) = ("[^"]*");', field)
        assert match is not None, field
        name, value = match.groups()
        checks.append(f"static assert(FlintAIModels.{name} == {value});")
    consumer.write_text("import flint.ai.model : FlintAIModels;\n\n"
                        "static assert(__traits(isFinalClass, FlintAIModels));\n"
                        "static assert(!__traits(compiles, new FlintAIModels()));\n"
                        + "\n".join(checks) + "\n", encoding="utf-8")
    env = dict(os.environ, FLINT_DMD_SERVER="0")
    env.pop("FLINT_DMD_SERVER_PRELUDE", None)
    for compiler in ("dmd", "ldc2"):
        subprocess.run([compiler, "-preview=dip1000", "-c", "-o-", consumer, module],
                       cwd=scratch, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flint", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    options = parser.parse_args()
    flint, helper, cache = options.flint.resolve(), options.helper.resolve(), options.cache.resolve()
    arguments = command(PROJECT, TAG, TYPE, helper, cache, MODULE)
    default = run(flint, *arguments)
    assert default.returncode == 0, (default.stdout, default.stderr)
    replacement = run(flint, *arguments, "--replace-ported")
    assert replacement.returncode == 0, (replacement.stdout, replacement.stderr)
    output = json.loads(replacement.stdout)
    assert output["source"] == json.loads(default.stdout)["source"]
    assert not json.loads(json.loads(default.stdout)["mapping"])["elements"]
    rows = json.loads((ROOT / "api/ai/mapping.json").read_text(encoding="utf-8"))["elements"]
    expected = {key: value for key, value in rows.items() if key == TYPE or key.startswith(TYPE + "#")}
    assert len(expected) == 19 and not any("#<init>" in key for key in expected)
    assert proposed(output["mapping"]) == expected, output
    rejects(flint, command(PROJECT, TAG, "org.springframework.ai.model.SpringAIModelProperties", helper, cache, MODULE),
            "unsupported constant holder")
    fields = constant_holder(PORT.read_text(encoding="utf-8"))
    assert len(fields) == 18 and constant_holder(output["source"]) == fields, output
    with tempfile.TemporaryDirectory() as scratch:
        verify_constants(output["source"], fields, Path(scratch))
    print("SpringAIModels matches all 18 FlintAIModels values, ordering and mappings on DMD and LDC")


if __name__ == "__main__":
    main()

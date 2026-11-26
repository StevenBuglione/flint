"""Translate Spring Component and verify its marker through Flint's annotation merger."""

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
COMPONENT = "org.springframework.stereotype.Component"
MODULE = "flint.stereotype"
STEREOTYPES = ROOT / "framework/context/source/flint/stereotype.d"


def component_signature(source):
    match = re.search(r"^@(\w+)\nstruct Component\s*\{([^}]*)\}", source, re.MULTILINE)
    assert match is not None, source
    marker, body = match.groups()
    uncommented = re.sub(r"//[^\n]*", "", body)
    # Flint strings treat a missing default and Java's empty string alike.
    fields = re.sub(r'\s*=\s*""\s*;', ";", uncommented)
    return marker, fields.split()


def verify_composition(source, hand_port, scratch):
    indexed = re.search(r"^struct Indexed\s*\{[^}]*\}", hand_port, re.MULTILINE)
    assert indexed is not None, hand_port
    probe = scratch / "flint/stereotype.d"
    probe.parent.mkdir()
    probe.write_text(source + "\n" + indexed[0] + "\n" + """
import flint.core.annotation.types : MergedAnnotations;
import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.aot.name : typeNameOf;

@Component struct Service {}
@Component class Direct {}
@Service class Transitive {}

static assert(Component.init.value == "");
static assert(typeNameOf!Component == "flint.stereotype.Component");

void main()
{
    const direct = descriptorOf!Direct;
    const transitive = descriptorOf!Transitive;
    const component = direct.annotation(typeNameOf!Component);
    const marker = direct.annotation(typeNameOf!Indexed);
    const inheritedMarker = transitive.annotation(typeNameOf!Indexed);
    assert(component !is null && component.distance == 0);
    assert(marker !is null && marker.distance == 1);
    assert(inheritedMarker !is null && inheritedMarker.distance == 2);
    const merged = MergedAnnotations.from(transitive.annotations);
    assert(merged.isPresent!Indexed && merged.isPresent!Component && merged.isPresent!Service);
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
    flags = ["-preview=dip1000", "-I" + str(scratch), *("-I" + str(ROOT / directory) for directory in includes)]
    request = scratch / "request.txt"
    request.write_text(f"module {MODULE}\n", encoding="utf-8")
    native = scratch / "extract.d"
    native.write_text(f"module extract;\nstatic import {MODULE};\n", encoding="utf-8")
    fallback = write_describer(scratch)
    env = dict(os.environ, FLINT_DMD_SERVER="0")
    env.pop("FLINT_DMD_SERVER_PRELUDE", None)
    for compiler in ("dmd", "ldc2"):
        binary = scratch / ("marker-" + compiler)
        subprocess.run([compiler, *flags, "-i", "-of=" + str(binary), probe], cwd=scratch, env=env, check=True)
        subprocess.run([binary], cwd=scratch, check=True)
        extraction = [f"-flint-aot-extract={request}", native] if compiler == "dmd" else [fallback]
        result = subprocess.run([compiler, *flags, "-o-", "-c", *extraction],
                                cwd=scratch, env=env, capture_output=True, text=True, check=False)
        assert result.returncode == 0, (compiler, result.stdout, result.stderr)
        annotations = model_documents(result, "FLINT-AOT-ANNOTATION ")
        assert [meta["type"] for meta in annotations[MODULE + ".Component"]["meta"]] == [MODULE + ".Indexed"]
        types = model_documents(result, f"FLINT-AOT-TYPE {MODULE} ")
        assert [annotation["type"] for annotation in types[MODULE + ".Direct"]["annotations"]] == [MODULE + ".Component"]


def write_describer(scratch):
    source = (ROOT / "apps/flint/src/flint_tool/engine/aot/extract.d").read_text(encoding="utf-8")
    describer = re.search(r"^enum describerSource = `(.*?)`;$", source, re.MULTILINE | re.DOTALL)
    assert describer is not None, "Flint AOT describer source missing"
    (scratch / "flint_aot_describe.d").write_text(describer[1], encoding="utf-8")
    (scratch / "flint_aot_known.d").write_text(
        "module flint_aot_known;\nbool flintAotKnownAnnotation(string name) { return false; }\n", encoding="utf-8")
    root = scratch / "describe.d"
    root.write_text("module describe;\nimport flint_aot_describe : describeModule;\n"
                    f'static import {MODULE};\nstatic if (describeModule!({MODULE}, "{MODULE}")) {{}}\n', encoding="utf-8")
    return root


def model_documents(result, prefix):
    documents = [json.loads(line[len(prefix):]) for line in (result.stdout + result.stderr).splitlines()
                 if line.startswith(prefix)]
    return {document.get("fqn", document["name"]): document for document in documents}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flint", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    options = parser.parse_args()
    flint, helper, cache = options.flint.resolve(), options.helper.resolve(), options.cache.resolve()
    arguments = command(PROJECT, TAG, COMPONENT, helper, cache, MODULE)
    result = run(flint, *arguments, "--replace-ported")
    assert result.returncode == 0, (result.stdout, result.stderr)
    output = json.loads(result.stdout)
    hand_port = STEREOTYPES.read_text(encoding="utf-8")
    assert component_signature(output["source"]) == component_signature(hand_port), output
    assert json.loads(output["mapping"])["elements"] == {
        COMPONENT: {"status": "adapted", "rules": ["R2"], "d": MODULE + ".Component"},
        COMPONENT + "#value": {"status": "adapted", "rules": ["R2"], "d": MODULE + ".Component.value"},
    }, output
    rejects(flint, arguments, "mapping conflict")
    rejects(flint, (*command(PROJECT, TAG, COMPONENT, helper, cache, "flint.other"), "--replace-ported"),
            "outside destination module")
    with tempfile.TemporaryDirectory() as scratch:
        verify_composition(output["source"], hand_port, Path(scratch))
    print("Spring Component matches the hand port and Indexed is visible directly and transitively on DMD and LDC")


if __name__ == "__main__":
    main()

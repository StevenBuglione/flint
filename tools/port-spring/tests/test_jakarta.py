"""Score every public Jakarta Persistence annotation against the pinned API and hand port."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import tempfile


PROJECT = "jakarta-persistence"
TAG = "3.2.0"
PACKAGE = "jakarta.persistence"
MODULE = "flint.jakarta.persistence"
ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / "framework/jakarta-persistence/source/flint/jakarta/persistence/annotations.d"


def declarations(source):
    return dict(re.findall(r"^struct (\w+)\s*\{([^}]*)\}", source, flags=re.MULTILINE))


def compare_fields(body):
    fields = {}
    for line in body.splitlines():
        match = re.fullmatch(r"\s*(\w+(?:\[\])?) (\w+)(?: = (.*))?;", line)
        if match:
            type_name, name, default = match.groups()
            fields[name] = type_name, None if type_name.endswith("[]") and default == "[]" else default
    return fields


def run(fl, *args):
    return subprocess.run([str(fl), *map(str, args)], cwd=ROOT, capture_output=True, check=False)


def command(project, tag, type_id, helper, cache, module=MODULE):
    return (
        "port-spring", "--project", project, "--tag", tag, "--type", type_id,
        "--module", module, "--cache", cache, "--helper", helper, "--json",
    )


def rejects(flint, args, diagnostic):
    result = run(flint, *args)
    output = json.loads(result.stdout)
    assert result.returncode and not output["source"] and not output["mapping"], output
    assert output["diagnostics"][0]["code"] == "FLINT-E1009", output
    assert diagnostic in output["diagnostics"][0]["message"], output


def check_cli(flint, helper, cache, scratch):
    basic = run(flint, *command(PROJECT, TAG, PACKAGE + ".Basic", helper, cache))
    assert basic.returncode == 0, (basic.stdout, basic.stderr)
    basic_output = json.loads(basic.stdout)
    assert "    FetchType fetch = FetchType.EAGER;" in basic_output["source"], basic_output
    assert not json.loads(basic_output["mapping"])["elements"], basic_output
    rejects(flint, command(PROJECT, TAG, PACKAGE + ".Basic", helper, cache, "flint.example"),
            "unsupported enum type outside destination module")

    args = command(PROJECT, TAG, PACKAGE + ".Entity", helper, cache)
    output_dir = scratch / "entity"
    first = run(flint, *args, "--output", output_dir)
    assert first.returncode == 0, (first.stdout, first.stderr)
    output = json.loads(first.stdout)
    source = output_dir / "persistence.d"
    fragment = output_dir / "mapping.json"
    assert source.read_text() == output["source"]
    assert fragment.read_text() == output["mapping"]
    assert not json.loads(output["mapping"])["elements"]
    second = run(flint, *args, "--output", output_dir)
    assert second.returncode and source.read_text() == output["source"]
    assert json.loads(second.stdout)["diagnostics"][0]["code"] == "FLINT-E1010", second.stdout
    assert fragment.read_text() == output["mapping"]
    rejects(flint, command(PROJECT, TAG, PACKAGE + ".Entity", helper, scratch), "checksum stamp")
    rejects(flint, command(PROJECT, TAG, PACKAGE + ".Missing", helper, cache), "pinned manifest")
    rejects(flint, command(PROJECT, TAG, PACKAGE + ".Entity", helper, cache, "flint.example"), "mapping conflict")
    rejects(flint, command("jakarta-annotation", "3.0.0", "jakarta.annotation.Resource", helper, cache),
            "registered EPL-2.0")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flint", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    opts = parser.parse_args()
    flint = opts.flint.resolve()
    helper = opts.helper.resolve()
    cache = opts.cache.resolve()
    manifest = json.loads((ROOT / f"api/upstream/{PROJECT}-{TAG}.json").read_text())
    mapping = json.loads((ROOT / "api/framework/mapping.json").read_text())["elements"]
    hand_source = PORT.read_text()
    hand = declarations(hand_source)
    option_types = "\n".join(re.findall(r"^enum \w+\s*\{[^}]*\}", hand_source, flags=re.MULTILINE))
    annotations = [t for t in manifest["types"] if t["package"] == PACKAGE and t["kind"] == "annotation"]
    generated = []
    matched = 0
    class_rules = 0
    deferred = []
    rejected = Counter()
    for annotation in annotations:
        result = run(flint, *command(PROJECT, TAG, annotation["id"], helper, cache), "--replace-ported")
        output = json.loads(result.stdout)
        assert output["schema"] == "flint.port-spring/1", output
        if result.returncode:
            messages = [entry["message"] for entry in output["diagnostics"]]
            assert len(messages) == 1 and "unsupported" in messages[0], messages
            assert not output["source"] and not output["mapping"]
            rejected[messages[0].split(": ")[-1].strip()] += 1
            continue
        fragment = json.loads(output["mapping"])
        expected = {annotation["id"], *(annotation["id"] + "#" + m["signature"] for m in annotation["members"])}
        assert fragment["rulebook"] == 2 and set(fragment["elements"]) == expected, fragment
        name = annotation["id"].split(".")[-1]
        body = declarations(output["source"])[name]
        if name in hand:
            for element, entry in fragment["elements"].items():
                old = mapping[element]
                if entry != old:
                    assert (entry["status"], entry["d"]) == (old["status"], old["d"]), (element, entry, old)
                    assert set(entry["rules"]) ^ set(old["rules"]) == {"R4"}, (element, entry, old)
                    class_rules += 1
            assert compare_fields(body) == compare_fields(hand[name]), (name, body, hand[name])
            matched += 1
        else:
            for element in expected:
                assert mapping[element].get("category") == "deferred", mapping[element]
            deferred.append(name)
        generated.append((name, output["source"], len(expected)))
    assert generated, "no generated Jakarta annotations"
    with tempfile.TemporaryDirectory() as scratch:
        scratch = Path(scratch)
        check_cli(flint, helper, cache, scratch)
        for name, source, _ in generated:
            # Compile each candidate in the Jakarta leaf that provides its referenced types.
            imports = "import flint.java.classref : ClassRef;\n"
            dependencies = "\n".join(f"struct {other}\n{{{body}}}" for other, body in hand.items() if other != name)
            leaf = source + "\n" + ("" if imports in source else imports) + option_types + "\n" + dependencies
            (scratch / f"{name}.d").write_text(leaf, encoding="utf-8")
        result = run(flint, "api", "headers", scratch)
        assert result.returncode == 0, (result.stdout, result.stderr)
        for compiler in ("dmd", "ldc2"):
            for name, _, _ in generated:
                subprocess.run(
                    [compiler, "-preview=dip1000", "-o-", "-c",
                     "-I" + str(ROOT / "framework/java/source"), scratch / f"{name}.d"],
                    cwd=scratch,
                    check=True,
                )
    print(f"{len(generated)}/{len(annotations)} annotations compile unchanged on DMD and LDC")
    print(f"{sum(count for _, _, count in generated)} mapping entries, {matched} annotations match the hand port")
    print(f"Class-token mappings differ only in R4 citations for {class_rules} existing entries")
    print(f"Deferred annotations with generated candidates: {', '.join(deferred)}")
    print(f"Rejected: {dict(sorted(rejected.items()))}")


if __name__ == "__main__":
    main()

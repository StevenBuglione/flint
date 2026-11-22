module flint_tool.project.native_test;

import flint_tool.diagnostics.report : Report;
import flint_tool.fixtures : codes;
import flint_tool.project.manifest : Manifest, NativeDependency;
import flint_tool.project.native : NativeRequirement, collectRequirements;
import flint.test : expect;

@safe:

@("native requirements merge, and two versions of one package name both requesters")
unittest
{
    Manifest manifest;
    manifest.natives = [NativeDependency("zlib", "1.4")];
    NativeRequirement[] requirements;
    Report report;
    expect(collectRequirements(manifest, ["dub:dyaml": ["zlib@1.4"], "model": ["sqlite@3.54.1"]],
            requirements, report)).toEqual(true);
    expect(requirements.length).toEqual(3);
    expect(requirements[1].requester).toEqual("dub:dyaml");
    Report conflict;
    expect(collectRequirements(manifest, ["model": ["zlib@1.3.1"]], requirements, conflict)).toEqual(false);
    expect(codes(conflict)).toEqual(["FLINT-E0320"]);
    expect(conflict.items[0].message).toEqual(
            "native package zlib is required at two versions: the project needs 1.4 and model needs 1.3.1");
}

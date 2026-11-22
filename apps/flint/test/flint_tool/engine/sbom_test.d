module flint_tool.engine.sbom_test;

import flint_tool.engine.oci : jsonString, rfc3339;
import flint_tool.engine.sbom : reference, uuidOf;
import flint_tool.commands.deps : obligationOf;
import flint.test : expect;

@safe:

@("LGPL and AGPL obligations depend on the licence and the linkage")
unittest
{
    import std.algorithm.searching : canFind;

    expect(obligationOf("MIT", "static").length).toEqual(0);
    expect(obligationOf("GPL-3.0-or-later WITH GCC-exception-3.1", "static").length).toEqual(0);
    expect(obligationOf("LGPL-2.1-or-later", "static").canFind("relink")).toEqual(true);
    expect(obligationOf("LGPL-2.1-or-later", "dynamic").canFind("replace")).toEqual(true);
    expect(obligationOf("AGPL-3.0-only", "static").canFind("network")).toEqual(true);
    expect(obligationOf("GPL-2.0-only", "static").canFind("copyleft")).toEqual(true);
}

@("references, UUIDs, JSON strings and timestamps are well formed")
unittest
{
    expect(reference("remote", "github.com/acme/x_y")).toEqual("remote-github.com-acme-x-y");
    const uuid = uuidOf("ebce24f8bd1e9e61161c991b25fa37ea351f30ecfc6389915e54ba06b92eca9b");
    expect(uuid).toEqual("ebce24f8-bd1e-5e61-961c-991b25fa37ea");
    expect(jsonString("a\"b\\\n")).toEqual(`"a\"b\\\u000a"`);
    expect(rfc3339(1_700_000_000)).toEqual("2023-11-14T22:13:20Z");
}

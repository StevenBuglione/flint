module flint_tool.commands.lsp_test;

import flint_tool.commands.lsp : compilerDiagnostics, pathUri, uriPath, wordAt, wordBefore;
import flint.test : expect;

@safe:

@("compiler output becomes zero-based diagnostics for the checked file only")
unittest
{
    const output = "/w/src/a.d(7,9): Error: undefined identifier `x`\n/w/src/b.d(1,1): Error: other\n"
        ~ "/w/src/a.d(9): Deprecation: old\n";
    const found = compilerDiagnostics(output, "/w/src/a.d");
    expect(found.length).toEqual(2);
    expect(found[0].line).toEqual(6);
    expect(found[0].column).toEqual(8);
    expect(found[0].severity).toEqual(1);
    expect(found[0].message).toEqual("undefined identifier `x`");
    expect(found[1].severity).toEqual(2);
    expect(found[1].column).toEqual(0);
}

@("words are found around and before a position")
unittest
{
    const text = "import flint.config : load;\n    Configur\n";
    expect(wordAt(text, 0, 23)).toEqual("load");
    expect(wordAt(text, 0, 7)).toEqual("flint");
    expect(wordBefore(text, 1, 12)).toEqual("Configur");
    expect(wordAt(text, 5, 0).length).toEqual(0);
}

version (Posix) @("file URIs round-trip, including spaces")
unittest
{
    expect(uriPath("file:///work/my%20shop/src/a.d")).toEqual("/work/my shop/src/a.d");
    expect(uriPath(pathUri("/work/my shop/a.d"))).toEqual("/work/my shop/a.d");
}

version (Windows) @("Windows file URIs carry the drive after a slash and map to backslash paths")
unittest
{
    expect(uriPath("file:///C:/work/my%20shop/src/a.d")).toEqual(`C:\work\my shop\src\a.d`);
    expect(uriPath("file:///c%3A/work/a.d")).toEqual(`c:\work\a.d`);
    expect(pathUri(`C:\work\my shop\a.d`)).toEqual("file:///C:/work/my%20shop/a.d");
    expect(uriPath(pathUri(`C:\work\my shop\a.d`))).toEqual(`C:\work\my shop\a.d`);
}

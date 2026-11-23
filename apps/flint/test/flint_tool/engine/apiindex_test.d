module flint_tool.engine.apiindex_test;

import flint_tool.engine.apiindex : ApiIndex, Symbol, functionSignature, lookup, search, unittestBlocks;
import flint.test : expect;

@safe:

@("function signatures put the name before the parameter list")
unittest
{
    expect(functionSignature("@safe Result!ExitStatus(ref scope Context context, scope const(char[])[] argv)",
            "run", null)).toEqual("@safe Result!ExitStatus run(ref scope Context context, scope const(char[])[] argv)");
    expect(functionSignature("Result!T(ref scope const ConfigOptions options) nothrow", "load", "(T)")).toEqual(
            "Result!T load(T)(ref scope const ConfigOptions options) nothrow");
    expect(functionSignature("const(char)[](int (*f)(int))", "pick", null)).toEqual(
            "const(char)[] pick(int (*f)(int))");
    expect(functionSignature("", "f", null)).toEqual("f(...)");
}

@("unittest blocks keep their attributes, line and identifiers")
unittest
{
    const text = "module t;\nimport flint.os : run;\n\n@(\"runs\")\nunittest\n{\n    run(context, [\"x\"]);\n}\n";
    const blocks = unittestBlocks(text, "packages/os/tests/t.d");
    expect(blocks.length).toEqual(1);
    expect(blocks[0].line).toEqual(4);
    expect(blocks[0].code[0 .. 9]).toEqual("@(\"runs\")");
    expect(("run" in blocks[0].identifiers) !is null).toEqual(true);
    expect(blocks[0].imports("flint.os")).toEqual(true);
    expect(blocks[0].imports("flint.engine.web")).toEqual(false);
}

@("search ranks exact names, then prefixes, then documentation")
unittest
{
    ApiIndex index;
    index.symbols = [
        Symbol("flint.config.loadAll", "loadAll", "function"),
        Symbol("flint.config.load", "load", "function"),
        Symbol("flint.os.run", "run", "function", "os", "flint.os", "", "Load and run a command")
    ];
    const hits = search(index, "load", 10);
    expect(index.symbols[hits[0].index].qualified).toEqual("flint.config.load");
    expect(index.symbols[hits[1].index].qualified).toEqual("flint.config.loadAll");
    expect(index.symbols[hits[2].index].qualified).toEqual("flint.os.run");
    expect(search(index, "nothing here", 10).length).toEqual(0);
    expect(lookup(index, "flint.os.run")).toEqual(2);
    expect(lookup(index, "flint.os.absent")).toEqual(size_t.max);
}

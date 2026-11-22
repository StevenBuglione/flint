module flint_tool.check.lexer_test;

import flint_tool.check.lexer : DependencyEdge, LexFailure, Token, compilerDependencyEdges,
    declaredModule, hasStringMixin, importedModules, moduleDefault, tokenize;
import flint.test : expect;

@safe:

private string[] values(string source)
{
    Token[] tokens;
    LexFailure failure;
    assert(tokenize(source, tokens, failure), failure.message);
    string[] result;
    foreach (token; tokens)
        result ~= token.value;
    return result;
}

@("tokens follow tools/d_source.py: identifiers, numbers, single bytes and literals")
unittest
{
    expect(values("module a.b; x1 = 0x1F + r\"raw\\\" `w` 'c' /* c */ // c\n/+ /+ n +/ +/ y;")).toEqual([
        "module", "a", ".", "b", ";", "x1", "=", "0", "x1F", "+", "<literal>", "<literal>",
        "<literal>", "y", ";"
    ]);
}

@("line numbers count newlines inside comments and literals")
unittest
{
    Token[] tokens;
    LexFailure failure;
    assert(tokenize("a\n/* x\n y */ \"p\nq\" b", tokens, failure));
    expect(tokens.length).toEqual(3);
    expect(tokens[1].line).toEqual(3);
    expect(tokens[2].line).toEqual(4);
}

@("token strings and unterminated constructs are refused, never passed")
unittest
{
    Token[] tokens;
    LexFailure failure;
    expect(tokenize("enum x = q{ @trusted };", tokens, failure)).toEqual(false);
    expect(failure.message).toEqual("use checked generator files; token strings require AST review");
    expect(tokenize("a /* open", tokens, failure)).toEqual(false);
    expect(tokenize("a /+ /+ +/", tokens, failure)).toEqual(false);
    expect(tokenize("a = \"open", tokens, failure)).toEqual(false);
    expect(failure.message).toEqual("unterminated literal");
}

@("module declaration, imports and the module default")
unittest
{
    Token[] tokens;
    LexFailure failure;
    assert(tokenize("module p.q;\nstatic import std.stdio;\nimport a = b.c, d : e;\n@safe:\nvoid f() {}",
            tokens, failure));
    string name;
    assert(declaredModule(tokens, name, failure));
    expect(name).toEqual("p.q");
    string[] modules;
    assert(importedModules(tokens, modules, failure));
    expect(modules).toEqual(["std.stdio", "b.c", "d"]);
    expect(moduleDefault(tokens)).toEqual("safe");

    assert(tokenize("module p;\nvoid f() {}\n@safe:", tokens, failure));
    expect(moduleDefault(tokens) is null).toEqual(true);
    assert(tokenize("void f();", tokens, failure));
    expect(declaredModule(tokens, name, failure)).toEqual(false);
}

@("string mixins are found by `mixin(`, not by template mixins")
unittest
{
    Token[] tokens;
    LexFailure failure;
    assert(tokenize("module m;\nmixin Foo!();\n", tokens, failure));
    expect(hasStringMixin(tokens)).toEqual(false);
    assert(tokenize("module m;\nmixin(\"int x;\");\n", tokens, failure));
    expect(hasStringMixin(tokens)).toEqual(true);
}

@("DMD -deps records parse into edges and unknown records fail")
unittest
{
    DependencyEdge[] edges;
    LexFailure failure;
    const deps = "flint.cli (/x/cli.d) : private : flint.arena (/x/arena.d)\n\n"
        ~ "flint.cli (/x/cli.d) : public static : core.stdc.string (/y/string.d)\n";
    assert(compilerDependencyEdges(deps, edges, failure), failure.message);
    expect(edges.length).toEqual(2);
    expect(edges[0].imported).toEqual("flint.arena");
    expect(edges[1].imported).toEqual("core.stdc.string");
    expect(compilerDependencyEdges("garbage line\n", edges, failure)).toEqual(false);
}

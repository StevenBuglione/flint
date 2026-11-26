/// Runs Flint AOT's shared SpEL corpus through the interpreter.
module flint.expression.aot_parity_tests;

import flint.engine.aot.any : Any;
import flint.expression.spel : SpelParseException;
import flint.expression.spel.standard : SpelExpressionParser;
import flint.java.lang : doubleToString, floatToString;
import std.file : exists, readText;
import std.json : JSONValue, parseJSON;
import std.path : absolutePath, buildNormalizedPath, buildPath, dirName;
import std.process : environment;

@safe:

private enum corpusPath = "tests/aot/spel-parity/cases.json";

private string corpusFile()
{
    const workspaceFile = environment.get("FLINT_WORKSPACE", "");
    if (workspaceFile.length)
    {
        const workspace = parseJSON(readText(workspaceFile));
        const checkout = workspace["checkouts"]["flint"]["path"].str;
        return buildPath(absolutePath(checkout, dirName(absolutePath(workspaceFile))), corpusPath);
    }

    const home = environment.get("FLINT_HOME", "");
    if (home.length && exists(buildPath(home, corpusPath)))
        return buildPath(home, corpusPath);

    const directory = buildNormalizedPath(absolutePath("."));
    if (exists(buildPath(directory, corpusPath)))
        return buildPath(directory, corpusPath);
    const monorepo = buildNormalizedPath(directory, "..", "..");
    if (directory == buildPath(monorepo, "framework", "expression") && exists(buildPath(monorepo, corpusPath)))
        return buildPath(monorepo, corpusPath);
    assert(false, "The Flint AOT SpEL parity corpus is missing. Set FLINT_WORKSPACE or FLINT_HOME");
}

private string valueText(const ref Any value)
{
    switch (value.typeName())
    {
    case "double":
        return doubleToString(value.get!double);
    case "float":
        return floatToString(value.get!float);
    default:
        return value.toString();
    }
}

private void checkCase(SpelExpressionParser parser, const ref JSONValue row)
{
    const id = row["id"].str;
    const expected = row["expected"];
    if (auto mode = "compiledOnly" in row)
    {
        assert(mode.str.length && ("runtimeOnly" in row) is null, id);
        return;
    }
    assert(("context" in row) is null, id ~ ": the interpreter driver needs a context for this case");
    if (auto error = "error" in expected)
    {
        assert(error.str == "syntax", id);
        try
        {
            parser.parseExpression(row["expression"].str);
            assert(false, id);
        }
        catch (SpelParseException rejection)
        {
            assert(rejection.getPosition() >= 0, id);
        }
        return;
    }
    const value = parser.parseExpression(row["expression"].str).getValue();
    const expectedType = expected["type"].str;
    assert((value.isNull() ? "null" : value.typeName()) == expectedType, id);
    assert(valueText(value) == expected["value"].str, id);
}

@("Flint AOT's shared SpEL parity corpus")
unittest
{
    const cases = parseJSON(readText(corpusFile())).arrayNoRef;
    assert(cases.length > 0);
    auto parser = new SpelExpressionParser;
    foreach (ref row; cases)
        checkCase(parser, row);
}

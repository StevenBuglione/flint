/// Static AspectJ selectors supported by the AOT planner.
module flint_tool.engine.aot.aspects;

import std.algorithm.searching : endsWith, startsWith;
import std.string : lastIndexOf, strip;

@safe:

/// Canonical UDA names in flint:aspectj.
enum aspectAnnotation = "flint.aspectj.lang.annotation.Aspect";
/// ditto
enum beforeAnnotation = "flint.aspectj.lang.annotation.Before";
/// Advice kinds reserved for later proxy slices.
immutable string[] otherAdvice = [
    "flint.aspectj.lang.annotation.After", "flint.aspectj.lang.annotation.AfterReturning",
    "flint.aspectj.lang.annotation.AfterThrowing", "flint.aspectj.lang.annotation.Around"
];

/// The qualified class and method named by the initial static execution syntax.
struct ExecutionSelector
{
    /// The exact extracted target type.
    string target;
    /// The method name, matching all overloads.
    string method;
}

/// Reads `execution(* qualified.Type.method(..))`; an empty target denotes invalid syntax.
ExecutionSelector parseExecution(string expression)
{
    enum prefix = "execution(";
    expression = expression.strip;
    if (!expression.startsWith(prefix) || !expression.endsWith(")"))
        return ExecutionSelector.init;

    auto signature = expression[prefix.length .. $ - 1].strip;
    if (signature.length < 2 || signature[0] != '*' || !whitespace(signature[1]))
        return ExecutionSelector.init;
    signature = signature[1 .. $].strip;

    enum arguments = "(..)";
    if (!signature.endsWith(arguments))
        return ExecutionSelector.init;
    auto qualified = signature[0 .. $ - arguments.length].strip;
    const separator = qualified.lastIndexOf('.');
    if (separator <= 0 || !qualifiedName(qualified[0 .. separator]) || !identifier(qualified[separator + 1 .. $]))
        return ExecutionSelector.init;
    return ExecutionSelector(qualified[0 .. separator], qualified[separator + 1 .. $]);
}

private bool qualifiedName(string name)
{
    import std.algorithm.iteration : splitter;

    if (name.length == 0 || name[$ - 1] == '.')
        return false;
    foreach (part; name.splitter('.'))
        if (!identifier(part))
            return false;
    return true;
}

private bool whitespace(char ch) pure nothrow @nogc
{
    return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n';
}

private bool identifier(string name) pure nothrow @nogc
{
    if (name.length == 0 || !initial(name[0]))
        return false;
    foreach (ch; name[1 .. $])
        if (!initial(ch) && (ch < '0' || ch > '9'))
            return false;
    return true;
}

private bool initial(char ch) pure nothrow @nogc
{
    return ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

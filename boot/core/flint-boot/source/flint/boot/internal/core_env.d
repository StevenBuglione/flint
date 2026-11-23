// Ported from spring-framework v7.1.0: spring-core/src/main/java/org/springframework/core/env/ProfilesParser.java
// and SimpleCommandLineArgsParser.java, CommandLineArgs.java in the same directory.
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: profile expressions compile to a small tree instead of lambdas.

/// Boot's private copies of two spring-core helpers: command-line parsing and profile expressions.
///
/// framework-core owns `flint.core.env`. Until it publishes `SimpleCommandLinePropertySource` and `Profiles`, Boot
/// uses these, and the day those land, this file is deleted and its importers switch over.
module flint.boot.internal.core_env;

import flint.boot.internal.lang : IllegalArgumentException;

@safe:

/// Parsed command-line arguments: `--name=value` options (repeatable) and the remaining non-option arguments.
final class CommandLineArgs
{
    private string[] names;
    private string[][string] options;
    private string[] nonOptionArgs;

    /// Record option `name` with `value` (`null` for `--name` without a value).
    void addOptionArg(string name, string value) pure
    {
        if ((name in options) is null)
        {
            names ~= name;
            options[name] = null;
        }
        if (value !is null)
            options[name] ~= value;
    }

    /// The option names, in order of first appearance.
    const(string)[] getOptionNames() const pure nothrow @nogc
    {
        return names;
    }

    /// Whether `name` was given.
    bool containsOption(string name) const pure nothrow
    {
        return (name in options) !is null;
    }

    /// The values of `name`: empty for `--name` alone, `null` when it was not given.
    const(string)[] getOptionValues(string name) const pure nothrow
    {
        if (auto values = name in options)
            return *values is null ? [] : *values;
        return null;
    }

    /// Record a non-option argument.
    void addNonOptionArg(string value) pure nothrow
    {
        nonOptionArgs ~= value;
    }

    /// The non-option arguments, in order.
    const(string)[] getNonOptionArgs() const pure nothrow @nogc
    {
        return nonOptionArgs;
    }
}

/// Parse `args` as Spring does: `--name=value`, `--name`, and `--` ending the options.
CommandLineArgs parseCommandLine(scope const string[] args) pure
{
    import std.algorithm.searching : startsWith;
    import std.string : indexOf;

    auto result = new CommandLineArgs;
    bool endOfOptions;
    foreach (arg; args)
    {
        if (endOfOptions || !arg.startsWith("--"))
        {
            result.addNonOptionArg(arg);
            continue;
        }
        const text = arg[2 .. $];
        const equals = text.indexOf('=');
        if (equals > -1)
        {
            if (equals == 0)
                throw new IllegalArgumentException("Invalid argument syntax: " ~ arg);
            result.addOptionArg(text[0 .. equals], text[equals + 1 .. $]);
        }
        else if (text.length)
            result.addOptionArg(text, null);
        else
            endOfOptions = true;
    }
    return result;
}

/// Whether any of the profile `expressions` (`prod`, `!dev`, `prod & cloud`, `(a | b) & !c`) matches the
/// profiles `accepted` reports as active. Throws `IllegalArgumentException` for a malformed expression.
bool matchesProfiles(scope const string[] expressions, scope bool delegate(string) @safe accepted)
{
    if (expressions.length == 0)
        throw new IllegalArgumentException("Must specify at least one profile expression");
    foreach (expression; expressions)
    {
        if (parseProfileExpression(expression).matches(accepted))
            return true;
    }
    return false;
}

/// A parsed profile expression.
final class ProfileExpression
{
    private enum Kind
    {
        name,
        not,
        and,
        or
    }

    private Kind kind;
    private string profile;
    private ProfileExpression[] operands;

    private this(Kind kind, string profile, ProfileExpression[] operands) pure nothrow
    {
        this.kind = kind;
        this.profile = profile;
        this.operands = operands;
    }

    /// Whether the expression holds for the profiles `accepted` reports.
    bool matches(scope bool delegate(string) @safe accepted) const
    {
        final switch (kind)
        {
        case Kind.name:
            return accepted(profile);
        case Kind.not:
            return !operands[0].matches(accepted);
        case Kind.and:
            foreach (operand; operands)
            {
                if (!operand.matches(accepted))
                    return false;
            }
            return true;
        case Kind.or:
            foreach (operand; operands)
            {
                if (operand.matches(accepted))
                    return true;
            }
            return false;
        }
    }
}

/// Parse one profile expression.
ProfileExpression parseProfileExpression(string expression) pure
{
    import std.string : strip;

    if (expression.strip.length == 0)
        throw new IllegalArgumentException("Invalid profile expression [" ~ expression ~ "]: must contain text");
    auto parser = ExpressionParser(expression, tokenize(expression));
    return parser.parse(Context.none);
}

private enum Context
{
    none,
    negate,
    parenthesis
}

private string[] tokenize(string expression) pure
{
    string[] tokens;
    size_t start;
    foreach (index, char ch; expression)
    {
        if (ch == '(' || ch == ')' || ch == '&' || ch == '|' || ch == '!')
        {
            if (index > start)
                tokens ~= expression[start .. index];
            tokens ~= expression[index .. index + 1];
            start = index + 1;
        }
    }
    if (start < expression.length)
        tokens ~= expression[start .. $];
    return tokens;
}

private struct ExpressionParser
{
    string expression;
    string[] tokens;
    size_t position;

    ProfileExpression parse(Context context) pure
    {
        import std.string : strip;

        ProfileExpression[] elements;
        char operator = 0;
        bool operandExpected = true;
        while (position < tokens.length)
        {
            const token = tokens[position++].strip;
            if (token.length == 0)
                continue;
            if (token == "&" || token == "|")
            {
                wellFormed(operator == token[0] || (operator == 0 && !operandExpected));
                operator = token[0];
                operandExpected = true;
                continue;
            }
            if (token == ")")
            {
                wellFormed(context == Context.parenthesis && !operandExpected);
                return merge(elements, operator);
            }
            wellFormed(operandExpected);
            auto operand = operandFor(token);
            if (context == Context.negate)
                return operand;
            elements ~= operand;
            operandExpected = false;
        }
        wellFormed(context != Context.parenthesis && !operandExpected);
        return merge(elements, operator);
    }

    ProfileExpression operandFor(string token) pure
    {
        import std.ascii : isWhite;
        import std.algorithm.searching : any;

        if (token == "(")
            return parse(Context.parenthesis);
        if (token == "!")
            return new ProfileExpression(ProfileExpression.Kind.not, null, [parse(Context.negate)]);
        wellFormed(!token.any!isWhite);
        return new ProfileExpression(ProfileExpression.Kind.name, token, null);
    }

    ProfileExpression merge(ProfileExpression[] elements, char operator) pure
    {
        wellFormed(elements.length > 0);
        if (elements.length == 1)
            return elements[0];
        return new ProfileExpression(operator == '&' ? ProfileExpression.Kind.and
                : ProfileExpression.Kind.or, null, elements);
    }

    void wellFormed(bool condition) const pure
    {
        if (!condition)
            throw new IllegalArgumentException("Malformed profile expression [" ~ expression ~ "]");
    }
}

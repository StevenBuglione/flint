/// Compile-time named-parameter SQL without lexical substitutions inside SQL literals.
module flint.engine.data.internal.queries;

import flint.engine.data.internal.schema : Columns, Field, Parameters, absent, identifierPart, initial;
import flint.engine.data.internal.sqlgen : placeholder, projection;
import flint.engine.data.types : Query;

@safe:

package(flint.engine.data) struct Plan
{
    string sql;
    uint[] order;
    string error;
}

package(flint.engine.data) template NamedQuery(Projection, Args)
{
    enum planned = compileQuery(queryText!Args(), Parameters!Args.fields[]);
    static assert(planned.error is null, Args.stringof ~ ": " ~ planned.error);
    enum sql = "SELECT " ~ projection(Columns!Projection.columns[],
                "_flint_query") ~ " FROM (\n" ~ planned.sql ~ "\n) AS \"_flint_query\" LIMIT 2";
    enum order = planned.order;
}

private string queryText(T)()
{
    string sql;
    size_t count;
    static foreach (attribute; __traits(getAttributes, T))
    {
        static if (is(typeof(attribute) == Query))
        {
            sql = attribute.sql;
            ++count;
        }
        else static if (is(attribute == Query))
            static assert(0, T.stringof ~ ": Query requires SQL text");
    }
    assert(count == 1, T.stringof ~ ": exactly one Query annotation is required");
    return sql;
}

private struct Parser
{
    string source;
    string expanded;
    uint[128] ordinal;
    uint[] order;
    size_t index;
    size_t copied;
    string error;

    void scan(scope const Field[] params)
    {
        while (index < source.length && error is null)
        {
            if (skipQuotedOrComment())
                continue;
            const ch = source[index];
            if (ch == ':')
                replaceParameter(params);
            else if (ch == ';')
                finishStatement();
            else if (ch == '?' || rawMarker())
                error = "use named :parameter placeholders";
            else
                ++index;
        }
        if (error is null)
        {
            if (order.length != params.length)
                error = "mapped parameter is unused: " ~ unused(params);
            else
                expanded ~= source[copied .. $];
        }
    }

    private bool rawMarker() const pure nothrow @nogc
    {
        if (index + 1 == source.length)
            return false;
        const next = source[index + 1];
        return (source[index] == '$' && next >= '0' && next <= '9') || (source[index] == '@' && initial(next));
    }

    private string unused(scope const Field[] params) const pure nothrow @nogc
    {
        foreach (number, ref const field; params)
        {
            if (!ordinal[number])
                return field.name;
        }
        return "";
    }

    private void replaceParameter(scope const Field[] params)
    {
        const begin = index++;
        if (index == source.length)
            return;
        if (source[index] == ':')
        {
            ++index;
            return;
        }
        if (!initial(source[index]))
        {
            if (identifierPart(source[index]))
                error = "invalid named SQL parameter";
            return;
        }
        const start = index;
        while (index < source.length && identifierPart(source[index]))
            ++index;
        const name = source[start .. index];
        const field = argument(params, name);
        if (field == absent)
        {
            error = "unknown SQL parameter: " ~ name;
            return;
        }
        if (!ordinal[field])
        {
            order ~= cast(uint) field;
            ordinal[field] = cast(uint) order.length;
        }
        expanded ~= source[copied .. begin] ~ placeholder(ordinal[field]);
        copied = index;
    }

    private void finishStatement()
    {
        size_t stop = index++;
        while (index < source.length && error is null)
        {
            const ch = source[index];
            if (whitespace(ch))
                ++index;
            else if (!skipComment())
            {
                error = "a Query annotation must contain one statement";
                return;
            }
        }
        if (error is null)
            source = source[0 .. stop];
    }

    private bool skipQuotedOrComment()
    {
        if (skipComment())
            return true;
        switch (source[index])
        {
        case '\'':
            skipQuote('\'', escapeString());
            return true;
        case '"':
            skipQuote('"', false);
            return true;
        case '\x60':
            skipQuote('\x60', false);
            return true;
        case '[':
            skipBracket();
            return true;
        case '$':
            return skipDollar();
        default:
            return false;
        }
    }

    private bool escapeString() const pure nothrow @nogc
    {
        if (index == 0 || (source[index - 1] != 'E' && source[index - 1] != 'e'))
            return false;
        return index == 1 || !identifierPart(source[index - 2]);
    }

    private void skipQuote(char quote, bool backslash)
    {
        ++index;
        while (index < source.length)
        {
            const ch = source[index++];
            if (backslash && ch == '\\' && index < source.length)
                ++index;
            else if (ch == quote)
            {
                if (index < source.length && source[index] == quote)
                    ++index;
                else
                    return;
            }
        }
        error = "unterminated SQL quote";
    }

    private void skipBracket()
    {
        ++index;
        while (index < source.length)
        {
            if (source[index++] == ']')
                return;
        }
        error = "unterminated quoted SQL identifier";
    }

    private bool skipDollar()
    {
        const begin = index;
        const end = dollarEnd(source, index);
        if (end == absent)
            return false;
        const tag = source[begin .. end];
        index = end;
        while (tag.length <= source.length - index)
        {
            if (source[index .. index + tag.length] == tag)
            {
                index += tag.length;
                return true;
            }
            ++index;
        }
        error = "unterminated dollar-quoted SQL literal";
        return true;
    }

    private bool skipComment()
    {
        if (index + 1 >= source.length)
            return false;
        const token = source[index .. index + 2];
        if (token == "--")
        {
            index += 2;
            while (index < source.length && source[index] != '\n' && source[index] != '\r')
                ++index;
            return true;
        }
        if (token != "/*")
            return false;
        skipBlock();
        return true;
    }

    private void skipBlock()
    {
        size_t depth = 1;
        index += 2;
        while (index + 1 < source.length)
        {
            const token = source[index .. index + 2];
            if (token == "/*")
            {
                ++depth;
                index += 2;
            }
            else if (token == "*/")
            {
                index += 2;
                if (--depth == 0)
                    return;
            }
            else
            {
                ++index;
            }
        }
        error = "unterminated SQL block comment";
    }
}

private bool whitespace(char value) pure nothrow @nogc
{
    return value == ' ' || (value >= '\t' && value <= '\r');
}

private size_t argument(scope const Field[] params, scope const(char)[] name) pure nothrow @nogc
{
    foreach (index, ref const field; params)
    {
        if (field.name == name)
            return index;
    }
    return absent;
}

private size_t dollarEnd(scope const(char)[] input, size_t index) pure nothrow @nogc
{
    ++index;
    if (index >= input.length)
        return absent;
    if (input[index] == '$')
        return index + 1;
    if (!initial(input[index]))
        return absent;
    while (++index < input.length && identifierPart(input[index]))
    {
    }
    return index < input.length && input[index] == '$' ? index + 1 : absent;
}

private Plan compileQuery(string sql, scope const Field[] params)
{
    if (sql.length == 0 || sql.length > 65_536)
        return Plan(null, null, "Query SQL length must be between 1 and 65,536 bytes");
    foreach (ch; sql)
    {
        if (ch == '\0')
            return Plan(null, null, "Query SQL contains a NUL byte");
    }
    Parser parser = Parser(sql);
    parser.scan(params);
    return Plan(parser.expanded, parser.order, parser.error);
}

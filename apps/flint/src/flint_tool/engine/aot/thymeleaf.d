/// Build-time lowering of the first Thymeleaf HTML text form to an engine-template resource.
module flint_tool.engine.aot.thymeleaf;

import flint_tool.diagnostics.report : positionOf;
import std.ascii : isAlpha, isDigit;
import std.utf : UTFException, validate;

@safe:

/// Cache version for generated resources produced by the Thymeleaf lowering.
enum thymeleafLoweringVersion = 1;

/// A source error in the input resource. The caller supplies its file path when reporting it.
struct ThymeleafError
{
    /// Flint diagnostic code.
    string code;
    /// Explanation of the rejected construct.
    string message;
    /// One-based source line.
    size_t line;
    /// One-based byte column on the source line.
    size_t column;
}

private enum maxSourceBytes = 1_048_576;

/// Lower a single div, p, or span with a th:text attribute, a bare model variable, and an old plain-text body.
/// For unsupported constructs, report the source location and leave `lowered` empty.
bool lowerThymeleaf(string source, out string lowered, out ThymeleafError error)
{
    Source input = Source(source);
    if (source.length > maxSourceBytes)
        return input.reject("template source exceeds 1 MiB", error);
    if (!validSource(source))
        return input.reject("template source must be UTF-8 without NUL", error);

    input.skipSpace();
    const start = input.cursor;
    string tag;
    string name;
    size_t closing;
    if (!input.readOpeningTag(tag, error) || !input.readTextValue(name, error)
            || !input.readClosingTag(tag, closing, error))
        return false;

    lowered = source[0 .. start] ~ "<" ~ tag ~ ">{{model." ~ name ~ "}}" ~ source[closing .. $];
    return true;
}

private bool validSource(string source) pure
{
    foreach (c; source)
        if (c == '\0')
            return false;
    try
        validate(source);
    catch (UTFException)
        return false;
    return true;
}

private struct Source
{
    string text;
    size_t cursor;

    bool readOpeningTag(out string tag, out ThymeleafError error)
    {
        if (!take("<"))
            return reject("expected an HTML element", error);
        const tagStart = cursor;
        tag = identifier();
        if (tag is null)
            return reject("expected an HTML element name", error);
        if (tag != "div" && tag != "p" && tag != "span")
        {
            cursor = tagStart;
            return reject("th:text is unsupported on <" ~ tag ~ ">", error);
        }

        const afterTag = cursor;
        skipSpace();
        if (afterTag == cursor || !take("th:text"))
            return reject("expected th:text", error);
        skipSpace();
        if (!take("="))
            return reject("expected = after th:text", error);
        return true;
    }

    bool readTextValue(out string name, out ThymeleafError error)
    {
        skipSpace();
        const quote = peek();
        if (quote != '"' && quote != '\'')
            return reject("expected a quoted th:text value", error);
        ++cursor;
        if (!take("${"))
            return reject("expected a model variable in th:text", error);
        name = identifier();
        if (name.length == 0 || !take("}") || peek() != quote)
            return reject("expected a bare model variable in th:text", error);
        ++cursor;
        skipSpace();
        if (!take(">"))
            return reject("additional attributes on th:text elements are unsupported", error);
        return true;
    }

    bool readClosingTag(string tag, out size_t closing, out ThymeleafError error)
    {
        while (cursor < text.length && peek() != '<')
            ++cursor;
        closing = cursor;
        if (!take("</") || !take(tag))
            return reject("expected the matching closing tag after plain text", error);
        skipSpace();
        if (!take(">"))
            return reject("expected the end of the closing tag", error);
        skipSpace();
        if (cursor != text.length)
            return reject("expected the end of the template", error);
        return true;
    }

    char peek() const pure nothrow @nogc
    {
        return cursor < text.length ? text[cursor] : '\0';
    }

    bool take(string token) pure nothrow @nogc
    {
        if (token.length > text.length - cursor || text[cursor .. cursor + token.length] != token)
            return false;
        cursor += token.length;
        return true;
    }

    void skipSpace() pure nothrow @nogc
    {
        for (auto c = peek(); c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f'; c = peek())
            ++cursor;
    }

    string identifier() pure nothrow @nogc
    {
        const start = cursor;
        if (!isAlpha(peek()) && peek() != '_')
            return null;
        ++cursor;
        for (auto c = peek(); isAlpha(c) || isDigit(c) || c == '_'; c = peek())
            ++cursor;
        return text[start .. cursor];
    }

    bool reject(string message, out ThymeleafError error) const
    {
        const position = positionOf(text, cursor);
        error = ThymeleafError("FLINT-E1160", message, cast(size_t) position.line, cast(size_t) position.column);
        return false;
    }
}

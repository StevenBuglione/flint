module flint.java.stringtokenizer_test;

import flint.engine.aot.any : Any;
import flint.java.lang : UnsupportedOperationException;
import flint.java.util : Iterator, NoSuchElementException;
import flint.java.util.enumeration : Enumeration;
import flint.java.util.stringtokenizer : StringTokenizer;

@safe:

private string[] drain(StringTokenizer tokens)
{
    import std.exception : collectException;

    string[] result;
    while (tokens.hasMoreTokens())
        result ~= tokens.nextToken();
    auto exhausted = collectException!NoSuchElementException(tokens.nextToken());
    assert(exhausted !is null && exhausted.getMessage() is null);
    return result;
}

@("StringTokenizer splits at the default whitespace set, including form feed but not vertical tab")
unittest
{
    assert(drain(new StringTokenizer("a\fb c\td\ne\rf  g\vh")) == [
        "a", "b", "c", "d", "e", "f", "g\vh"
    ]);
    assert(drain(new StringTokenizer("   ")).length == 0);
    assert(drain(new StringTokenizer("")).length == 0);
}

@("StringTokenizer optionally returns each delimiter as its own token")
unittest
{
    assert(drain(new StringTokenizer("a,,b;c;", ",;")) == ["a", "b", "c"]);
    assert(drain(new StringTokenizer("a,,b;c;", ",;", true)) == ["a", ",", ",", "b", ";", "c", ";"]);
    assert(new StringTokenizer("a,,b", ",", true).countTokens() == 4);
}

@("StringTokenizer matches supplementary delimiters as whole code points")
unittest
{
    assert(drain(new StringTokenizer("a\U0001F600b\U0001F600\U0001F600c", "\U0001F600")) == [
        "a", "b", "c"
    ]);
    assert(drain(new StringTokenizer("a\U0001F600b", "\U0001F600", true)) == [
        "a", "\U0001F600", "b"
    ]);
    assert(drain(new StringTokenizer("x,\U0001F601y\U0001F600z", ",\U0001F600")) == [
        "x", "\U0001F601y", "z"
    ]);
    assert(drain(new StringTokenizer("x\U0001F600y z", " ")) == ["x\U0001F600y", "z"]);
    assert(drain(new StringTokenizer("aéb中c", "é中")) == ["a", "b", "c"]);
}

@("StringTokenizer countTokens leaves the position unchanged")
unittest
{
    auto tokens = new StringTokenizer(" a  b c ", " ");
    assert(tokens.countTokens() == 3);
    assert(tokens.hasMoreTokens());
    assert(tokens.countTokens() == 3);
    assert(tokens.nextToken() == "a");
    assert(tokens.countTokens() == 2);
}

@("StringTokenizer rescans from the current position after the delimiters change")
unittest
{
    auto tokens = new StringTokenizer(" ,a b,c", " ");
    // The lookahead skipped the leading space; the new delimiter set must not reuse it.
    assert(tokens.hasMoreTokens());
    assert(tokens.nextToken(",") == " ");
    assert(tokens.nextToken() == "a b");
    assert(tokens.countTokens() == 1);

    auto switching = new StringTokenizer("a b,c d", " ");
    assert(switching.nextToken() == "a");
    assert(switching.nextToken(",") == " b");
    assert(switching.nextToken(" ") == ",c");
    assert(drain(switching) == ["d"]);
}

@("StringTokenizer treats a null string or delimiter set as empty (R26)")
unittest
{
    assert(drain(new StringTokenizer(null)).length == 0);
    assert(drain(new StringTokenizer("a b", null)) == ["a b"]);
    auto tokens = new StringTokenizer("a b,c", " ");
    assert(tokens.nextToken(null) == "a b,c");
}

@("StringTokenizer enumerates String tokens as Objects and adapts to an Iterator")
unittest
{
    import std.exception : collectException;

    Enumeration!Any elements = new StringTokenizer("p q");
    assert(elements.hasMoreElements());
    assert(elements.nextElement().get!string() == "p");

    Iterator!Any iterator = elements.asIterator();
    assert(iterator.hasNext());
    auto unsupported = collectException!UnsupportedOperationException(iterator.remove());
    assert(unsupported !is null && unsupported.getMessage() == "remove");
    assert(iterator.next() == Any.of("q"));
    assert(!iterator.hasNext());
    assert(collectException!NoSuchElementException(iterator.next()) !is null);
}

private final class Pushback : StringTokenizer
{
    private string pending;

    alias nextToken = StringTokenizer.nextToken;

    this(string text)
    {
        super(text, ",");
    }

    void pushBack(string token)
    {
        pending = token;
    }

    override bool hasMoreTokens()
    {
        return pending !is null || super.hasMoreTokens();
    }

    override string nextToken()
    {
        if (pending is null)
            return super.nextToken();
        auto token = pending;
        pending = null;
        return token;
    }
}

@("StringTokenizer subclasses override token retrieval, as Jackson's type parser does")
unittest
{
    StringTokenizer tokens = new Pushback("a,b");
    assert(tokens.nextToken() == "a");
    (cast(Pushback) tokens).pushBack("a");
    assert(tokens.hasMoreElements());
    assert(tokens.nextElement() == Any.of("a"));
    assert(tokens.nextToken() == "b");
    assert(!tokens.hasMoreTokens());
}

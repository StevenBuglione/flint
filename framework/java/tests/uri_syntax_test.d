module flint.java.test.uri_syntax;

import flint.java.lang : IllegalArgumentException;
import flint.java.net : URI;
import flint.java.net.urisyntaxexception : URISyntaxException;

@safe:

@("URI parses every hierarchical component")
unittest
{
    const uri = URI("http://user:pass@host:99/p?q#f");
    assert(uri.getScheme() == "http");
    assert(uri.isAbsolute() && !uri.isOpaque());
    assert(uri.getRawSchemeSpecificPart() == "//user:pass@host:99/p?q");
    assert(uri.getRawAuthority() == "user:pass@host:99");
    assert(uri.getRawUserInfo() == "user:pass");
    assert(uri.getHost() == "host");
    assert(uri.getPort() == 99);
    assert(uri.getRawPath() == "/p");
    assert(uri.getRawQuery() == "q");
    assert(uri.getRawFragment() == "f");
    assert(uri.toString() == "http://user:pass@host:99/p?q#f");

    const file = URI("file:///foo/bar");
    assert(!file.isOpaque());
    assert(file.getRawAuthority() is null);
    assert(file.getRawPath() == "/foo/bar");

    const opaque = URI("mailto:user@example.com");
    assert(opaque.getScheme() == "mailto");
    assert(opaque.isOpaque());
    assert(opaque.getRawSchemeSpecificPart() == "user@example.com");
    assert(opaque.getRawPath() is null);
}

@("URI parses bracketed IPv6 hosts and scoped addresses")
unittest
{
    const literal = URI("http://[::1]:8080/a");
    assert(literal.getHost() == "[::1]");
    assert(literal.getPort() == 8080);
    const scoped = URI("http://[fe80::1%25eth0]/");
    assert(scoped.getHost() == "[fe80::1%25eth0]");
    const registered = URI("//[::%eth0]/a");
    assert(registered.getHost() == "[::%eth0]");
    assert(registered.getRawPath() == "/a");
}

@("URI constructors quote components and reject a relative absolute path")
unittest
{
    assert(URI("http", "user", "host", 80, "/p", "q", "f").toString() == "http://user@host:80/p?q#f");
    assert(URI("http", "host", "/p", "f").toString() == "http://host/p#f");
    assert(URI("http", "user@host", "/p", "q", "f").toString() == "http://user@host/p?q#f");
    assert(URI("mailto", "user@example.com", null).toString() == "mailto:user@example.com");
    assert(URI("http", null, "host", -1, "/a b", null, null).toString() == "http://host/a%20b");

    bool threw;
    try
        URI("http", null, "host", -1, "relative", null, null);
    catch (URISyntaxException failure)
    {
        threw = true;
        assert(failure.getReason() == "Relative path in absolute URI");
        assert(failure.getIndex() == -1);
        assert(failure.getMessage() == "Relative path in absolute URI: http://hostrelative");
    }
    assert(threw);
}

@("URI.create wraps URISyntaxException in IllegalArgumentException")
unittest
{
    auto failure = uriFailure("//");
    assert(failure.getMessage() == "Expected authority at index 2: //");
    assert(failure.getInput() == "//");
    assert(failure.getReason() == "Expected authority");
    assert(failure.getIndex() == 2);

    bool wrappedRejected;
    try
        URI.create("//");
    catch (IllegalArgumentException wrapped)
    {
        wrappedRejected = true;
        assert(wrapped.getMessage() == "Expected authority at index 2: //");
        auto cause = cast(URISyntaxException) wrapped.getCause();
        assert(cause !is null && cause.getInput() == "//");
    }
    assert(wrappedRejected, "URI.create must reject a missing authority");
}

@("URI parser diagnostics match Java's reasons, indices and inputs")
unittest
{
    assert(uriFailure("a b").getMessage() == "Illegal character in path at index 1: a b");
    assert(uriFailure("http://ho st/").getMessage() == "Illegal character in authority at index 9: http://ho st/");
    assert(uriFailure("//[::%e-th0]/").getMessage() == "Illegal character in scope id at index 7: //[::%e-th0]/");
    const portMessage = uriFailure("//[::%eth0]:%61").getMessage();
    assert(portMessage == "Illegal character in port number at index 12: //[::%eth0]:%61");
    assert(uriFailure("http://host/a[b]").getMessage() == "Illegal character in path at index 13: http://host/a[b]");
}

@("URI equals, hashCode and compareTo follow Java's component rules")
unittest
{
    assert(URI("HTTP://A/b") == URI("http://a/b"));
    assert(URI("http://a/%7e") == URI("http://a/%7E"));
    assert(URI("http://a/%7e") != URI("http://a/%7f"));
    assert(URI("http://a:80/b") != URI("http://a/b"));
    assert(URI("mailto:a") == URI("MAILTO:a"));
    assert(URI("http://a/b") != URI("http://a/c"));

    assert(URI("HTTP://A/b").hashCode() == URI("http://a/b").hashCode());
    assert(URI("http://a/%7e").hashCode() == URI("http://a/%7E").hashCode());
    assert(URI("http://a/%7e").hashCode() != URI("http://a/%7f").hashCode());

    assert(URI("http://a/b").compareTo(URI("http://a/c")) < 0);
    assert(URI("http://a/c").compareTo(URI("http://a/b")) > 0);
    assert(URI("http://a/b").compareTo(URI("http://a/b")) == 0);
    assert(URI("http://a:80/b").compareTo(URI("http://a/b")) == 81);
}

@("URI resolves RFC 3986 references")
unittest
{
    const base = URI("http://a/b/c/d;p?q");
    assert(base.resolve(URI("g")).toString() == "http://a/b/c/g");
    assert(base.resolve(URI("./g")).toString() == "http://a/b/c/g");
    assert(base.resolve(URI("g/")).toString() == "http://a/b/c/g/");
    assert(base.resolve(URI("/g")).toString() == "http://a/g");
    assert(base.resolve(URI("//g")).toString() == "http://g");
    assert(base.resolve(URI("?y")).toString() == "http://a/b/c/?y");
    assert(base.resolve(URI("#s")).toString() == "http://a/b/c/d;p?q#s");
    assert(base.resolve(URI("g?y#s")).toString() == "http://a/b/c/g?y#s");
    assert(base.resolve(URI("")).toString() == "http://a/b/c/");
    assert(base.resolve(URI("..")).toString() == "http://a/b/");
    assert(base.resolve(URI("../../../g")).toString() == "http://a/../g");
    assert(base.resolve(URI("g/../h")).toString() == "http://a/b/c/h");
    assert(base.resolve(URI("http:g")).toString() == "http:g");
}

@("URI relativizes and normalizes paths")
unittest
{
    assert(URI("http://a/b/c/").relativize(URI("http://a/b/c/d")).toString() == "d");
    assert(URI("http://a/b/c/d").relativize(URI("http://a/b/c/e")).toString() == "http://a/b/c/e");
    assert(URI("http://a/b/c/d").relativize(URI("http://x/b/c/d")).toString() == "http://x/b/c/d");

    assert(URI("http://a/b/../c").normalize().toString() == "http://a/c");
    assert(URI("a/./b/../c").normalize().toString() == "a/c");
    assert(URI("http://a//b").normalize().toString() == "http://a/b");
}

@("URI.toASCIIString percent-encodes non-ASCII text")
unittest
{
    assert(URI("/日本%20語").toASCIIString() == "/%E6%97%A5%E6%9C%AC%20%E8%AA%9E");
    assert(URI("http://host/%7e").toASCIIString() == "http://host/%7e");
}

private URISyntaxException uriFailure(string input) pure
{
    try
        URI(input);
    catch (URISyntaxException failure)
        return failure;
    assert(false, "Expected a rejected URI");
}

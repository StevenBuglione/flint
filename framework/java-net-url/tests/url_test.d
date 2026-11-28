/// Original Flint tests for Java SE parsing-only URL and MalformedURLException.
module flint.java.net.url_test;

import flint.java.io : IOException;
import flint.java.net.malformedurlexception : MalformedURLException;
import flint.java.net.url : URL;
import std.exception : assertThrown, collectException;
import std.typecons : Nullable;

@safe:

private Nullable!string absent() pure nothrow @nogc
{
    return Nullable!string.init;
}

private Nullable!string present(string s) pure nothrow @nogc
{
    return Nullable!string(s);
}

@("MalformedURLException inherits IOException and preserves message")
unittest
{
    auto bare = new MalformedURLException();
    IOException asIo = bare;
    assert(asIo !is null);
    assert(bare.getMessage() is null);

    auto detailed = new MalformedURLException("unknown protocol: gopher");
    assert(detailed.getMessage() == "unknown protocol: gopher");
}

@("URL parses absolute hierarchical, IPv4, IPv6, and port forms matching OpenJDK 21")
unittest
{
    auto u = new URL("http://Example.test:80/a%2f?x=%2B#Frag");
    assert(u.getProtocol() == "http");
    assert(u.getAuthority() == present("Example.test:80"));
    assert(u.getUserInfo().isNull);
    assert(u.getHost() == present("Example.test"));
    assert(u.getPort() == 80);
    assert(u.getDefaultPort() == 80);
    assert(u.getPath() == "/a%2f");
    assert(u.getQuery() == present("x=%2B"));
    assert(u.getFile() == "/a%2f?x=%2B");
    assert(u.getRef() == present("Frag"));
    assert(u.toExternalForm() == "http://Example.test:80/a%2f?x=%2B#Frag");
    assert(u.toString() == u.toExternalForm());

    auto raw = new URL("http://u%40ser:p%3Ass@h:0080/a%2Fb?x=%3F");
    assert(raw.getAuthority() == present("u%40ser:p%3Ass@h:0080"));
    assert(raw.getUserInfo() == present("u%40ser:p%3Ass"));
    assert(raw.getHost() == present("h"));
    assert(raw.getPort() == 80);
    assert(raw.getPath() == "/a%2Fb");
    assert(raw.getQuery() == present("x=%3F"));
    assert(raw.getRef().isNull);

    auto v6 = new URL("http://[2001:DB8::1]:8080/a?q");
    assert(v6.getAuthority() == present("[2001:DB8::1]:8080"));
    assert(v6.getHost() == present("[2001:DB8::1]"));
    assert(v6.getPort() == 8080);

    auto v6Scope = new URL("http://[fe80::1%en0]/a");
    assert(v6Scope.getHost() == present("[fe80::1%en0]"));
    assert(v6Scope.getPort() == -1);

    auto emptyPort = new URL("http://h:/a");
    assert(emptyPort.getAuthority() == present("h:"));
    assert(emptyPort.getHost() == present("h"));
    assert(emptyPort.getPort() == -1);
    assert(emptyPort.toExternalForm() == "http://h:/a");

    auto negOne = new URL("http://h:-1/a");
    assert(negOne.getPort() == -1);
    assert(negOne.toExternalForm() == "http://h:-1/a");

    auto largePort = new URL("http://h:65536/a");
    assert(largePort.getPort() == 65_536);

    auto multiAt = new URL("http://u@v@h/a");
    assert(multiAt.getAuthority() == present("u@v@h"));
    assert(multiAt.getUserInfo().isNull);
    assert(multiAt.getHost() == present(""));
    assert(multiAt.getPort() == -1);
}

@("URL distinguishes absent and empty authority, query, and fragment")
unittest
{
    auto noAuth = new URL("http:/path");
    assert(noAuth.getAuthority().isNull);
    assert(noAuth.getHost() == present(""));
    assert(noAuth.getPath() == "/path");
    assert(noAuth.toExternalForm() == "http:/path");

    auto emptyAuth = new URL("http:///path");
    assert(emptyAuth.getAuthority() == present(""));
    assert(emptyAuth.getHost() == present(""));
    assert(emptyAuth.getPath() == "/path");
    assert(emptyAuth.toExternalForm() == "http:/path");

    auto noPath = new URL("http://h");
    assert(noPath.getPath() == "");
    assert(noPath.getFile() == "");
    assert(noPath.getQuery().isNull);
    assert(noPath.getRef().isNull);

    auto emptyQuery = new URL("http://h/a?");
    assert(emptyQuery.getQuery() == present(""));
    assert(emptyQuery.getFile() == "/a?");
    assert(emptyQuery.toExternalForm() == "http://h/a?");

    auto emptyRef = new URL("http://h/a#");
    assert(emptyRef.getRef() == present(""));
    assert(emptyRef.toExternalForm() == "http://h/a#");

    auto ws = new URL("  http://h/a  ");
    assert(ws.toExternalForm() == "http://h/a");

    auto legacy = new URL("url:http://h/a");
    assert(legacy.toExternalForm() == "http://h/a");

    auto schemeCase = new URL("HTTPS://EXAMPLE.TEST/path");
    assert(schemeCase.getProtocol() == "https");
    assert(schemeCase.getHost() == present("EXAMPLE.TEST"));
    assert(schemeCase.getDefaultPort() == 443);

    auto nonStrict = new URL("http://h/%q0");
    assert(nonStrict.getPath() == "/%q0");
    auto spacePath = new URL("http://h/a b");
    assert(spacePath.getPath() == "/a b");
}

@("URL supports built-in file, ftp, jar, mailto, jmod, and jrt protocols")
unittest
{
    auto plainFile = new URL("file:/path/a");
    assert(plainFile.getAuthority().isNull);
    assert(plainFile.getHost() == present(""));
    assert(plainFile.getDefaultPort() == -1);
    assert(plainFile.toExternalForm() == "file:/path/a");

    auto emptyFileAuth = new URL("file:///path/a");
    assert(emptyFileAuth.getAuthority() == present(""));
    assert(emptyFileAuth.toExternalForm() == "file:/path/a");

    auto fileHost = new URL("file://example.test/path");
    assert(fileHost.getAuthority() == present("example.test"));
    assert(fileHost.getHost() == present("example.test"));
    assert(fileHost.toExternalForm() == "file://example.test/path");

    auto ftp = new URL("ftp://ftp.example.test/path");
    assert(ftp.getDefaultPort() == 21);

    auto jar = new URL("jar:file:/path/lib.jar!/inside.txt");
    assert(jar.getProtocol() == "jar");
    assert(jar.getAuthority().isNull);
    assert(jar.getHost() == present(""));
    assert(jar.getPath() == "file:/path/lib.jar!/inside.txt");
    assert(jar.toExternalForm() == "jar:file:/path/lib.jar!/inside.txt");

    auto jarRel = new URL(jar, "dir/../other.txt#sec");
    assert(jarRel.getPath() == "file:/path/lib.jar!/other.txt");
    assert(jarRel.getRef() == present("sec"));

    auto jarRoot = new URL(jar, "/top.txt");
    assert(jarRoot.getPath() == "file:/path/lib.jar!/top.txt");

    auto mail = new URL("mailto:user@example.test");
    assert(mail.getProtocol() == "mailto");
    assert(mail.getFile() == "user@example.test");
    assertThrown!MalformedURLException(new URL("mailto:   "));

    auto jrt = new URL("jrt:/java.base/java/lang/Object.class");
    assert(jrt.getProtocol() == "jrt");
    assert(jrt.getDefaultPort() == -1);
}

@("URL resolves relative references against a context matching OpenJDK 21")
unittest
{
    auto fullBase = new URL("http://h/dir/base?old#ref");

    auto qOnly = new URL(fullBase, "?new");
    assert(qOnly.getPath() == "/dir/");
    assert(qOnly.getQuery() == present("new"));
    assert(qOnly.getFile() == "/dir/?new");
    assert(qOnly.getRef().isNull);

    auto fOnly = new URL(fullBase, "#new");
    assert(fOnly.getPath() == "/dir/base");
    assert(fOnly.getQuery() == present("old"));
    assert(fOnly.getRef() == present("new"));

    auto emptyRef = new URL(fullBase, "");
    assert(emptyRef.getPath() == "/dir/base");
    assert(emptyRef.getQuery() == present("old"));
    assert(emptyRef.getRef() == present("ref"));

    auto parentRel = new URL(fullBase, "../next");
    assert(parentRel.getPath() == "/next");
    assert(parentRel.getQuery().isNull);
    assert(parentRel.getRef().isNull);

    auto base = new URL("http://h/dir/base");
    assert((new URL(base, "./next")).getPath() == "/dir/next");
    assert((new URL(base, "/next")).getPath() == "/next");
    assert((new URL(base, "//other/next")).toExternalForm() == "http://other/next");
    assert((new URL(base, "http:next")).getPath() == "/dir/next");
    assert((new URL(base, "https:next")).toExternalForm() == "https:next");
    assert((new URL(base, "%2E%2E/next")).getPath() == "/dir/%2E%2E/next");
}

@("URL rejects malformed specs with OpenJDK diagnostics")
unittest
{
    auto neg = collectException!MalformedURLException(new URL("http://h:-2/a"));
    assert(neg !is null && neg.getMessage() == "Invalid port number :-2");

    auto nonNum = collectException!MalformedURLException(new URL("http://h:abc/a"));
    assert(nonNum !is null && nonNum.getMessage() == `Error at index 0 in: "abc"`);

    auto unclosed = collectException!MalformedURLException(new URL("http://[::1/a"));
    assert(unclosed !is null && unclosed.getMessage() == "Invalid authority field: [::1");

    auto noProto = collectException!MalformedURLException(new URL("relative/path"));
    assert(noProto !is null && noProto.getMessage() == "no protocol: relative/path");

    auto unknown = collectException!MalformedURLException(new URL("gopher://host/path"));
    assert(unknown !is null && unknown.getMessage() == "unknown protocol: gopher");

    assertThrown!MalformedURLException(new URL("jar:file:/a.jar"));
    assertThrown!MalformedURLException(new URL("jar:jar:file:/a.jar!/b!/c"));
    assertThrown!MalformedURLException(new URL("http://bad host/a"));

    // R26: null spec counts as empty.
    const string nullSpec = null;
    auto fromNull = collectException!MalformedURLException(new URL(nullSpec));
    assert(fromNull !is null && fromNull.getMessage() == "no protocol: ");
}

@("URL component constructors and D-NET-1 equality, sameFile, and hashCode")
unittest
{
    auto u1 = new URL("HTTP", "Example.TEST", 80, "/a/b?q=1#frag");
    assert(u1.getProtocol() == "http");
    assert(u1.getHost() == present("Example.TEST"));
    assert(u1.getPort() == 80);
    assert(u1.getAuthority() == present("Example.TEST:80"));
    assert(u1.getPath() == "/a/b");
    assert(u1.getQuery() == present("q=1"));
    assert(u1.getRef() == present("frag"));

    auto u2 = new URL("http", "example.test", "/a/b?q=1#frag");
    assert(u1.equals(u2));
    assert(u1 == u2);
    assert(u1.hashCode() == u2.hashCode());
    assert(u1.toHash() == u2.toHash());
    assert(u1.sameFile(u2));

    auto u3 = new URL("http", "example.test", "/a/b?q=1#other");
    assert(!u1.equals(u3));
    assert(u1 != u3);
    assert(u1.sameFile(u3));

    auto v6Bare = new URL("http", "2001:db8::1", 8080, "/x");
    assert(v6Bare.getHost() == present("[2001:db8::1]"));
    assert(v6Bare.getAuthority() == present("[2001:db8::1]:8080"));

    auto nullHost = new URL("http", absent(), -1, "/only");
    assert(nullHost.getHost().isNull);
    assert(nullHost.getAuthority().isNull);

    // file: empty host equals localhost without DNS (D-NET-1 + OpenJDK file.Handler).
    auto fileEmpty = new URL("file:///tmp/a");
    auto fileLocal = new URL("file://localhost/tmp/a");
    assert(fileEmpty.equals(fileLocal));
    assert(fileEmpty.sameFile(fileLocal));
    assert(fileEmpty.hashCode() == fileLocal.hashCode());

    // ftp: userInfo participates in equals (OpenJDK ftp.Handler).
    auto ftp1 = new URL("ftp://alice@example.test/a");
    auto ftp2 = new URL("ftp://bob@example.test/a");
    assert(!ftp1.equals(ftp2));
    assert(ftp1.sameFile(ftp2));

    // jar: compares enclosed URLs and entries.
    auto jar1 = new URL("jar:http://EXAMPLE.TEST:80/a.jar!/x.txt");
    auto jar2 = new URL("jar:http://example.test/a.jar!/x.txt");
    assert(jar1.equals(jar2));
    assert(jar1.sameFile(jar2));
    assert(jar1.hashCode() == jar2.hashCode());

    assert(!u1.equals(null));
    assert(!u1.sameFile(null));
}

@("URL.toURI returns a URI and applies OpenJDK 21 syntax validation")
unittest
{
    import flint.java.net : URI;
    import flint.java.net.urisyntaxexception : URISyntaxException;

    auto u = new URL("http://Example.test:80/a%2f?x=%2B#Frag");
    URI uri = u.toURI();
    assert(uri.toString() == "http://Example.test:80/a%2f?x=%2B#Frag");
    assert(uri.getScheme() == "http");
    assert(uri.getAuthority() == "Example.test:80");
    assert(uri.getRawPath() == "/a%2f");
    assert(uri.getPath() == "/a/");

    // file: an empty or null authority collapses to file:/... (OpenJDK file.Handler).
    assert((new URL("file:///tmp/x")).toURI().toString() == "file:/tmp/x");
    assert((new URL("file", absent(), -1, "/tmp/x")).toURI().toString() == "file:/tmp/x");

    // IPv6 with a scope id, and non-ASCII authority/path, are legal URI characters.
    assert((new URL("http://[fe80::1%25eth0]/x")).toURI().toString() == "http://[fe80::1%25eth0]/x");
    assert((new URL("http://\u00fcnicode.com/x")).toURI().toString() == "http://\u00fcnicode.com/x");

    // An illegal path character raises URISyntaxException with Java's reason and index.
    auto badPath = collectException!URISyntaxException((new URL("http://h/a b")).toURI());
    assert(badPath !is null);
    assert(badPath.getInput() == "http://h/a b");
    assert(badPath.getReason() == "Illegal character in path");
    assert(badPath.getIndex() == 10);

    // A malformed percent escape is rejected by the URI parser, not the authority scan.
    auto badEscape = collectException!URISyntaxException((new URL("http://h/%zz")).toURI());
    assert(badEscape !is null);
    assert(badEscape.getReason() == "Malformed escape pair");
    assert(badEscape.getIndex() == 9);
}

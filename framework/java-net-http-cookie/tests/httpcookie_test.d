// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.httpcookie_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.net.httpcookie : HttpCookie;
import std.typecons : Nullable;

@safe:

private void assertThrowsIllegal(scope void delegate() @safe fn, string expectedMessage)
{
    bool threw;
    try
    {
        fn();
    }
    catch (IllegalArgumentException e)
    {
        threw = true;
        assert(e.getMessage() == expectedMessage, "Expected '" ~ expectedMessage ~ "', got '" ~ e.getMessage() ~ "'");
    }
    assert(threw, "Expected IllegalArgumentException: " ~ expectedMessage);
}

unittest
{
    // Basic construction, trimming, absent vs empty value, and toString.
    auto c = new HttpCookie(" session ", "value");
    assert(c.getName() == "session");
    assert(!c.getValue().isNull && c.getValue().get == "value");
    assert(c.getVersion() == 1);
    assert(c.getMaxAge() == -1);
    assert(!c.hasExpired());
    assert(!c.getSecure());
    assert(!c.isHttpOnly());
    assert(!c.getDiscard());
    assert(c.getDomain().isNull);
    assert(c.getPath().isNull);
    assert(c.getPortlist().isNull);
    assert(c.getComment().isNull);
    assert(c.getCommentURL().isNull);
    assert(c.toString() == `session="value"`);

    auto nullVal = new HttpCookie("session", null);
    assert(nullVal.getValue().isNull);
    assert(nullVal.toString() == `session="null"`);

    auto emptyVal = new HttpCookie("session", "");
    assert(!emptyVal.getValue().isNull && emptyVal.getValue().get == "");
    assert(emptyVal.toString() == `session=""`);

    // Cookie named "domain" is accepted in Java 21.
    auto domainNamed = new HttpCookie("domain", "value");
    assert(domainNamed.getName() == "domain");
    assert(domainNamed.toString() == `domain="value"`);

    // Illegal cookie names (covers IllegalCookieNameTest behavior).
    assertThrowsIllegal(() { new HttpCookie("", "v"); }, "Illegal cookie name");
    assertThrowsIllegal(() { new HttpCookie("   ", "v"); }, "Illegal cookie name");
    assertThrowsIllegal(() { new HttpCookie("ses sion", "v"); }, "Illegal cookie name");
    assertThrowsIllegal(() { new HttpCookie("session;", "v"); }, "Illegal cookie name");
    assertThrowsIllegal(() { new HttpCookie("session,", "v"); }, "Illegal cookie name");
    assertThrowsIllegal(() { new HttpCookie("$session", "v"); }, "Illegal cookie name");
    assertThrowsIllegal(() { new HttpCookie("café", "v"); }, "Illegal cookie name");
    assertThrowsIllegal(() { new HttpCookie("a\x1fb", "v"); }, "Illegal cookie name");
    assertThrowsIllegal(() { new HttpCookie("a\x7fb", "v"); }, "Illegal cookie name");
    // R26: null string counts as empty, raising IllegalArgumentException.
    assertThrowsIllegal(() { new HttpCookie(null, "v"); }, "Illegal cookie name");
}

unittest
{
    // Parse single and multi-cookie headers, version guessing, duplicates, expiry, and errors.
    auto bare = HttpCookie.parse("session=value");
    assert(bare.size() == 1);
    assert(bare.get(0).getName() == "session");
    assert(bare.get(0).getValue().get == "value");
    assert(bare.get(0).getVersion() == 0);
    assert(bare.get(0).toString() == "session=value");

    auto sc = HttpCookie.parse("Set-Cookie: session=value; PaTh=/web; Domain=EXAMPLE.COM; Secure; HttpOnly");
    assert(sc.size() == 1);
    assert(sc.get(0).getDomain().get == "example.com");
    assert(sc.get(0).getPath().get == "/web");
    assert(sc.get(0).getSecure());
    assert(sc.get(0).isHttpOnly());
    assert(sc.get(0).getVersion() == 0);

    auto sc2 = HttpCookie.parse(`Set-Cookie2: one="first,part"; Version=1, two=2; Version=1`);
    assert(sc2.size() == 2);
    assert(sc2.get(0).getName() == "one");
    assert(sc2.get(0).getValue().get == "first,part");
    assert(sc2.get(1).getName() == "two");
    assert(sc2.get(1).getValue().get == "2");

    // Version=0 inside header still triggers version=1 in guessCookieVersion.
    auto v0 = HttpCookie.parse("session=value; Version=0");
    assert(v0.get(0).getVersion() == 1);
    assert(v0.get(0).toString() == `session="value"`);

    // All RFC 2965 attributes.
    auto all = HttpCookie.parse(`session="value"; Version=1; Max-Age=600; Path=/web; Domain=.EXAMPLE.COM; `
            ~ `Port="80,443"; Secure; HttpOnly; Discard; Comment="sample"; CommentURL="example.invalid"`);
    auto a0 = all.get(0);
    assert(a0.getMaxAge() == 600 && !a0.hasExpired());
    assert(a0.getDomain().get == ".example.com");
    assert(a0.getPath().get == "/web");
    assert(a0.getPortlist().get == "80,443");
    assert(a0.getSecure() && a0.isHttpOnly() && a0.getDiscard());
    assert(a0.getComment().get == "sample");
    assert(a0.getCommentURL().get == "example.invalid");
    assert(a0.toString() == `session="value";$Path="/web";$Domain=".example.com";$Port="80,443"`);

    // Duplicate attributes: first wins.
    auto dup = HttpCookie.parse("session=value; Path=/first; Path=/second; "
            ~ "Domain=FIRST.EXAMPLE; Domain=second.example; Max-Age=0; Max-Age=600");
    assert(dup.get(0).getPath().get == "/first");
    assert(dup.get(0).getDomain().get == "first.example");
    assert(dup.get(0).getMaxAge() == 0 && dup.get(0).hasExpired());

    // Negative Max-Age stays unexpired (covers CookieNegativeMaxAge).
    auto neg = HttpCookie.parse("session=value; Max-Age=-5");
    assert(neg.get(0).getMaxAge() == -5);
    assert(!neg.get(0).hasExpired());
    neg.get(0).setMaxAge(-100);
    assert(!neg.get(0).hasExpired());

    // ExpiredCookieTest coverage: past date -> 0 & expired; first expiry attribute wins; future date -> >0 & unexpired.
    auto past = HttpCookie.parse("session=value; Expires=Thu, 01 Jan 1970 00:00:00 GMT");
    assert(past.get(0).getMaxAge() == 0 && past.get(0).hasExpired());

    auto before = HttpCookie.parse("session=value; Max-Age=600; Expires=Thu, 01 Jan 1970 00:00:00 GMT");
    assert(before.get(0).getMaxAge() == 600 && !before.get(0).hasExpired());

    auto after = HttpCookie.parse("session=value; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=600");
    assert(after.get(0).getMaxAge() == 0 && after.get(0).hasExpired());

    auto future = HttpCookie.parse("session=value; Expires=Thu, 01 Jan 2099 00:00:00 GMT");
    assert(future.get(0).getMaxAge() > 0 && !future.get(0).hasExpired());

    // Wrong weekday fails strict SimpleDateFormat parsing -> delta 0 (expired).
    auto badDow = HttpCookie.parse("session=value; Expires=Fri, 01 Jan 2099 00:00:00 GMT");
    assert(badDow.get(0).getMaxAge() == 0 && badDow.get(0).hasExpired());

    // Port without '=' sets empty portlist, distinct from absent.
    auto emptyPort = HttpCookie.parse("session=value; Version=1; Port");
    assert(!emptyPort.get(0).getPortlist().isNull && emptyPort.get(0).getPortlist().get == "");
    assert(emptyPort.get(0).toString() == `session="value";$Port=""`);

    // Quoted semicolon follows StringTokenizer semantics.
    auto qsemi = HttpCookie.parse(`session="left;right"; Comment="left;right"`);
    assert(qsemi.get(0).getValue().get == `"left`);
    assert(qsemi.get(0).getComment().get == `"left`);

    // Parse errors.
    assertThrowsIllegal(() { HttpCookie.parse("session=value; Max-Age=invalid"); }, "Illegal cookie max-age attribute");
    assertThrowsIllegal(() { HttpCookie.parse(""); }, "Empty cookie header string");
    assertThrowsIllegal(() { HttpCookie.parse(null); }, "Empty cookie header string");
    assertThrowsIllegal(() { HttpCookie.parse("session; Path=/web"); }, "Invalid cookie name-value pair");
}

unittest
{
    // Equality, exact Java hashCode, clone independence, setVersion validation, and domainMatches.
    HttpCookie makeCookie(string name, string value, Nullable!string domain, Nullable!string path)
    {
        auto c = new HttpCookie(name, value);
        c.setDomain(domain);
        c.setPath(path);
        return c;
    }

    auto orig = makeCookie("Session", "original", Nullable!string("EXAMPLE.COM"), Nullable!string("/Web"));
    auto same = makeCookie("session", "different", Nullable!string("example.com"), Nullable!string("/Web"));
    auto diffPath = makeCookie("session", "different", Nullable!string("example.com"), Nullable!string("/web"));
    auto diffDom = makeCookie("session", "original", Nullable!string("other.example"), Nullable!string("/Web"));
    auto nullPropsA = makeCookie("n", "a", Nullable!string.init, Nullable!string.init);
    auto nullPropsB = makeCookie("N", "b", Nullable!string.init, Nullable!string.init);

    assert(orig.equals(same) && same.equals(orig) && orig == same);
    assert(orig.hashCode() == 42_461_752 && same.hashCode() == 42_461_752);
    assert(!orig.equals(diffPath) && diffPath.hashCode() == 42_492_504);
    assert(!orig.equals(diffDom) && diffDom.hashCode() == -1_649_622_073);
    assert(nullPropsA.equals(nullPropsB) && nullPropsA.hashCode() == 110);

    // Null vs empty domain/path are distinct in equals.
    auto emptyPath = makeCookie("n", "a", Nullable!string.init, Nullable!string(""));
    assert(!nullPropsA.equals(emptyPath));

    auto copy = orig.clone();
    assert(copy !is orig);
    assert(copy.equals(orig) && copy.hashCode() == orig.hashCode());
    copy.setValue("replacement");
    assert(orig.getValue().get == "original");
    assert(copy.getValue().get == "replacement");

    assertThrowsIllegal(() { copy.setVersion(2); }, "cookie version should be 0 or 1");
    assertThrowsIllegal(() { copy.setVersion(-1); }, "cookie version should be 0 or 1");

    // domainMatches parity.
    assert(HttpCookie.domainMatches("example.com", "EXAMPLE.COM"));
    assert(HttpCookie.domainMatches(".example.com", "one.example.com"));
    assert(HttpCookie.domainMatches(".example.com", "example.com"));
    assert(!HttpCookie.domainMatches(".example.com", "two.one.example.com"));
    assert(!HttpCookie.domainMatches("example.com", "one.example.com"));
    assert(!HttpCookie.domainMatches(".example.com", "notexample.com"));
    assert(HttpCookie.domainMatches(".local", "localhost"));
    assert(!HttpCookie.domainMatches("localhost", "localhost"));
    assert(HttpCookie.domainMatches("127.0.0.1", "127.0.0.1"));
    assert(!HttpCookie.domainMatches(null, "example.com"));
    assert(!HttpCookie.domainMatches("example.com", null));
}

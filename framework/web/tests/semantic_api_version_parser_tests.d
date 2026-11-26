/++
Ported from spring-projects/spring-framework v7.1.0, spring-web/src/test/java/org/springframework/web/accept/SemanticApiVersionParserTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook.
+/
module flint.web.semantic_api_version_parser_tests;

import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException, NumberFormatException;
import flint.web.accept : ApiVersionParser, SemanticApiVersionParser;
import std.exception : assertThrown, collectException;

@safe:

@("parse")
unittest
{
    alias Version = SemanticApiVersionParser.Version;
    ApiVersionParser!Version parser = new SemanticApiVersionParser();
    static assert(!__traits(compiles, ApiVersionParser!string));
    void check(string input, int major, int minor, int patch)
    {
        Version parsed = parser.parseVersion(input);
        assert(parsed.getMajor() == major);
        assert(parsed.getMinor() == minor);
        assert(parsed.getPatch() == patch);
    }

    check("0", 0, 0, 0);
    check("0.3", 0, 3, 0);
    check("4.5", 4, 5, 0);
    check("6.7.8", 6, 7, 8);
    check("v01", 1, 0, 0);
    check("version-1.2", 1, 2, 0);
}

@("parseInvalid")
unittest
{
    auto parser = new SemanticApiVersionParser();
    foreach (input; ["", "v", "1a", "1.0a", "1.0.0a", "1.0.0.", "1.0.0-"])
    {
        auto error = collectException!IllegalStateException(parser.parseVersion(input));
        assert(error !is null && error.msg == "Invalid API version format");
    }
}

@("Flint.SemanticApiVersionParser.validates format before integer conversion")
unittest
{
    auto parser = new SemanticApiVersionParser();
    auto error = collectException!IllegalArgumentException(parser.parseVersion(null));
    assert(error !is null && error.msg == "'version' is required");
    assertThrown!NumberFormatException(parser.parseVersion("2147483648"));
    assertThrown!IllegalStateException(parser.parseVersion("2147483648.1."));
    assertThrown!IllegalStateException(parser.parseVersion("1.0.0.0"));
    assertThrown!IllegalStateException(parser.parseVersion("1..2"));
    assertThrown!IllegalStateException(parser.parseVersion("1\n"));
    assert(parser.parseVersion("1.2147483647.2").getMinor() == int.max);
}

@("Flint.SemanticApiVersionParser.scans UTF-16 units before applying the ASCII grammar")
unittest
{
    auto parser = new SemanticApiVersionParser();
    assertThrown!IllegalStateException(parser.parseVersion("v\u06611.2"));
    assert(parser.parseVersion("v\U0001D7D91.2").toString() == "1.2.0");
    assert(parser.parseVersion("版本2.03").toString() == "2.3.0");
}

@("Flint.SemanticApiVersionParser.Version has normalized value semantics")
unittest
{
    auto parser = new SemanticApiVersionParser();
    auto parsed = parser.parseVersion("01.2");
    auto same = parser.parseVersion("v1.2.00");
    assert(parsed == same);
    assert(parsed.hashCode() == 1023);
    assert(parsed.hashCode() == same.hashCode());
    assert(parsed.toString() == "1.2.0");
    assert(parsed.compareTo(same) == 0);
    assert(parsed < parser.parseVersion("1.2.1"));
    assert(parsed < parser.parseVersion("1.10"));
    assert(parsed > parser.parseVersion("0.20.3"));
    assertThrown!NullPointerException(parsed.compareTo(null));
    assert(!parsed.equals(null));
    assert(!parsed.equals(new Object()));
}

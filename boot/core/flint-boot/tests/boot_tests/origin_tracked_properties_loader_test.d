// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/env/OriginTrackedPropertiesLoaderTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test.
// Excluded: compareToJavaProperties (compares against java.util.Properties, which has no Flint counterpart).
module boot_tests.origin_tracked_properties_loader_test;

import boot_tests.support : assertThrows;
import flint.boot.env : Document, OriginTrackedPropertiesLoader;
import flint.java.lang : IllegalStateException;
import flint.boot.origin : OriginTrackedValue, TextResourceOrigin;

@safe:

private Document[] documents()
{
    import std.file : read;

    auto bytes = cast(const(ubyte)[]) read("tests/resources/test-properties.properties");
    return new OriginTrackedPropertiesLoader("class path resource [test-properties.properties]", bytes).load();
}

private OriginTrackedValue getFromFirst(string key)
{
    return documents()[0].get(key);
}

private string value(OriginTrackedValue tracked)
{
    return tracked is null ? null : tracked.getValue();
}

private string location(OriginTrackedValue tracked)
{
    assert(tracked !is null);
    auto origin = cast(TextResourceOrigin) tracked.getOrigin();
    assert(origin !is null);
    return origin.getLocation().toString();
}

private Document[] loadText(string content)
{
    return new OriginTrackedPropertiesLoader("byte array resource", cast(const(ubyte)[]) content).load();
}

private void check(string key, string expected, string expectedLocation)
{
    auto tracked = getFromFirst(key);
    assert(value(tracked) == expected, key ~ ": " ~ value(tracked));
    assert(location(tracked) == expectedLocation, key ~ ": " ~ location(tracked));
}

@("getSimpleProperty") unittest
{
    check("test", "properties", "11:6");
}

@("getSimplePropertyWithColonSeparator") unittest
{
    check("test-colon-separator", "my-property", "15:23");
}

@("getPropertyWithSeparatorSurroundedBySpaces") unittest
{
    check("blah", "hello world", "2:12");
}

@("getUnicodeProperty") unittest
{
    check("test-unicode", "properties&test", "12:14");
}

@("getMalformedUnicodeProperty") unittest
{
    assertThrows!IllegalStateException(() {
        loadText("test-malformed-unicode=properties\\u(026test");
    }, "Malformed \\uxxxx encoding");
}

@("shouldRespectEncoding") unittest
{
    auto loaded = new OriginTrackedPropertiesLoader("utf-8.properties", cast(const(ubyte)[]) "smiley=😃").load(
            "UTF-8");
    assert(loaded[0].get("smiley") !is null);
    assert(loaded[0].get("smiley").getValue() == "😃");
}

@("getEscapedProperty") unittest
{
    check("test=property", "helloworld", "14:15");
}

@("getPropertyWithTab") unittest
{
    check("test-tab-property", "foo\tbar", "16:19");
}

@("getPropertyWithBang") unittest
{
    check("test-bang-property", "foo!", "34:20");
}

@("getPropertyWithValueComment") unittest
{
    check("test-property-value-comment", "foo !bar #foo", "36:29");
}

@("getPropertyWithMultilineImmediateBang") unittest
{
    check("test-multiline-immediate-bang", "!foo", "39:1");
}

@("getPropertyWithCarriageReturn") unittest
{
    check("test-return-property", "foo\rbar", "17:22");
}

@("getPropertyWithNewLine") unittest
{
    check("test-newline-property", "foo\nbar", "18:23");
}

@("getPropertyWithFormFeed") unittest
{
    check("test-form-feed-property", "foo\fbar", "19:25");
}

@("getPropertyWithWhiteSpace") unittest
{
    check("test-whitespace-property", "foo   bar", "20:32");
}

@("getCommentedOutPropertyShouldBeNull") unittest
{
    assert(getFromFirst("commented-property") is null);
    assert(getFromFirst("#commented-property") is null);
    assert(getFromFirst("commented-two") is null);
    assert(getFromFirst("!commented-two") is null);
}

@("getPropertyWithEscapedCommentPrefixCharacter") unittest
{
    auto loaded = loadText("\\#hash-prefixed=hash\n\\!bang-prefixed=bang");
    assert(loaded.length == 1);
    assert(loaded[0].keys == ["#hash-prefixed", "!bang-prefixed"]);
    assert(value(loaded[0].get("#hash-prefixed")) == "hash");
    assert(value(loaded[0].get("!bang-prefixed")) == "bang");
}

@("getMultiline") unittest
{
    check("test-multiline", "ab\\c", "21:17");
}

@("getImmediateMultiline") unittest
{
    check("test-multiline-immediate", "foo", "32:1");
}

@("loadWhenMultiDocumentWithPoundPrefixAndWithoutWhitespaceLoadsMultiDoc") unittest
{
    assert(loadText("a=a\n#---\nb=b").length == 2);
}

@("loadWhenMultiDocumentWithExclamationPrefixAndWithoutWhitespaceLoadsMultiDoc") unittest
{
    assert(loadText("a=a\n!---\nb=b").length == 2);
}

@("loadWhenMultiDocumentWithPoundPrefixAndLeadingWhitespaceLoadsSingleDoc") unittest
{
    assert(loadText("a=a\n \t#---\nb=b").length == 1);
}

@("loadWhenMultiDocumentWithExclamationPrefixAndLeadingWhitespaceLoadsSingleDoc") unittest
{
    assert(loadText("a=a\n \t!---\nb=b").length == 1);
}

@("loadWhenMultiDocumentWithPoundPrefixAndTrailingWhitespaceLoadsMultiDoc") unittest
{
    assert(loadText("a=a\n#--- \t \nb=b").length == 2);
}

@("loadWhenMultiDocumentWithExclamationPrefixAndTrailingWhitespaceLoadsMultiDoc") unittest
{
    assert(loadText("a=a\n!--- \t \nb=b").length == 2);
}

@("loadWhenMultiDocumentWithTrailingWhitespaceAndIndentedNextLineLoadsFollowingProperties") unittest
{
    auto loaded = loadText("a=a\n#--- \n  b=b");
    assert(loaded.length == 2);
    assert(loaded[1].keys == ["b"]);
    assert(value(loaded[1].get("b")) == "b");
}

@("loadWhenMultiDocumentWithTrailingWhitespaceTracksLocationOfFollowingProperties") unittest
{
    assert(location(loadText("a=a\n#--- \nb=b")[1].get("b")) == "3:3");
}

@("loadWhenMultiDocumentWithPoundPrefixAndTrailingCharsLoadsSingleDoc") unittest
{
    assert(loadText("a=a\n#--- \tcomment\nb=b").length == 1);
}

@("loadWhenMultiDocumentWithExclamationPrefixAndTrailingCharsLoadsSingleDoc") unittest
{
    assert(loadText("a=a\n!--- \tcomment\nb=b").length == 1);
}

@("loadWhenMultiDocumentSeparatorPrefixDifferentFromCommentPrefixLoadsMultiDoc") unittest
{
    foreach (content; ["a=a\n# comment\n!---\nb=b", "a=a\n! comment\n#---\nb=b"])
        assert(loadText(content).length == 2, content);
}

@("loadWhenCommentEndsWithBackslashLoadsFollowingProperties") unittest
{
    auto loaded = loadText("#\\\nkey=value");
    assert(loaded.length == 1);
    assert(loaded[0].keys == ["key"]);
    assert(value(loaded[0].get("key")) == "value");
}

@("loadWhenCommentWithExclamationPrefixEndsWithBackslashLoadsFollowingProperties") unittest
{
    auto loaded = loadText("!\\\nkey=value");
    assert(loaded.length == 1);
    assert(loaded[0].keys == ["key"]);
}

@("loadWhenDocumentSeparatorEndsWithBackslashLoadsSingleDocument") unittest
{
    auto loaded = loadText("a=a\n#---\\\nb=b");
    assert(loaded.length == 1);
    assert(loaded[0].keys == ["a", "b"]);
}

@("getPropertyWithWhitespaceAfterKey") unittest
{
    check("bar", "foo=baz", "3:7");
}

@("getPropertyWithSpaceSeparator") unittest
{
    check("hello", "world", "4:9");
}

@("getPropertyWithBackslashEscaped") unittest
{
    check("proper\\ty", "test", "5:11");
}

@("getPropertyWithEmptyValue") unittest
{
    check("foo", "", "7:0");
}

@("getPropertyWithBackslashEscapedInValue") unittest
{
    check("bat", "a\\", "7:7");
}

@("getPropertyWithSeparatorInValue") unittest
{
    check("bling", "a=b", "8:9");
}

@("getListProperty") unittest
{
    check("foods[0]", "Apple", "24:9");
    check("foods[1]", "Orange", "25:1");
    check("foods[2]", "Strawberry", "26:1");
    check("foods[3]", "Mango", "27:1");
}

@("getPropertyWithISO88591Character") unittest
{
    assert(value(getFromFirst("test-iso8859-1-chars")) == "æ×ÈÅÞßáñÀÿ");
}

@("getPropertyWithTrailingSpace") unittest
{
    assert(value(getFromFirst("test-with-trailing-space")) == "trailing ");
}

@("getPropertyWithEscapedTrailingSpace") unittest
{
    assert(value(getFromFirst("test-with-escaped-trailing-space")) == "trailing ");
}

@("existingCommentsAreNotTreatedAsMultiDoc") unittest
{
    enum content = "#---\n# Test\n#---\nspring=boot\n#---\n# Test\nboot=bar\n# Test\n#---\nbar=ok\n"
        ~ "!---\n! Test\n!---\nok=well\n!---\n! Test\nwell=hello\n! Test\n!---\nhello=world\n";
    assert(loadText(content).length == 1);
}

@("getPropertyAfterPoundCharacter") unittest
{
    assert(value(getFromFirst("test-line-after-empty-pound")) == "abc");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;

/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/CommentParsingTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests. Flint has one byte parser, so each
 * test runs once rather than per input mode; the char-based variants read the same bytes.
 */
module comment_parsing_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonFactory, JsonReadFeature;
import read_test_support : assertEnd, parserWith, verifyException;

@safe:

private enum DOC_WITH_SLASHSTAR_COMMENT = "[ /* comment:\n ends here */ 1 /* one more ok to have \"unquoted\" "
    ~ "and non-ascii: 㑖    */ ]";
private enum DOC_WITH_SLASHSLASH_COMMENT = "[ // comment...\n 1 \r  // one more, not array: []   & 㑖  \n ]";

private JsonParser createParser(string doc, bool enabled)
{
    auto p = JsonFactory.builder().configure(JsonReadFeature.ALLOW_JAVA_COMMENTS, enabled).build().createParser(doc);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    return p;
}

private void testDisabled(string doc)
{
    auto p = createParser(doc, false);
    try
    {
        p.nextToken();
        assert(false, "Expected exception for unrecognized comment");
    }
    catch (Exception e)
        verifyException(e, "ALLOW_COMMENTS");
    p.close();
}

private void testEnabled(string doc)
{
    auto p = createParser(doc, true);
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.getIntValue() == 1);
    assert(p.nextToken() == JsonToken.END_ARRAY);
    p.close();
}

private void testCommentsBeforePropValue(JsonReadFeature feature, string comment)
{
    foreach (prefix, suffix; [":": "123", " :": "123", "\t:": "123", ": ": "123", ":\t": "123"])
    {
        immutable doc = "{\"abc\"" ~ prefix ~ comment ~ suffix ~ "}";
        auto p = parserWith(doc, feature);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME, doc);
        assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT, doc);
        assert(p.getIntValue() == 123);
        assert(p.nextToken() == JsonToken.END_OBJECT);
        p.close();
    }
}

private void testCommentsBetweenArrayValues(JsonReadFeature feature, string comment)
{
    foreach (tmpl; ["%s,", " %s,", "\t%s,", "%s ,", "%s\t,", " %s ,", "\t%s\t,", "\n%s,", "%s\n,"])
    {
        import std.array : replace;

        immutable doc = "[1" ~ tmpl.replace("%s", comment) ~ "2]";
        auto p = parserWith(doc, feature);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT, doc);
        assert(p.getIntValue() == 1);
        assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT, doc);
        assert(p.getIntValue() == 2);
        assert(p.nextToken() == JsonToken.END_ARRAY);
        p.close();
    }
}

private void testYAMLComments()
{
    immutable doc = "# foo\n" ~ " {\"a\" # xyz\n" ~ " : # foo\n" ~ " 1, # more\n" ~ "\"b\": [ \n"
        ~ " #all!\n" ~ " 3 #yay!\n" ~ "] # foobar\n" ~ "} # x";
    auto p = parserWith(doc, JsonReadFeature.ALLOW_YAML_COMMENTS);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME);
    assert(p.currentName() == "a");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.getIntValue() == 1);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME);
    assert(p.currentName() == "b");
    assert(p.nextToken() == JsonToken.START_ARRAY);
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.getIntValue() == 3);
    assert(p.nextToken() == JsonToken.END_ARRAY);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    assertEnd(p);
    p.close();
}

@("defaultSettings")
unittest
{
    auto f = new JsonFactory();
    assert(!f.isEnabled(JsonReadFeature.ALLOW_JAVA_COMMENTS));
    auto p = f.createParser("[ 1 ]");
    p.close();
}

@("commentsDisabled")
unittest
{
    testDisabled(DOC_WITH_SLASHSTAR_COMMENT);
    testDisabled(DOC_WITH_SLASHSLASH_COMMENT);
}

@("commentsEnabled")
unittest
{
    testEnabled(DOC_WITH_SLASHSTAR_COMMENT);
    testEnabled(DOC_WITH_SLASHSLASH_COMMENT);
}

@("commentsWithUTF8")
unittest
{
    auto p = createParser("/* © 2099 Yoyodyne Inc. */\n [ \"bar? ©\" ]\n", true);
    assert(p.nextToken() == JsonToken.VALUE_STRING);
    assert(p.nextToken() == JsonToken.END_ARRAY);
    assertEnd(p);
    p.close();
}

@("yamlCommentsBytes")
unittest
{
    testYAMLComments();
    testCommentsBeforePropValue(JsonReadFeature.ALLOW_YAML_COMMENTS, "# foo\n");
}

@("yamlCommentsChars")
unittest
{
    testYAMLComments();
    testCommentsBeforePropValue(JsonReadFeature.ALLOW_YAML_COMMENTS, "# foo\n");
    testCommentsBetweenArrayValues(JsonReadFeature.ALLOW_YAML_COMMENTS, "# foo\n");
}

@("cCommentsBytes")
unittest
{
    testCommentsBeforePropValue(JsonReadFeature.ALLOW_JAVA_COMMENTS, "/* foo */\n");
}

@("cCommentsChars")
unittest
{
    testCommentsBeforePropValue(JsonReadFeature.ALLOW_JAVA_COMMENTS, "/* foo */\n");
}

@("cppCommentsBytes")
unittest
{
    testCommentsBeforePropValue(JsonReadFeature.ALLOW_JAVA_COMMENTS, "// foo\n");
}

@("cppCommentsChars")
unittest
{
    testCommentsBeforePropValue(JsonReadFeature.ALLOW_JAVA_COMMENTS, "// foo \n");
}

// Flint additions: the failures Jackson's comment skipping reports, and comments right after a value.
@("an unterminated, malformed or control-character comment fails as Jackson reports it")
unittest
{
    import read_test_support : nextFails;

    auto unterminated = parserWith("[ /* never closed", JsonReadFeature.ALLOW_JAVA_COMMENTS);
    assert(unterminated.nextToken() == JsonToken.START_ARRAY);
    nextFails(unterminated, "Unexpected end-of-input in a comment");
    auto single = parserWith("[ /x ]", JsonReadFeature.ALLOW_JAVA_COMMENTS);
    assert(single.nextToken() == JsonToken.START_ARRAY);
    nextFails(single, "was expecting either '*' or '/' for a comment");
    auto control = parserWith("[ // a\x01b\n 1 ]", JsonReadFeature.ALLOW_JAVA_COMMENTS);
    assert(control.nextToken() == JsonToken.START_ARRAY);
    nextFails(control, "Illegal character ((CTRL-CHAR, code 1))");
    auto badUtf8 = parserWith("[ /* \xC3\x28 */ 1 ]", JsonReadFeature.ALLOW_JAVA_COMMENTS);
    assert(badUtf8.nextToken() == JsonToken.START_ARRAY);
    nextFails(badUtf8, "Invalid UTF-8 middle byte 0x28");
    // '#' without ALLOW_YAML_COMMENTS is a value character, as in Jackson.
    auto hash = parserWith("[ # x\n 1 ]");
    assert(hash.nextToken() == JsonToken.START_ARRAY);
    nextFails(hash, "Unexpected character ('#' (code 35))");
}

@("a comment may follow a value without a space inside an Array or Object")
unittest
{
    auto p = parserWith("[1/*a*/,true// b\n,null#c\n]", JsonReadFeature.ALLOW_JAVA_COMMENTS,
            JsonReadFeature.ALLOW_YAML_COMMENTS);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getIntValue() == 1);
    assert(p.nextToken() == JsonToken.VALUE_TRUE);
    assert(p.nextToken() == JsonToken.VALUE_NULL);
    assert(p.nextToken() == JsonToken.END_ARRAY);
    assertEnd(p);
}

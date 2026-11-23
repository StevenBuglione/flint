// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/env/
// PropertiesPropertySourceLoaderTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `@WithResource` content is passed to the loader as bytes, with the class path
// resource's description.
// Not ported: getFileExtensions and loadXml (XML properties files, `java.util.Properties.loadFromXML`, which Flint
// does not support).
module boot_tests.properties_property_source_loader_test;

import flint.boot.env : OriginTrackedMapPropertySource, PropertiesPropertySourceLoader;

@safe:

private OriginTrackedMapPropertySource[] load(string content)
{
    return new PropertiesPropertySourceLoader().load("test.properties",
            "class path resource [test.properties]", cast(const(ubyte)[]) content);
}

/// The text block of `@WithResource`: each line ends with a newline.
private string lines(string[] text...)
{
    string result;
    foreach (line; text)
        result ~= line ~ "\n";
    return result;
}

@("loadProperties") unittest
{
    auto loaded = load("test=properties");
    auto source = loaded[0];
    assert(source.getProperty("test") == "properties");
}

@("loadMultiDocumentPropertiesWithSeparatorAtTheBeginningOfFile") unittest
{
    auto loaded = load(lines("#---", "#test", "blah=hello world", "bar=baz", "hello=world", "#---",
            "foo=bar", "bling=biz", "#comment1", "#comment2"));
    assert(loaded.length == 2);
    assert(loaded[0].getProperty("blah") == "hello world");
    assert(loaded[1].getProperty("foo") == "bar");
}

@("loadMultiDocumentProperties") unittest
{
    auto loaded = load(lines("#test", "blah=hello world", "bar=baz", "hello=world", "#---",
            "foo=bar", "bling=biz", "#comment1", "#comment2", "#---"));
    assert(loaded.length == 2);
    assert(loaded[0].getProperty("blah") == "hello world");
    assert(loaded[1].getProperty("foo") == "bar");
}

@("loadMultiDocumentPropertiesWithEmptyDocument") unittest
{
    auto loaded = load(lines("", "#---", "#test", "blah=hello world", "bar=baz", "hello=world",
            "#---", "#---", "foo=bar", "bling=biz", "#comment1", "#comment2"));
    assert(loaded.length == 2);
    assert(loaded[0].getProperty("blah") == "hello world");
    assert(loaded[1].getProperty("foo") == "bar");
}

@("loadWithEmptyValues") unittest
{
    auto loaded = load("one=1\nnone\nzero=\ntwo=2\n");
    auto source = loaded[0];
    assert(source.getProperty("one") == "1");
    assert(source.getProperty("none") == "");
    assert(source.getProperty("zero") == "");
    assert(source.getProperty("two") == "2");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;

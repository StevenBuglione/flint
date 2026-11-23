// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/env/ OriginTrackedYamlLoaderTests.java and YamlPropertySourceLoaderTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; SnakeYAML's ComposerException is Flint's
// YamlException.
module boot_tests.yaml_loader_test;

import boot_tests.support : assertThrows;
import flint.boot.env : Document, OriginTrackedYamlLoader, YamlPropertySourceLoader;
import flint.boot.internal.yaml : YamlException;
import flint.boot.origin : OriginTrackedValue, TextResourceOrigin;

@safe:

// The upstream @WithTestYamlResource content.
private enum testYaml = `# https://docs.ansible.com/ansible/latest/reference_appendices/YAMLSyntax.html

name: Martin D'vloper
job: Developer
skill: Elite
employed: True
foods:
    - Apple
    - Orange
    - Strawberry
    - Mango
languages:
    perl: Elite
    python: Elite
    pascal: Lame
education: |
    4 GCSEs
    3 A-Levels
    BSc in the Internet of Things
example:
    foo:
      - name: springboot
        url: https://springboot.example.com/
        bar:
          - bar1: baz
          - bar2: bling
empty: ""
null-value: null
emptylist: []
emptymap: {}
---

spring:
  profiles: development
name: Test Name

---
`;

private Document[] load(string yaml)
{
    return new OriginTrackedYamlLoader("test-yaml.yml", cast(const(ubyte)[]) yaml).load();
}

private OriginTrackedValue first(string key)
{
    return load(testYaml)[0].get(key);
}

private string location(OriginTrackedValue value)
{
    assert(value !is null);
    auto origin = cast(TextResourceOrigin) value.getOrigin();
    assert(origin !is null);
    return origin.getLocation().toString();
}

private void check(string key, string expected, string expectedLocation)
{
    auto value = first(key);
    assert(value !is null, key);
    assert(value.toString() == expected, key ~ ": " ~ value.toString());
    assert(location(value) == expectedLocation, key ~ ": " ~ location(value));
}

@("processSimpleKey") unittest
{
    check("name", "Martin D'vloper", "3:7");
}

@("processMap") unittest
{
    check("languages.perl", "Elite", "13:11");
    check("languages.python", "Elite", "14:13");
    check("languages.pascal", "Lame", "15:13");
}

@("processCollection") unittest
{
    check("foods[0]", "Apple", "8:7");
    check("foods[1]", "Orange", "9:7");
    check("foods[2]", "Strawberry", "10:7");
    check("foods[3]", "Mango", "11:7");
}

@("processMultiline") unittest
{
    check("education", "4 GCSEs\n3 A-Levels\nBSc in the Internet of Things\n", "16:12");
}

@("processListOfMaps") unittest
{
    check("example.foo[0].name", "springboot", "22:15");
    check("example.foo[0].url", "https://springboot.example.com/", "23:14");
    check("example.foo[0].bar[0].bar1", "baz", "25:19");
    check("example.foo[0].bar[1].bar2", "bling", "26:19");
}

@("processEmptyAndNullValues") unittest
{
    check("empty", "", "27:8");
    check("null-value", "", "28:13");
    check("emptylist", "", "29:12");
}

@("emptyMapsOrObjectsAreNotDropped") unittest
{
    auto value = first("emptymap");
    assert(value !is null && value.getValue() == "");
}

@("unsupportedType") unittest
{
    assertThrows!YamlException(() {
        load(`value: !!java.net.URL [!!java.lang.String [!!java.lang.StringBuilder ["http://localhost:9000/"]]]`);
    });
}

@("emptyDocuments") unittest
{
    assert(load("---\n---\n---\n---\n").length == 0);
}

@("loadWhenLargeNumberOfNodesLoadsYaml") unittest
{
    import std.conv : to;

    enum size = 500;
    string yaml = "defs:\n";
    foreach (i; 0 .. size)
        yaml ~= " - def" ~ i.to!string ~ ": &def" ~ i.to!string ~ "\n    - value: " ~ i.to!string ~ "\n";
    yaml ~= "refs:\n";
    foreach (i; 0 .. size)
        yaml ~= "  ref" ~ i.to!string ~ ":\n   - value: *def" ~ i.to!string ~ "\n";
    assert(load(yaml)[0].keys.length == size * 2);
}

@("loadWhenRecursiveLoadsYaml") unittest
{
    auto loaded = load("&def1\ntest:\n  a:\n    spring: 'a'\n  b:\n    boot: 'b'\n")[0];
    assert(loaded.get("test.a.spring").toString() == "a");
    assert(loaded.get("test.b.boot").toString() == "b");
}

@("loadWhenUsingAnchors") unittest
{
    auto loaded = load("some:\n  path: &anchor\n    config:\n      key: value\n  anotherpath:\n    <<: *anchor\n")[0];
    assert(loaded.get("some.path.config.key").toString() == "value");
    assert(loaded.get("some.anotherpath.config.key").toString() == "value");
}

@("canLoadFilesBiggerThan3Mb") unittest
{
    import std.array : appender;

    auto yaml = appender!string;
    while (yaml.data.length < 4_194_304)
        yaml ~= "- some list entry\n";
    assert(load(yaml.data)[0].keys.length > 0);
}

@("YamlPropertySourceLoader.load") unittest
{
    auto source = new YamlPropertySourceLoader().load("resource", "byte array resource",
            cast(const(ubyte)[]) "foo:\n  bar: spam")[0];
    assert(source.getProperty("foo.bar") == "spam");
}

@("YamlPropertySourceLoader.orderedItems") unittest
{
    string yaml;
    string[] expected;
    foreach (char c; 'a' .. 'z' + 1)
    {
        yaml ~= c ~ ": value" ~ c ~ "\n";
        expected ~= [c];
    }
    auto source = new YamlPropertySourceLoader().load("resource", "byte array resource", cast(const(ubyte)[]) yaml)[0];
    assert(source.getPropertyNames() == expected);
}

@("YamlPropertySourceLoader.mergeItems") unittest
{
    auto loaded = new YamlPropertySourceLoader().load("resource", "byte array resource",
            cast(const(ubyte)[]) "foo:\n  bar: spam\n---\nfoo:\n  baz: wham\n");
    assert(loaded.length == 2);
    assert(loaded[0].getProperty("foo.bar") == "spam");
    assert(loaded[1].getProperty("foo.baz") == "wham");
    assert(loaded[0].getName() == "resource (document #0)");
}

@("YamlPropertySourceLoader.timestampLikeItemsDoNotBecomeDates") unittest
{
    auto source = new YamlPropertySourceLoader().load("resource", "byte array resource",
            cast(const(ubyte)[]) "foo: 2015-01-28")[0];
    assert(source.getProperty("foo") == "2015-01-28");
}

@("YamlPropertySourceLoader.loadOriginAware") unittest
{
    auto loaded = new YamlPropertySourceLoader().load("resource",
            "class path resource [test-yaml.yml]", cast(const(ubyte)[]) "a: b\n---\nc: d\ne: f\n");
    foreach (source; loaded)
        foreach (name; source.getPropertyNames())
            assert(source.getOrigin(name) !is null, name);
}

// Flint additions: the YAML features Boot configuration relies on that the upstream tests do not cover.
@("flint.yaml.blockScalarsAndQuotes") unittest
{
    auto doc = load("a: >\n  folded\n  text\n\n  next\nb: |-\n  keep\nc: \"esc\\taped \\u00e9\"\nd: 'it''s'\n"
            ~ "e: plain\n  continued\nf: [x, 'y', {g: h}]\ng: {i: 1, j: [k]}\nh: 0x1A\ni: on\nj: ~\nk: !!str 012\n")[0];
    assert(doc.get("a").getValue() == "folded text\nnext\n", "a" ~ "=[" ~ doc.get("a").getValue() ~ "]");
    assert(doc.get("b").getValue() == "keep", "b" ~ "=[" ~ doc.get("b").getValue() ~ "]");
    assert(doc.get("c").getValue() == "esc\taped é", "c" ~ "=[" ~ doc.get("c").getValue() ~ "]");
    assert(doc.get("d").getValue() == "it's", "d" ~ "=[" ~ doc.get("d").getValue() ~ "]");
    assert(doc.get("e").getValue() == "plain continued", "e" ~ "=[" ~ doc.get("e").getValue() ~ "]");
    assert(doc.get("f[0]").getValue() == "x", "f[0]" ~ "=[" ~ doc.get("f[0]").getValue() ~ "]");
    assert(doc.get("f[1]").getValue() == "y", "f[1]" ~ "=[" ~ doc.get("f[1]").getValue() ~ "]");
    assert(doc.get("f[2].g").getValue() == "h", "f[2].g" ~ "=[" ~ doc.get("f[2].g").getValue() ~ "]");
    assert(doc.get("g.i").getValue() == "1", "g.i" ~ "=[" ~ doc.get("g.i").getValue() ~ "]");
    assert(doc.get("g.j[0]").getValue() == "k", "g.j[0]" ~ "=[" ~ doc.get("g.j[0]").getValue() ~ "]");
    assert(doc.get("h").getValue() == "26", "h" ~ "=[" ~ doc.get("h").getValue() ~ "]");
    assert(doc.get("i").getValue() == "true", "i" ~ "=[" ~ doc.get("i").getValue() ~ "]");
    assert(doc.get("j").getValue() == "", "j" ~ "=[" ~ doc.get("j").getValue() ~ "]");
    assert(doc.get("k").getValue() == "012", "k" ~ "=[" ~ doc.get("k").getValue() ~ "]");
}

@("flint.yaml.sequenceAtKeyIndentAndBracketKeys") unittest
{
    auto doc = load("list:\n- one\n- two: 2\n  three: 3\nmap:\n  \"[a.b]\": c\n  '[x/y]': z\n# trailing comment\n")[0];
    assert(doc.get("list[0]").getValue() == "one", "list[0]" ~ "=[" ~ doc.get("list[0]").getValue() ~ "]");
    assert(doc.get("list[1].two").getValue() == "2", "list[1].two" ~ "=[" ~ doc.get("list[1].two").getValue() ~ "]");
    assert(doc.get("list[1].three").getValue() == "3", "list[1].three" ~ "=[" ~ doc.get("list[1].three")
            .getValue() ~ "]");
    assert(doc.get("map[a.b]").getValue() == "c", "map[a.b]" ~ "=[" ~ doc.get("map[a.b]").getValue() ~ "]");
    assert(doc.get("map[x/y]").getValue() == "z", "map[x/y]" ~ "=[" ~ doc.get("map[x/y]").getValue() ~ "]");
}

@("flint.yaml.profileDocuments") unittest
{
    auto docs = load("flint:\n  application:\n    name: demo\n---\nflint:\n  config:\n    activate:\n"
            ~ "      on-profile: prod\nserver:\n  port: 8081\n");
    assert(docs.length == 2);
    assert(docs[1].get("flint.config.activate.on-profile").getValue() == "prod");
    assert(docs[1].get("server.port").getValue() == "8081");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;

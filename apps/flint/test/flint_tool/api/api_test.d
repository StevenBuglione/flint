module flint_tool.api.api_test;

import flint_tool.api.coverage : Classifier, Mapping, Status, coverage, matches, parseMapping, validRule, validSymbol;
import flint_tool.api.diff : Change, Difference, diffManifests;
import flint_tool.api.extract : ExtractRequest, extract;
import flint_tool.api.manifest : Manifest, memberId, parseManifest, renderManifest;
import flint_tool.api.upstreams : Upstream, fetchUpstream, findUpstream, parseUpstreams;
import flint.test : expect;

@safe:

/// A small upstream tree: two Gradle modules, every kind of file extract must leave out, and a flat variant.
private string fixtureTree(string flavour)
{
    import std.file : mkdirRecurse, tempDir, write;
    import std.path : buildPath, dirName;
    import std.uuid : randomUUID;

    const root = buildPath(tempDir(), "flint-api-" ~ flavour ~ "-" ~ randomUUID().toString());
    void put(string relative, string text)
    {
        const path = buildPath(root, relative);
        mkdirRecurse(dirName(path));
        write(path, text);
    }

    if (flavour == "flat")
    {
        put("org/slf4j/Logger.java", "package org.slf4j;\npublic interface Logger { void info(String msg); }\n");
        put("org/slf4j/internal/Hidden.java", "package org.slf4j.internal;\npublic class Hidden { }\n");
        put("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n");
        return root;
    }
    if (flavour == "jdk")
    {
        put("src/java.base/share/classes/java/lang/Runnable.java",
                "package java.lang;\npublic interface Runnable { void run(); }\n");
        put("src/java.base/share/classes/java/util/Optional.java",
                "package java.util;\npublic final class Optional<T> {\n"
                ~ "    public boolean isPresent() { return false; }\n}\n");
        put("src/java.base/share/classes/jdk/internal/misc/Unsafe.java",
                "package jdk.internal.misc;\npublic final class Unsafe { }\n");
        put("src/java.base/share/classes/sun/nio/ch/Net.java", "package sun.nio.ch;\npublic class Net { }\n");
        put("src/java.base/unix/classes/java/io/UnixFileSystem.java",
                "package java.io;\npublic class UnixFileSystem { }\n");
        put("src/java.sql/share/classes/java/sql/Connection.java",
                "package java.sql;\npublic interface Connection { void close(); }\n");
        put("src/java.desktop/share/classes/java/awt/Frame.java", "package java.awt;\npublic class Frame { }\n");
        put("test/jdk/java/lang/RunnableTest.java", "package java.lang;\npublic class RunnableTest { }\n");
        put("make/src/classes/build/tools/Gen.java", "package build.tools;\npublic class Gen { }\n");
        return root;
    }
    put("spring-core/src/main/java/org/x/core/Resource.java",
            "package org.x.core;\npublic interface Resource {\n    boolean exists();\n    String getFilename();\n}\n");
    put("spring-core/src/main/java/org/x/core/package-info.java", "@NullMarked\npackage org.x.core;\n");
    put("spring-core/src/main/java/module-info.java", "module org.x.core { exports org.x.core; }\n");
    put("spring-core/src/main/java/org/x/core/internal/Impl.java",
            "package org.x.core.internal;\npublic class Impl { }\n");
    put("spring-core/src/main/java/org/x/core/Util.java", "package org.x.core;\nfinal class Util { }\n");
    put("spring-core/src/test/java/org/x/core/ResourceTests.java",
            "package org.x.core;\npublic class ResourceTests { }\n");
    put("spring-core/src/testFixtures/java/org/x/core/Fixture.java", "package org.x.core;\npublic class Fixture { }\n");
    put("spring-core/src/jmh/java/org/x/core/Bench.java", "package org.x.core;\npublic class Bench { }\n");
    put("spring-web/src/main/java/org/x/web/HttpStatus.java",
            "package org.x.web;\npublic enum HttpStatus { OK, NOT_FOUND; public int value() { return 0; } }\n");
    put("spring-web/src/main/java/org/x/web/GetMapping.java",
            "package org.x.web;\npublic @interface GetMapping { String[] value() default {}; }\n");
    put("plugin/src/intTest/projects/app/src/main/java/demo/App.java", "package demo;\npublic class App { }\n");
    put("buildSrc/src/main/java/build/Conventions.java", "package build;\npublic class Conventions { }\n");
    put("framework-docs/src/main/java/docs/Sample.java", "package docs;\npublic class Sample { }\n");
    return root;
}

private void removeTree(string root)
{
    import std.file : rmdirRecurse;

    rmdirRecurse(root);
}

private string[] typeIds(const ref Manifest manifest)
{
    string[] ids;
    foreach (ref type; manifest.types)
        ids ~= type.module_ ~ ":" ~ type.decl.id;
    return ids;
}

@("extract keeps src/main/java of each module and leaves out tests, fixtures, jmh, internal and excluded trees")
unittest
{
    const root = fixtureTree("gradle");
    scope (exit)
        removeTree(root);
    ExtractRequest request;
    request.source = root;
    request.project = "spring-x";
    request.version_ = "v1.0.0";
    request.excludes = ["buildSrc", "framework-docs/"];
    auto extraction = extract(request);
    expect(extraction.problems.length).toEqual(0);
    expect(extraction.files).toEqual(4);
    expect(typeIds(extraction.manifest)).toEqual([
        "spring-core:org.x.core.Resource", "spring-web:org.x.web.GetMapping",
        "spring-web:org.x.web.HttpStatus"
    ]);
    const modules = extraction.manifest.modules;
    expect(modules.length).toEqual(2);
    expect(modules[0].name).toEqual("spring-core");
    expect(modules[0].methods).toEqual(2);
    expect(modules[1].constants).toEqual(2);
    expect(modules[1].attributes).toEqual(1);
    expect(modules[1].elements).toEqual(6);
    expect(extraction.manifest.types[0].file).toEqual("spring-core/src/main/java/org/x/core/Resource.java");
}

@("a flat source archive is one module named after the project")
unittest
{
    const root = fixtureTree("flat");
    scope (exit)
        removeTree(root);
    ExtractRequest request;
    request.source = root;
    request.project = "slf4j-api";
    request.version_ = "2.0.20";
    auto extraction = extract(request);
    expect(typeIds(extraction.manifest)).toEqual(["slf4j-api:org.slf4j.Logger"]);
}

@("an OpenJDK tree: src/<module>/share/classes, the JDK module as module, only the included package roots")
unittest
{
    const root = fixtureTree("jdk");
    scope (exit)
        removeTree(root);
    ExtractRequest request;
    request.source = root;
    request.project = "openjdk";
    request.version_ = "jdk-21.0.13-ga";
    auto everything = extract(request);
    expect(typeIds(everything.manifest)).toEqual([
        "java.desktop:java.awt.Frame", "java.base:java.lang.Runnable",
        "java.sql:java.sql.Connection", "java.base:java.util.Optional", "java.base:sun.nio.ch.Net"
    ]);
    request.includes = ["src/java.base/share/classes/java/", "src/java.sql/share/classes/java"];
    auto exported = extract(request);
    expect(exported.problems.length).toEqual(0);
    expect(exported.files).toEqual(3);
    expect(typeIds(exported.manifest)).toEqual([
        "java.base:java.lang.Runnable", "java.sql:java.sql.Connection", "java.base:java.util.Optional"
    ]);
    expect(exported.manifest.types[0].file).toEqual("src/java.base/share/classes/java/lang/Runnable.java");
}

@("a manifest renders one type per line and reads back to the same elements")
unittest
{
    import std.algorithm.searching : count;

    const root = fixtureTree("gradle");
    scope (exit)
        removeTree(root);
    ExtractRequest request;
    request.source = root;
    request.project = "spring-x";
    request.version_ = "v1.0.0";
    request.excludes = ["buildSrc", "framework-docs"];
    auto extraction = extract(request);
    const text = renderManifest(extraction.manifest);
    expect(text.count("\n{\"id\":")).toEqual(extraction.manifest.types.length);
    Manifest reread;
    string error;
    expect(parseManifest(text, reread, error)).toEqual(true);
    expect(error).toEqual("");
    expect(renderManifest(reread)).toEqual(text);
    expect(reread.types[0].decl.package_).toEqual("org.x.core");
    expect(memberId(reread.types[0].decl, reread.types[0].decl.members[0])).toEqual("org.x.core.Resource#exists()");
    expect(parseManifest(`{"schema":"other"}`, reread, error)).toEqual(false);
    expect(error).toEqual("not a flint.api-manifest/1 document");
}

@("mapping patterns: * stays within a name, ** crosses packages and members")
unittest
{
    expect(matches("org.x.jmx.**", "org.x.jmx.export.Exporter#start()")).toEqual(true);
    expect(matches("org.x.jmx.**", "org.x.jmxe.Thing")).toEqual(false);
    expect(matches("org.x.web.HttpStatus#*", "org.x.web.HttpStatus#OK")).toEqual(true);
    expect(matches("org.x.web.HttpStatus#*", "org.x.web.HttpStatus#value()")).toEqual(false);
    expect(matches("org.x.web.HttpStatus#*(*)", "org.x.web.HttpStatus#valueOf(int)")).toEqual(true);
    expect(matches("org.x.*.Resource", "org.x.core.Resource")).toEqual(true);
    expect(matches("org.x.*.Resource", "org.x.core.io.Resource")).toEqual(false);
    expect(validSymbol("flint.engine.http.HttpStatus")).toEqual(true);
    expect(validSymbol("flint.")).toEqual(false);
    expect(validSymbol("org.springframework.X")).toEqual(false);
    expect(validSymbol("flint.engine.http..X")).toEqual(false);
    expect(validRule("R1")).toEqual(true);
    expect(validRule("R14")).toEqual(true);
    expect(validRule("R15")).toEqual(false);
    expect(validRule("R16")).toEqual(true);
    expect(validRule("R17")).toEqual(true);
    expect(validRule("R18")).toEqual(true);
    expect(validRule("R19")).toEqual(false);
    expect(validRule("R0")).toEqual(false);
    expect(validRule("R01")).toEqual(false);
}

@("an exact id beats patterns, then the longest literal prefix, then fewer **")
unittest
{
    import flint_tool.api.coverage : moreSpecific;

    Mapping mapping;
    string error;
    const parsed = parseMapping(`{"rulebook":1,"elements":{
        "org.x.**":{"status":"excluded","category":"jvm-platform"},
        "org.x.web.**":{"status":"adapted","rules":["R3","R13"]},
        "org.x.web.*":{"status":"excluded","category":"deferred","phase":"2"},
        "org.x.web.HttpStatus":{"status":"ported","d":"flint.engine.web.HttpStatus"}}}`, mapping, error);
    expect(error).toEqual("");
    expect(parsed).toEqual(true);
    expect(mapping.rulebook).toEqual(1);
    const classifier = Classifier(mapping);
    expect(classifier.classify("org.x.web.HttpStatus").status).toEqual(Status.ported);
    expect(classifier.classify("org.x.web.HttpStatus#OK").rules).toEqual(["R3", "R13"]);
    expect(classifier.classify("org.x.web.MediaType").category).toEqual("deferred");
    expect(classifier.classify("org.x.core.Resource").category).toEqual("jvm-platform");
    expect(classifier.classify("com.other.Type") is null).toEqual(true);
    expect(moreSpecific("org.x.web.*", "org.x.web.**")).toEqual(true);
    expect(moreSpecific("org.x.**", "org.x.web.**")).toEqual(false);
}

@("invalid mapping entries are refused with the element and the reason")
unittest
{
    import flint_tool.api.coverage : rulebookVersion;

    Mapping mapping;
    string error;
    expect(parseMapping(`{"elements":{"a.B":{"status":"ported"}}}`, mapping, error)).toEqual(false);
    expect(error).toEqual("a.B: a ported element needs its D symbol `d` under flint.");
    expect(parseMapping(`{"elements":{"a.B":{"status":"adapted","rules":["R3","R99"]}}}`, mapping, error)).toEqual(
            false);
    expect(error).toEqual("a.B: `R99` is not a rulebook rule, R1 to R14 or R16 to R18");
    expect(parseMapping(`{"elements":{"a.B":{"status":"adapted"}}}`, mapping, error)).toEqual(false);
    expect(parseMapping(`{"elements":{"a.B":{"status":"excluded","category":"jmx"}}}`, mapping, error)).toEqual(false);
    expect(parseMapping(`{"elements":{"a.B":{"status":"excluded","category":"deferred"}}}`, mapping, error)).toEqual(
            false);
    expect(error).toEqual("a.B: a deferred element must name its `phase`");
    expect(parseMapping(`{"elements":{"a.B":{"status":"done"}}}`, mapping, error)).toEqual(false);
    expect(parseMapping(`[]`, mapping, error)).toEqual(false);
    expect(parseMapping(`{"upstream":"p@v1","elements":{}}`, mapping, error)).toEqual(true);
    expect(mapping.covers("p", "v1")).toEqual(true);
    expect(mapping.covers("p", "v2")).toEqual(false);
    expect(rulebookVersion("# Rulebook\n\nRulebook version: **12**.\n")).toEqual(12);
    expect(rulebookVersion("no version")).toEqual(0);
}

@("coverage tallies every element per module and lists the unclassified ids")
unittest
{
    const root = fixtureTree("gradle");
    scope (exit)
        removeTree(root);
    ExtractRequest request;
    request.source = root;
    request.project = "spring-x";
    request.version_ = "v1.0.0";
    request.excludes = ["buildSrc", "framework-docs"];
    auto manifest = extract(request).manifest;
    Mapping mapping;
    string error;
    parseMapping(`{"elements":{
        "org.x.web.**":{"status":"excluded","category":"deferred","phase":"2"},
        "org.x.core.Resource":{"status":"ported","d":"flint.core.Resource"},
        "org.x.core.Resource#exists()":{"status":"adapted","rules":["R6"]}}}`, mapping, error);
    const classifier = Classifier(mapping);
    const result = coverage(manifest, classifier);
    expect(result.summary.total).toEqual(9);
    expect(result.summary.ported).toEqual(1);
    expect(result.summary.adapted).toEqual(1);
    expect(result.summary.excluded).toEqual(6);
    expect(result.summary.unclassified).toEqual(1);
    expect(result.unclassified).toEqual(["org.x.core.Resource#getFilename()"]);
    expect(result.modules.length).toEqual(2);
    expect(result.modules[0].name).toEqual("spring-core");
    expect(result.modules[0].unclassified).toEqual(1);
    expect(result.modules[1].classifiedPercent).toEqual(100.0);
}

@("diff reports added, removed and changed elements by id, ignoring parameter names and member order")
unittest
{
    import flint_tool.api.java : parseJava;
    import flint_tool.api.manifest : ApiType;

    Manifest manifestOf(string source)
    {
        Manifest manifest;
        foreach (decl; parseJava(source).types)
            manifest.types ~= ApiType("m", "A.java", decl);
        return manifest;
    }

    const older = manifestOf(`package p;
public class A {
    public void keep(String name) { }
    public int count() { return 0; }
    public void gone() { }
    public static class Old { }
}`);
    const newer = manifestOf(`package p;
public final class A {
    public long count() { return 0; }
    public void keep(String renamed) { }
    public void added(int x) { }
    public static class Old { }
}`);
    const differences = diffManifests(older, newer);
    string[] lines;
    foreach (ref difference; differences)
        lines ~= cast(string) difference.change ~ " " ~ difference.kind ~ " " ~ difference.id;
    expect(lines).toEqual([
        "changed class p.A", "added method p.A#added(int)", "changed method p.A#count()",
        "removed method p.A#gone()"
    ]);
    expect(differences[0].details).toEqual(["modifiers: (none) -> final"]);
    expect(differences[2].details).toEqual(["type: int -> long"]);
}

@("upstream pins parse, and the reference cache is filled only by an archive with the pinned digest")
unittest
{
    import std.file : exists, mkdirRecurse, readText, rmdirRecurse, tempDir, write;
    import std.array : replicate;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import flint_tool.support.files : sha256File;
    import flint_tool.support.process : Launch, capture;

    const work = buildPath(tempDir(), "flint-api-fetch-" ~ randomUUID().toString());
    scope (exit)
        rmdirRecurse(work);
    mkdirRecurse(buildPath(work, "lib-1.0", "src", "main", "java", "p"));
    write(buildPath(work, "lib-1.0", "src", "main", "java", "p", "A.java"), "package p;\npublic class A { }\n");
    const archive = buildPath(work, "lib-1.0.tar.gz");
    const packed = capture(["tar", "-czf", "lib-1.0.tar.gz", "lib-1.0"], Launch(work));
    expect(packed.failure ~ packed.errors).toEqual("");
    expect(packed.ok).toEqual(true);
    const digest = sha256File(archive);

    Upstream[] upstreams;
    string error;
    const head = `{"schema":"flint.api-upstreams/1","upstreams":[{"project":"lib","version":"1.0","url":"`;
    const tail = `","format":"tar.gz","exclude":["docs"],"include":["src"]}]}`;
    const pins = head ~ fileUrl(archive) ~ `","sha256":"` ~ digest ~ tail;
    expect(parseUpstreams(pins, upstreams, error)).toEqual(true);
    expect(error).toEqual("");
    const pinned = findUpstream(upstreams, "lib", "1.0");
    expect(pinned.exclude).toEqual(["docs"]);
    expect(pinned.include).toEqual(["src"]);
    expect(pinned.signaturesOnly).toEqual(false);
    expect(findUpstream(upstreams, "lib", "2.0") is null).toEqual(true);

    const cache = buildPath(work, "cache");
    const offline = fetchUpstream(*pinned, cache, true);
    expect(offline.failure).toEqual("lib-1.0 is not in the reference cache and flint is offline");
    const fetched = fetchUpstream(*pinned, cache, false);
    expect(fetched.failure).toEqual("");
    expect(fetched.cached).toEqual(false);
    expect(readText(buildPath(fetched.directory, "src", "main", "java", "p", "A.java"))).toEqual(
            "package p;\npublic class A { }\n");
    expect(fetchUpstream(*pinned, cache, true).cached).toEqual(true);

    Upstream tampered = upstreams[0];
    tampered.version_ = "1.0-bad";
    tampered.sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    const refused = fetchUpstream(tampered, cache, false);
    expect(refused.failure.length > 0).toEqual(true);
    expect(exists(buildPath(cache, "lib-1.0-bad"))).toEqual(false);
    expect(parseUpstreams(`{"schema":"flint.api-upstreams/1","upstreams":[{"project":"x","version":"1",
        "url":"u","sha256":"abc","format":"zip"}]}`, upstreams, error)).toEqual(false);
    const jdk = `{"schema":"flint.api-upstreams/1","upstreams":[{"project":"openjdk","version":"21","url":"u",`
        ~ `"sha256":"` ~ replicate("0", 64) ~ `","format":"tar.gz","signatures_only":true}]}`;
    expect(parseUpstreams(jdk, upstreams, error)).toEqual(true);
    expect(upstreams[0].signaturesOnly).toEqual(true);
}

@("`flint api extract --version TAG` reaches the --tag option; other commands keep --version")
unittest
{
    import flint_tool.app : tagAlias;

    expect(tagAlias(["api", "extract", "--version", "v7.1.0", "--project", "p"])).toEqual([
        "api", "extract", "--tag", "v7.1.0", "--project", "p"
    ]);
    expect(tagAlias(["api", "extract", "--version=v1"])).toEqual(["api", "extract", "--tag=v1"]);
    expect(tagAlias(["build", "--version"])).toEqual(["build", "--version"]);
    expect(tagAlias(["api", "diff", "--version"])).toEqual(["api", "diff", "--version"]);
}

@("a slice selects a module's types by package pattern, and its checklist reads statuses from the mapping")
unittest
{
    import std.algorithm.searching : canFind;
    import flint_tool.api.checklist : ChecklistCounts, IndexRow, Slice, parseSlice, renderChecklist,
        renderIndex, selected;

    const root = fixtureTree("gradle");
    scope (exit)
        removeTree(root);
    ExtractRequest request;
    request.source = root;
    request.project = "spring-x";
    request.version_ = "v1.0.0";
    request.excludes = ["buildSrc", "framework-docs"];
    auto manifest = extract(request).manifest;
    Slice slice;
    string error;
    expect(parseSlice(`{"schema":"flint.api-slice/1","title":"Phase 1","checklists":[
        {"name":"spring-web","upstream":"spring-x@v1.0.0","module":"spring-web","packages":["org.x.*"]},
        {"name":"spring-core","upstream":"spring-x@v1.0.0","module":"spring-core","packages":["org.y.**"]}]}`,
            slice, error)).toEqual(true);
    expect(error).toEqual("");
    expect(selected(slice.checklists[0], manifest.types[1])).toEqual(true);
    expect(selected(slice.checklists[0], manifest.types[0])).toEqual(false);
    expect(selected(slice.checklists[1], manifest.types[0])).toEqual(false);

    Mapping mapping;
    parseMapping(`{"elements":{"org.x.web.HttpStatus":{"status":"ported","d":"flint.engine.web.HttpStatus"},
        "org.x.web.HttpStatus#value()":{"status":"adapted","rules":["R6"]},
        "org.x.web.GetMapping#*":{"status":"excluded","category":"deferred","phase":"2"}}}`, mapping, error);
    const classifier = Classifier(mapping);
    ChecklistCounts counts;
    const text = renderChecklist(slice.checklists[0], slice.title, manifest,
            "api/upstream/spring-x-v1.0.0.json", classifier, "api/framework/mapping.json", counts);
    expect(counts.types).toEqual(2);
    expect(counts.elements).toEqual(6);
    expect(counts.open).toEqual(3);
    expect(text.canFind("# spring-web: Phase 1 checklist\n")).toEqual(true);
    expect(text.canFind("2 types, 6 elements: 1 ported, 1 adapted, 1 excluded, 3 open.")).toEqual(true);
    expect(text.canFind("| ported `flint.engine.web.HttpStatus` | `public enum HttpStatus` | `org.x.web.HttpStatus` |"))
        .toEqual(true);
    expect(text.canFind("| adapted R6 | `public int value()` | `#value()` |")).toEqual(true);
    expect(text.canFind("| excluded: deferred (phase 2) | `public String[] value() default {}` | `#value` |")).toEqual(
            true);
    expect(text.canFind("|  | `public OK` | `#OK` |")).toEqual(true);
    const index = renderIndex("Phase 1", "slice.json", [
        IndexRow("spring-web", "spring-x@v1.0.0", "spring-web", counts)
    ]);
    expect(index.canFind("| [spring-web](spring-web.md) | spring-x@v1.0.0 | `spring-web` | 2 | 6 | 1 | 1 | 1 | 3 |"))
        .toEqual(true);
    expect(parseSlice(
            `{"schema":"flint.api-slice/1","checklists":[{"name":"Bad Name","upstream":"a@1","module":"m"}]}`,
            slice, error)).toEqual(false);
}

@("checklist cells escape table pipes and backticks; constructors render with their type's name")
unittest
{
    import flint_tool.api.checklist : cell, declaration;
    import flint_tool.api.java : parseJava;

    expect(cell("a | b `c`")).toEqual("a \\| b 'c'");
    const unit = parseJava("package p;\npublic class Pool { protected Pool(int size) throws Exception { } }\n");
    expect(declaration(unit.types[0].members[0], "Pool")).toEqual("protected Pool(int size) throws Exception");
    expect(declaration(unit.types[0])).toEqual("public class Pool");
}

@("a ported file needs a pinned upstream that may be ported, its copyright and licence lines and the notice")
unittest
{
    import std.array : replicate;
    import flint_tool.api.headers : LicenceEntry, checkHeader, parseLicenceMatrix, sdlLicence;

    Upstream[] upstreams;
    string error;
    parseUpstreams(`{"schema":"flint.api-upstreams/1","upstreams":[
        {"project":"spring-framework","version":"v7.1.0","repo":"framework","url":"u","format":"tar.gz",
         "sha256":"` ~ "a".replicate(64) ~ `"},
        {"project":"jakarta-servlet","version":"6.1.0","repo":"framework","url":"u","format":"jar",
         "sha256":"` ~ "b".replicate(64) ~ `"},
        {"project":"liquibase","version":"4.0","repo":"boot","url":"u","format":"jar","sha256":"` ~ "c".replicate(
            64) ~ `"},
        {"project":"spring-security","version":"7.2.0","repo":"security","url":"u","format":"tar.gz",
         "sha256":"` ~ "d".replicate(64) ~ `"}]}`, upstreams, error);
    expect(error).toEqual("");
    LicenceEntry[] matrix;
    expect(parseLicenceMatrix(`{"projects":[
        {"name":"spring-framework","licence":"Apache-2.0","use":"port-source","tag":"v7.1.0",
         "header":"Copyright 2002-present the original author or authors."},
        {"name":"jakarta-servlet","licence":"EPL-2.0 OR GPL-2.0-with-classpath-exception","use":"epl-module",
         "tag":"6.1.0"},
        {"name":"liquibase","licence":"FSL-1.1-ALv2","use":"clean-room","tag":null},
        {"name":"spring-security","licence":"Apache-2.0","use":"port-source","tag":"to pin at port start"}]}`,
            matrix, error)).toEqual(true);

    string[] check(string header, string licence = "Apache-2.0")
    {
        string[] messages;
        foreach (problem; checkHeader("f.d", header ~ "module flint.util.assert_;\n", upstreams, matrix, licence))
            messages ~= problem.message;
        return messages;
    }

    enum source = "spring-core/src/main/java/org/springframework/util/Assert.java";
    enum good = "// Ported from spring-framework v7.1.0: " ~ source ~ "\n"
        ~ "// Copyright 2002-present the original author or authors.\n"
        ~ "// Licensed under the Apache License, Version 2.0.\n// Modified by the Flint authors.\n";
    expect(check(good)).toEqual(cast(string[]) null);
    expect(check("/// Not ported; it quotes `// Ported from x y: z` in prose.\n")).toEqual(cast(string[]) null);
    expect(check(
            "// Ported from spring-framework v7.1.0: a/B.java\n// Licensed under the Apache License, Version 2.0\n"))
        .toEqual([
            "the header lacks the upstream copyright line: Copyright 2002-present the original author or authors.",
            "the header lacks \"Modified by the Flint authors\" (Apache-2.0 §4(b))"
    ]);
    expect(check("// Ported from spring-framework v7.0.0: a/B.java\n")).toEqual(
            ["the marker names spring-framework at a version api/upstreams.json does not pin"]);
    expect(check("// Ported from liquibase 4.0: a/B.java\n")).toEqual(
            [
        "liquibase is `clean-room` (FSL-1.1-ALv2) in policy/upstream-licences.json: its source may not be ported"
    ]);
    expect(check("// Ported from spring-security 7.2.0: a/B.java\n// Copyright 2004 x\n"
            ~ "// Licensed under the Apache License, Version 2.0\n// Modified by the Flint authors.\n")).toEqual(
            [
        "policy/upstream-licences.json pins spring-security at `to pin at port start`, not 7.2.0"
    ]);
    enum servlet = "// Ported from jakarta-servlet 6.1.0: jakarta/servlet/Filter.java\n// Copyright (c) 1997 Oracle\n"
        ~ "// Licensed under the Eclipse Public License 2.0.\n// Modified by the Flint authors.\n";
    expect(check(servlet, "EPL-2.0")).toEqual(cast(string[]) null);
    expect(check(servlet)).toEqual(
            [
        "jakarta-servlet is ported only into EPL-2.0 packages, but the package declares `Apache-2.0`"
    ]);
    expect(check("// Ported from spring-framework: no version
")).toEqual(["the marker names spring-framework at a version api/upstreams.json does not pin"]);
    expect(check("// Ported from somewhere 1.0: x
")).toEqual([
        "the marker must name an upstream pinned in api/upstreams.json and its version: "
        ~ "`Ported from <project> <version>: <upstream path>`"
    ]);
    expect(sdlLicence("name \"x\"\nlicense \"EPL-2.0\"\n")).toEqual("EPL-2.0");
    // An SPDX line naming the licence the port is made under stands for the licence sentence, and the upstream
    // paths may continue on the lines after the marker.
    enum spdx = "/*\n * Ported from jakarta-servlet 6.1.0: https://github.com/jakartaee/servlet, tag 6.1.0,\n"
        ~ " *   api/src/main/java/jakarta/servlet/{Filter,Servlet}.java\n * Copyright (c) 1997 Oracle\n"
        ~ " * SPDX-License-Identifier: EPL-2.0 OR GPL-2.0 WITH Classpath-exception-2.0\n"
        ~ " * Modified by the Flint authors.\n */\n";
    expect(check(spdx, "EPL-2.0")).toEqual(cast(string[]) null);
    expect(check("// Ported from spring-framework v7.1.0:\n//   a/B.java\n"
            ~ "// Copyright 2002-present the original author or authors.\n// SPDX-License-Identifier: MIT\n"
            ~ "// Modified by the Flint authors.\n")).toEqual(
            [
        "the header lacks the licence line (Licensed under the Apache License, Version 2.0, or an "
        ~ "SPDX-License-Identifier naming Apache-2.0)"
    ]);
}

@("the coverage baseline ratchets: counts may fall, never rise, and a lowered baseline keeps unmeasured upstreams")
unittest
{
    import flint_tool.api.baseline : Baseline, BaselineUpstream, compare, lowered, parseBaseline, renderBaseline;

    Baseline baselineOf(string key, size_t[string] modules)
    {
        Baseline baseline;
        baseline.upstreams = [BaselineUpstream(key, modules)];
        return baseline;
    }

    auto recorded = baselineOf("spring-framework@v7.1.0", [
        "spring-core": 10,
        "spring-jdbc": 5,
        "spring-tx": 0
    ]);
    recorded.upstreams ~= BaselineUpstream("slf4j-api@2.0.20", ["slf4j-api": 7]);
    const text = renderBaseline(recorded);
    Baseline reread;
    string error;
    expect(parseBaseline(text, reread, error)).toEqual(true);
    expect(renderBaseline(reread)).toEqual(text);
    expect(reread.total).toEqual(22);

    const better = baselineOf("spring-framework@v7.1.0", [
        "spring-core": 4,
        "spring-jdbc": 5,
        "spring-tx": 0
    ]);
    const ratchet = compare(reread, better);
    expect(ratchet.regressions.length).toEqual(0);
    expect(ratchet.improvements).toEqual(
            ["spring-framework@v7.1.0 spring-core: 4 unclassified, below the baseline's 10"]);
    string[] raised;
    const next = lowered(reread, better, raised);
    expect(raised.length).toEqual(0);
    expect(next.total).toEqual(16);
    expect(next.find("slf4j-api@2.0.20").modules["slf4j-api"]).toEqual(7);

    const worse = baselineOf("spring-framework@v7.1.0", [
        "spring-core": 4,
        "spring-jdbc": 6,
        "spring-tx": 0,
        "spring-new": 3
    ]);
    expect(compare(next, worse).regressions).toEqual(
            [
        "spring-framework@v7.1.0 spring-jdbc: 6 unclassified, above the baseline's 5",
        "spring-framework@v7.1.0 spring-new: 3 unclassified, and the module is not in the baseline"
    ]);
    lowered(next, worse, raised);
    expect(raised.length).toEqual(2);

    // A manifest the baseline has never recorded fails the ratchet, and --update-baseline records it.
    const fresh = baselineOf("jackson-core@3.1.8", ["jackson-core": 30]);
    expect(compare(next, fresh).regressions).toEqual(
            ["jackson-core@3.1.8 is not in the baseline; record it with --update-baseline"]);
    const added = lowered(next, fresh, raised);
    expect(raised.length).toEqual(0);
    expect(added.total).toEqual(46);
}

@("a checklist marked complete is unfinished while an element is unclassified or deferred")
unittest
{
    import flint_tool.api.checklist : Slice, parseSlice, unfinished;

    const root = fixtureTree("gradle");
    scope (exit)
        removeTree(root);
    ExtractRequest request;
    request.source = root;
    request.project = "spring-x";
    request.version_ = "v1.0.0";
    request.excludes = ["buildSrc", "framework-docs"];
    auto manifest = extract(request).manifest;
    Slice slice;
    string error;
    parseSlice(`{"schema":"flint.api-slice/1","checklists":[
        {"name":"spring-core","upstream":"spring-x@v1.0.0","module":"spring-core","complete":true}]}`, slice, error);
    expect(slice.checklists[0].complete).toEqual(true);
    Mapping mapping;
    parseMapping(`{"elements":{"org.x.core.Resource":{"status":"ported","d":"flint.core.Resource"},
        "org.x.core.Resource#exists()":{"status":"excluded","category":"deferred","phase":"2"},
        "org.x.core.Resource#getFilename()":{"status":"excluded","category":"jvm-platform"}}}`, mapping, error);
    const partial = Classifier(mapping);
    expect(unfinished(slice.checklists[0], manifest, partial)).toEqual(
            ["org.x.core.Resource#exists() (deferred to phase 2)"]);
    parseMapping(`{"elements":{"org.x.core.**":{"status":"adapted","rules":["R6"]}}}`, mapping, error);
    const done = Classifier(mapping);
    expect(unfinished(slice.checklists[0], manifest, done).length).toEqual(0);
}

@("a marker names its pin by project, owner/repo or Maven artifact id, with the pinned version anywhere on the line")
unittest
{
    import std.array : replicate;
    import flint_tool.api.headers : markerText, pinOf;

    Upstream[] upstreams;
    string error;
    enum central = "https://repo1.maven.org/maven2/";
    parseUpstreams(`{"schema":"flint.api-upstreams/1","upstreams":[
        {"project":"spring-framework","version":"v7.1.0","url":
         "https://github.com/spring-projects/spring-framework/archive/refs/tags/v7.1.0.tar.gz",
         "format":"tar.gz","sha256":"` ~ "a".replicate(64) ~ `"},
        {"project":"jackson-annotations","version":"2.21","format":"jar","sha256":"` ~ "b".replicate(64) ~ `",
         "url":"` ~ central ~ `com/fasterxml/jackson/core/jackson-annotations/2.21/`
            ~ `jackson-annotations-2.21-sources.jar"},
        {"project":"jakarta-servlet","version":"6.1.0","format":"jar","sha256":"` ~ "c".replicate(64) ~ `",
         "url":"` ~ central ~ `jakarta/servlet/jakarta.servlet-api/6.1.0/jakarta.servlet-api-6.1.0-sources.jar"}]}`,
            upstreams, error);
    expect(error).toEqual("");

    string pinned(string header)
    {
        string failure;
        const pin = pinOf(markerText(header), upstreams, failure);
        return pin is null ? failure : pin.project;
    }

    expect(pinned("/++\nPorted from spring-projects/spring-framework v7.1.0, spring-web/src/main/java/X.java\n+/\n"))
        .toEqual("spring-framework");
    expect(pinned(" * Ported from Jackson (jackson-annotations) 2.21, https://github.com/FasterXML/x, tag x\n"))
        .toEqual("jackson-annotations");
    expect(pinned(" * Ported from Jackson (jackson-annotations), tag jackson-annotations-2.21:\n")).toEqual(
            "jackson-annotations");
    expect(pinned("Ported from jakartaee/servlet, jakarta.servlet-api 6.1.0 (the sources jar)\n")).toEqual(
            "jakarta-servlet");
    expect(pinned("// Ported from jakarta-servlet 6.0.0: x\n")).toEqual(
            "the marker names jakarta-servlet at a version api/upstreams.json does not pin");
}

@("a licence may be stated by its own standard wording: the MIT grant, the EPL by name or identifier")
unittest
{
    import flint_tool.api.headers : LicenceEntry, statesLicence;

    const mit = LicenceEntry("slf4j", "MIT", "port-source", "2.0.20");
    expect(statesLicence(" * Permission is hereby granted, free  of charge, to any person\n", mit)).toEqual(true);
    expect(statesLicence(" * Licensed under the MIT License.\n", mit)).toEqual(true);
    expect(statesLicence(" * Copyright (c) 2004 QOS.ch\n", mit)).toEqual(false);
    const epl = LicenceEntry("jakarta-servlet", "EPL-2.0 OR GPL-2.0-with-classpath-exception", "epl-module", "6.1.0");
    expect(statesLicence("Flint distributes this module under EPL-2.0 only.\n", epl)).toEqual(true);
    expect(statesLicence("Licensed under the Apache License, Version 2.0\n", epl)).toEqual(false);
    const apache = LicenceEntry("spring-framework", "Apache-2.0", "port-source", "v7.1.0");
    expect(statesLicence("Licensed under the Apache License, Version 2.0 (the \"License\")\n", apache)).toEqual(true);
}

@("upstream header forms: a project named in a URL, the Apache licence by name, an upstream's own header line")
unittest
{
    import std.array : replicate;
    import flint_tool.api.headers : LicenceEntry, checkHeader, markerText, pinOf, statesLicence;

    Upstream[] upstreams;
    string error;
    parseUpstreams(`{"schema":"flint.api-upstreams/1","upstreams":[{"project":"hibernate-validator",
        "version":"9.1.6.Final","format":"jar","sha256":"` ~ "a".replicate(64) ~ `","url":
        "https://repo1.maven.org/maven2/org/hibernate/validator/hibernate-validator/9.1.6.Final/`
            ~ `hibernate-validator-9.1.6.Final-sources.jar"},
        {"project":"jakarta-validation","version":"3.1.1","format":"jar","sha256":"` ~ "b".replicate(
                64) ~ `","url":"u"}]}`, upstreams, error);
    string failure;
    const pin = pinOf(markerText(
            " * Ported from Hibernate Validator 9.1.6.Final, https://github.com/hibernate/hibernate-validator,\n"),
            upstreams, failure);
    expect(failure).toEqual("");
    expect(pin.project).toEqual("hibernate-validator");
    const apache = LicenceEntry("jakarta-validation", "Apache-2.0", "port-source", "3.1.1", "Jakarta Validation API");
    expect(statesLicence(" * License: Apache License, Version 2.0\n", apache)).toEqual(true);
    enum header = "/*\n * Ported from Jakarta Validation API 3.1.1 (jakarta-validation), https://x, tag 3.1.1:\n"
        ~ " *\n * Jakarta Validation API\n * License: Apache License, Version 2.0\n *\n"
        ~ " * Modified by the Flint authors.\n */\nmodule flint.jakarta.validation;\n";
    expect(checkHeader("f.d", header, upstreams, [apache], "Apache-2.0").length).toEqual(0);
}

@("test-source archives parse from api/upstream-tests.json and cache apart from the sources jars")
unittest
{
    import std.array : replicate;
    import flint_tool.api.upstreams : parseUpstreamTests;

    Upstream[] archives;
    string error;
    expect(parseUpstreamTests(`{"schema":1,"archives":[{"project":"jackson-databind","version":"3.1.8",
        "matrix":"jackson-databind","url":"u","sha256":"` ~ "a".replicate(64) ~ `","format":"tar.gz",
        "tests":"src/test/java"}]}`, archives, error)).toEqual(true);
    expect(error).toEqual("");
    expect(archives[0].key).toEqual("jackson-databind-3.1.8-tests");
    expect(archives[0].tests).toEqual(true);
    expect(parseUpstreamTests(`{"archives":[{"project":"x","version":"1","url":"u","sha256":"short",
        "format":"tar.gz"}]}`, archives, error)).toEqual(false);
}

/// A file URL curl reads on every host: `file:///C:/a/b` on Windows, whose `\` would also be invalid in JSON.
private string fileUrl(string path)
{
    version (Windows)
    {
        import std.array : replace;

        return "file:///" ~ path.replace(`\`, "/");
    }
    else
        return "file://" ~ path;
}

@("a runtime port resolves an api:false pin, and BSL-1.0 is stated by druntime's own wording")
unittest
{
    import std.array : replicate;
    import flint_tool.api.headers : LicenceEntry, checkHeader;

    Upstream[] upstreams;
    string error;
    expect(parseUpstreams(`{"schema":"flint.api-upstreams/1","upstreams":[{"project":"druntime","version":"v2.114.0",
        "repo":"flint","api":false,"url":"https://github.com/dlang/dmd/archive/refs/tags/v2.114.0.tar.gz",
        "sha256":"` ~ "a".replicate(64) ~ `","format":"tar.gz"}]}`, upstreams, error)).toEqual(true);
    expect(upstreams[0].api).toEqual(false);
    const druntime = LicenceEntry("druntime", "BSL-1.0", "port-source", "v2.114.0");
    enum header = "/**\n * Port of druntime v2.114.0 (https://github.com/dlang/dmd, tag v2.114.0), the D runtime:\n"
        ~ " * druntime/src/core/internal/gc/pooltable.d\n *\n * Copyright: D Language Foundation 2001 - 2021.\n"
        ~ " * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).\n *\n"
        ~ " * Modified by the Flint authors.\n */\nmodule flint.arena.sys.gc.pooltable;\n";
    expect(checkHeader("f.d", header, upstreams, [druntime], "BSL-1.0").length).toEqual(0);
    enum unlicensed = "/**\n * Port of druntime v2.114.0: x.d\n * Copyright: D Language Foundation.\n"
        ~ " * Modified by the Flint authors.\n */\nmodule m;\n";
    expect(checkHeader("f.d", unlicensed, upstreams, [druntime], "").length).toEqual(1);
}

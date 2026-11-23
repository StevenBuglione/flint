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
    expect(validSymbol("flint.http.HttpStatus")).toEqual(true);
    expect(validSymbol("flint.")).toEqual(false);
    expect(validSymbol("org.springframework.X")).toEqual(false);
    expect(validSymbol("flint.http..X")).toEqual(false);
    expect(validRule("R1")).toEqual(true);
    expect(validRule("R14")).toEqual(true);
    expect(validRule("R15")).toEqual(false);
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
        "org.x.web.HttpStatus":{"status":"ported","d":"flint.web.HttpStatus"}}}`, mapping, error);
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
    expect(error).toEqual("a.B: `R99` is not a rulebook rule, R1 to R14");
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
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import flint_tool.support.files : sha256File;
    import flint_tool.support.process : capture;

    const work = buildPath(tempDir(), "flint-api-fetch-" ~ randomUUID().toString());
    scope (exit)
        rmdirRecurse(work);
    mkdirRecurse(buildPath(work, "lib-1.0", "src", "main", "java", "p"));
    write(buildPath(work, "lib-1.0", "src", "main", "java", "p", "A.java"), "package p;\npublic class A { }\n");
    const archive = buildPath(work, "lib-1.0.tar.gz");
    expect(capture(["tar", "-czf", archive, "-C", work, "lib-1.0"]).ok).toEqual(true);
    const digest = sha256File(archive);

    Upstream[] upstreams;
    string error;
    expect(parseUpstreams(`{"schema":"flint.api-upstreams/1","upstreams":[{"project":"lib","version":"1.0",
        "url":"file://` ~ archive ~ `","sha256":"` ~ digest ~ `","format":"tar.gz","exclude":["docs"]}]}`,
            upstreams, error)).toEqual(true);
    expect(error).toEqual("");
    const pinned = findUpstream(upstreams, "lib", "1.0");
    expect(pinned.exclude).toEqual(["docs"]);
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

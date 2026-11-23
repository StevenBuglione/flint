module flint_tool.engine.aot_test;

import flint.test : expect;
import std.algorithm.searching : canFind;

@safe:

// ---- interface keys ----

private string hashOf(string source)
{
    import flint_tool.engine.aot.iface : ModuleInterface, readInterface;

    ModuleInterface found;
    assert(readInterface(source, found));
    return found.hash;
}

private enum service = "module shop.owners;\nimport flint.stereotype : Service;\n@safe:\n"
    ~ "@Service(\"owners\") class OwnerService\n{\n    int calls;\n    string find(long id)\n    {\n"
    ~ "        calls++;\n        return \"Ada\";\n    }\n}\nunittest\n{\n    assert(true);\n}\n";

@("editing a method body or a unittest keeps the interface key")
unittest
{
    import std.array : replace;

    const base = hashOf(service);
    expect(hashOf(service.replace("return \"Ada\";", "return \"Grace\";"))).toEqual(base);
    expect(hashOf(service.replace("calls++;", "calls += 2;"))).toEqual(base);
    expect(hashOf(service.replace("assert(true);", "assert(1 == 1);"))).toEqual(base);
}

@("changing a signature, a field or an attribute argument changes the interface key")
unittest
{
    import std.array : replace;

    const base = hashOf(service);
    expect(hashOf(service.replace("string find(long id)", "string find(int id)")) == base).toBeFalse();
    expect(hashOf(service.replace("int calls;", "long calls;")) == base).toBeFalse();
    expect(hashOf(service.replace("@Service(\"owners\")", "@Service(\"people\")")) == base).toBeFalse();
}

@("bodies that compile-time evaluation can reach stay in the interface")
unittest
{
    import std.array : replace;

    enum inferred = "module m;\nauto answer()\n{\n    return 42;\n}\n";
    expect(hashOf(inferred.replace("42", "43")) == hashOf(inferred)).toBeFalse();
    enum ctfe = "module m;\nstring path()\n{\n    return \"/a\";\n}\n@Get(path()) void handler()\n{\n}\n";
    expect(hashOf(ctfe.replace("\"/a\"", "\"/b\"")) == hashOf(ctfe)).toBeFalse();
    enum literal = "module m;\nenum table = () { return \"owners\"; }();\n";
    expect(hashOf(literal.replace("owners", "pets")) == hashOf(literal)).toBeFalse();
}

@("the interface reader lists the imported modules")
unittest
{
    import flint_tool.engine.aot.iface : ModuleInterface, readInterface;

    ModuleInterface found;
    assert(readInterface("module a.b;\nimport c.d : E, F;\nstatic import g;\nimport h = i.j;\n"
            ~ "void f()\n{\n    import k : l;\n    auto s = import(\"x\");\n}\n", found));
    expect(found.name).toEqual("a.b");
    expect(found.imports).toEqual(["c.d", "g", "i.j", "k"]);
}

// ---- merged annotations ----

private enum annotationTypes = `[
{"name":"flint.core.annotation.ClassRef","modules":["flint.core.annotation"],"meta":[],
"fields":[{"name":"name","type":{"name":"string","modules":[]},"default":null,"annotations":[]}]},
{"name":"flint.stereotype.Component","modules":["flint.stereotype"],"meta":[],"fields":[{"name":"value",
"type":{"name":"string","modules":[]},"default":null,"annotations":[]}]},
{"name":"flint.stereotype.Service","modules":["flint.stereotype"],
"meta":[{"type":"flint.stereotype.Component","modules":["flint.stereotype"],"values":{"value":null}}],
"fields":[{"name":"value","type":{"name":"string","modules":[]},"default":null,
"annotations":[{"type":"flint.core.annotation.AliasFor","modules":["flint.core.annotation"],
"values":{"attribute":null,"annotation":{"type":"flint.core.annotation.ClassRef","modules":[],
"values":{"name":"flint.stereotype.Component"}},"value":null}}]}]},
{"name":"m.RequestMapping","modules":["m"],"meta":[],"fields":[{"name":"value","type":{"name":"string[]",
"modules":[]},"default":[],"annotations":[{"type":"flint.core.annotation.AliasFor","modules":[],
"values":{"attribute":"path","annotation":{"type":"flint.core.annotation.ClassRef","modules":[],
"values":{"name":null}},"value":null}}]},{"name":"path","type":{"name":"string[]","modules":[]},"default":[],
"annotations":[{"type":"flint.core.annotation.AliasFor","modules":[],"values":{"attribute":"value",
"annotation":{"type":"flint.core.annotation.ClassRef","modules":[],"values":{"name":null}},"value":null}}]},
{"name":"method","type":{"name":"m.Method[]","modules":["m"]},"default":[],"annotations":[]}]},
{"name":"m.GetMapping","modules":["m"],"meta":[{"type":"m.RequestMapping","modules":["m"],
"values":{"value":[],"path":[],"method":[{"enum":"m.Method","modules":["m"],"name":"GET"}]}}],
"fields":[{"name":"value","type":{"name":"string[]","modules":[]},"default":[],
"annotations":[{"type":"flint.core.annotation.AliasFor","modules":[],"values":{"attribute":"path",
"annotation":{"type":"flint.core.annotation.ClassRef","modules":[],"values":{"name":"m.RequestMapping"}},
"value":null}}]}]},
{"name":"m.Config","modules":["m"],"meta":[],"fields":[{"name":"proxyBeanMethods","type":{"name":"bool",
"modules":[]},"default":true,"annotations":[]}]},
{"name":"m.App","modules":["m"],"meta":[{"type":"m.Config","modules":["m"],
"values":{"proxyBeanMethods":true}}],"fields":[{"name":"proxyBeanMethods","type":{"name":"bool","modules":[]},
"default":true,"annotations":[{"type":"flint.core.annotation.AliasFor","modules":[],
"values":{"attribute":null,"annotation":{"type":"flint.core.annotation.ClassRef","modules":[],
"values":{"name":"m.Config"}},"value":null}}]}]}
]`;

private imported!"flint_tool.engine.aot.merge".MergedSet mergedOf(string annotations)
{
    import flint_tool.engine.aot.merge : merge;
    import flint_tool.engine.aot.model : AnnotationType, ModuleModel, parseModule;

    ModuleModel model;
    string error;
    const document = `{"schema":"flint.aot.model/1","module":"m","types":[{"name":"T","fqn":"m.T","kind":"class",`
        ~ `"annotations":` ~ annotations ~ `}],"annotationTypes":` ~ annotationTypes ~ `}`;
    assert(parseModule(document, model, error), error);
    AnnotationType[string] types;
    foreach (ref type; model.annotationTypes)
        types[type.name] = type;
    return merge(model.types[0].annotations, types);
}

@("a meta-annotation is present with the attributes its declaring annotation aliases")
unittest
{
    const merged = mergedOf(`[{"type":"flint.stereotype.Service","modules":[],"values":{"value":"owners"}}]`);
    expect(merged.items.length).toEqual(2);
    expect(merged.get("flint.stereotype.Component").text("value")).toEqual("owners");
    expect(merged.items[1].distance).toEqual(1);
}

@("a composed mapping overrides its meta-annotation's path and keeps its method")
unittest
{
    const merged = mergedOf(`[{"type":"m.GetMapping","modules":[],"values":{"value":["/owners/{id}"]}}]`);
    const mapping = merged.get("m.RequestMapping");
    expect(mapping.get("path").strings).toEqual(["/owners/{id}"]);
    expect(mapping.get("value").strings).toEqual(["/owners/{id}"]);
    expect(mapping.get("method").items[0].text).toEqual("GET");
}

@("intra-annotation aliases mirror each other and conflicting values are reported")
unittest
{
    const mirrored = mergedOf(`[{"type":"m.RequestMapping","modules":[],"values":{"value":["/a"],"path":[]}}]`);
    expect(mirrored.get("m.RequestMapping").get("path").strings).toEqual(["/a"]);
    const conflicting = mergedOf(`[{"type":"m.RequestMapping","modules":[],"values":{"value":["/a"],"path":["/b"]}}]`);
    expect(conflicting.conflicts.length).toEqual(1);
}

@("a false boolean overrides a true default through @AliasFor")
unittest
{
    const merged = mergedOf(`[{"type":"m.App","modules":[],"values":{"proxyBeanMethods":false}}]`);
    expect(merged.get("m.Config").flag("proxyBeanMethods", true)).toBeFalse();
    const defaulted = mergedOf(`[{"type":"m.App","modules":[],"values":{"proxyBeanMethods":true}}]`);
    expect(defaulted.get("m.Config").flag("proxyBeanMethods", false)).toBeTrue();
}

// ---- conditions ----

@("profile expressions compile to D")
unittest
{
    import flint_tool.engine.aot.conditions : compileProfile;

    string code;
    string error;
    assert(compileProfile("prod", code, error));
    expect(code).toEqual(`c.acceptsProfile("prod")`);
    assert(compileProfile("prod & !cloud", code, error));
    expect(code).toEqual(`(c.acceptsProfile("prod") && !c.acceptsProfile("cloud"))`);
    assert(compileProfile("(a | b) & c", code, error));
    expect(code).toEqual(`((c.acceptsProfile("a") || c.acceptsProfile("b")) && c.acceptsProfile("c"))`);
}

@("malformed profile expressions are rejected as Spring rejects them")
unittest
{
    import flint_tool.engine.aot.conditions : compileProfile;

    string code;
    string error;
    expect(compileProfile("a & b | c", code, error)).toBeFalse();
    expect(error.canFind("mixed '&' and '|'")).toBeTrue();
    expect(compileProfile("", code, error)).toBeFalse();
    expect(compileProfile("a &", code, error)).toBeFalse();
    expect(compileProfile("(a", code, error)).toBeFalse();
}

// ---- derived queries ----

private imported!"flint_tool.engine.aot.query".Domain owners()
{
    import flint_tool.engine.aot.query : Column, Domain;

    return Domain("shop.Owner", "Owner", "owners", [
        Column("id", "id"), Column("firstName", "first_name"), Column("lastName", "surname"),
        Column("city", "city"), Column("active", "active"), Column("address", "address", true)
    ]);
}

private imported!"flint_tool.engine.aot.query".DerivedQuery derived(string method, string returns, string[] parameters)
{
    import flint_tool.engine.aot.query : DerivedQuery, QueryError, deriveQuery;

    DerivedQuery query;
    QueryError error;
    const domain = owners();
    assert(deriveQuery(method, returns, parameters, domain, query, error), error.message);
    return query;
}

@("derived queries translate subjects, operators, ordering and limits")
unittest
{
    import flint_tool.engine.aot.query : QueryKind;

    auto query = derived("findByLastNameIgnoreCaseOrderByFirstNameAsc", "shop.Owner[]", ["lastName"]);
    expect(query.sql).toEqual("SELECT id, first_name, surname, city, active, address FROM owners "
            ~ "WHERE UPPER(surname) = UPPER(?) ORDER BY first_name ASC");
    expect(query.kind).toEqual(QueryKind.list);
    query = derived("findFirst2ByCityAndFirstNameStartingWith", "shop.Owner[]", ["city", "prefix"]);
    expect(query.sql.canFind("WHERE city = ? AND first_name LIKE ? LIMIT 2")).toBeTrue();
    expect(query.likeTransforms).toEqual(["", "starting"]);
    query = derived("countByActiveTrueOrCityIn", "long", ["cities"]);
    expect(query.sql).toEqual("SELECT COUNT(*) FROM owners WHERE (active = TRUE) OR (city IN (?))");
    query = derived("existsByIdBetween", "bool", ["low", "high"]);
    expect(query.sql).toEqual("SELECT 1 FROM owners WHERE id BETWEEN ? AND ? LIMIT 1");
    expect(query.parameters).toEqual(["low", "high"]);
    query = derived("deleteByCityIsNull", "void", []);
    expect(query.sql).toEqual("DELETE FROM owners WHERE city IS NULL");
    query = derived("findDistinctByLastNameOrderByCityDescIdAsc", "shop.Owner[]", ["lastName"]);
    expect(query.sql.canFind("SELECT DISTINCT ")).toBeTrue();
    expect(query.sql.canFind("ORDER BY city DESC, id ASC")).toBeTrue();
    query = derived("findByCityNot", "flint.java.util.Optional!(shop.Owner)", ["city"]);
    expect(query.kind).toEqual(QueryKind.optional);
    expect(query.sql.canFind("WHERE city <> ?")).toBeTrue();
}

@("invalid derived queries name Spring Data's problem")
unittest
{
    import flint_tool.engine.aot.query : DerivedQuery, QueryError, deriveQuery;

    DerivedQuery query;
    QueryError error;
    const domain = owners();
    expect(deriveQuery("findByColour", "x[]", ["c"], domain, query, error)).toBeFalse();
    expect(error.code).toEqual("FLINT-E1101");
    expect(error.message).toEqual("No property 'colour' found for type 'Owner'");
    expect(deriveQuery("findByAddressStreet", "x[]", ["s"], domain, query, error)).toBeFalse();
    expect(error.code).toEqual("FLINT-E1114");
    expect(deriveQuery("findByCity", "x[]", [], domain, query, error)).toBeFalse();
    expect(deriveQuery("findByCity", "x[]", ["a", "b"], domain, query, error)).toBeFalse();
    expect(deriveQuery("fetchByCity", "x[]", ["a"], domain, query, error)).toBeFalse();
}

// ---- names and paths ----

@("Spring's naming rules: bean names, table names, entry points and path combination")
unittest
{
    import flint_tool.engine.aot.names : beanName, entryPoint;
    import flint_tool.engine.aot.plan : combinePaths;
    import flint_tool.engine.aot.query : snakeCase;

    expect(beanName("OwnerService")).toEqual("ownerService");
    expect(beanName("URLService")).toEqual("URLService");
    expect(snakeCase("OwnerVisit")).toEqual("owner_visit");
    expect(snakeCase("firstName")).toEqual("first_name");
    expect(snakeCase("HTTPRequest")).toEqual("http_request");
    expect(entryPoint("shop.owners")).toEqual("flint_aot_register_4shop6owners");
    expect(combinePaths(["/owners"], ["/{id}"])).toEqual(["/owners/{id}"]);
    expect(combinePaths(["/owners/"], ["/{id}"])).toEqual(["/owners/{id}"]);
    expect(combinePaths(["/owners"], ["{id}"])).toEqual(["/owners/{id}"]);
    expect(combinePaths(["/owners"], null)).toEqual(["/owners"]);
    expect(combinePaths(null, ["/a", "/b"])).toEqual(["/a", "/b"]);
}

// ---- the sample application, through the compiler ----

private string repositoryRoot()
{
    import std.file : exists;
    import std.path : absolutePath, buildNormalizedPath, buildPath;

    string directory = absolutePath(".");
    foreach (attempt; 0 .. 6)
    {
        if (exists(buildPath(directory, "tests", "aot", "sample")))
            return buildNormalizedPath(directory);
        directory = buildPath(directory, "..");
    }
    assert(false, "tests/aot/sample not found above the working directory");
}

/// The DMD that runs the extraction compile: FLINT_AOT_TEST_DMD, else `dmd` on PATH. Never skipped.
private string compiler()
{
    import std.process : environment;

    return environment.get("FLINT_AOT_TEST_DMD", "dmd");
}

private string copyFixture(string name)
{
    import std.conv : to;
    import std.file : copy, dirEntries, exists, isFile, mkdirRecurse, rmdirRecurse, SpanMode, tempDir;
    import std.path : buildPath, dirName, relativePath;
    import std.process : thisProcessID;

    const source = buildPath(repositoryRoot(), "tests", "aot", name);
    const target = buildPath(tempDir(), "flint-aot-test-" ~ thisProcessID.to!string, name);
    if (exists(target))
        rmdirRecurse(target);
    foreach (entry; dirEntries(source, SpanMode.depth))
    {
        if (!isFile(entry.name))
            continue;
        const destination = buildPath(target, relativePath(entry.name, source));
        mkdirRecurse(dirName(destination));
        copy(entry.name, destination);
    }
    return target;
}

private void remove(string project)
{
    import std.file : exists, rmdirRecurse;
    import std.path : dirName;

    if (exists(dirName(project)))
        rmdirRecurse(dirName(project));
}

private imported!"flint_tool.engine.aot.driver".AotOutcome generate(string project)
{
    import std.path : buildPath;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(repositoryRoot(), "tests", "aot", "annotations"),
        "-I" ~ buildPath(repositoryRoot(), "packages", "engine-aot", "source")
    ];
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    return runAot(request);
}

private void edit(string path, string from, string to)
{
    import std.array : replace;
    import std.file : readText, write;
    import std.string : indexOf;

    const text = readText(path);
    assert(text.indexOf(from) >= 0, from);
    write(path, text.replace(from, to));
}

@("the sample generates, and only interface edits run the extraction compile again")
unittest
{
    import std.path : buildPath;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    auto first = generate(project);
    expect(first.extractionErrors).toEqual("");
    expect(first.ok).toBeTrue();
    expect(first.application).toEqual("shop.app.ShopApplication");
    expect(first.extracted).toEqual(5);
    expect(first.generated).toEqual(5);
    expect(first.removed).toEqual([
        "missing: @ConditionalOnClass: flint.does.not.Exist is not in the closure"
    ]);

    auto unchanged = generate(project);
    expect(unchanged.extracted).toEqual(0);
    expect(unchanged.written).toEqual(0);

    edit(buildPath(project, "src", "shop", "owners.d"), `return id == 1 ? "Ada" : "Grace";`,
            `return id == 1 ? "Ada" : "Hopper";`);
    auto body_ = generate(project);
    expect(body_.extracted).toEqual(0);
    expect(body_.written).toEqual(0);

    edit(buildPath(project, "src", "shop", "web.d"), `@GetMapping("/{id}")`, `@GetMapping("/{id}/greeting")`);
    auto mapping = generate(project);
    expect(mapping.ok).toBeTrue();
    expect(mapping.extracted).toEqual(1);
    expect(mapping.written).toEqual(1);
}

@("the sample's generated code compiles with flint:engine-aot and behaves as Spring does")
unittest
{
    import std.algorithm.iteration : filter, map;
    import std.algorithm.searching : endsWith;
    import std.array : array;
    import std.file : dirEntries, readText, SpanMode;
    import std.path : buildPath;
    import flint_tool.support.process : Launch, capture;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    auto outcome = generate(project);
    expect(outcome.ok).toBeTrue();
    string[] sources;
    foreach (directory; ["src", ".flint/generated/aot"])
        foreach (entry; dirEntries(buildPath(project, directory), "*.d", SpanMode.depth))
            sources ~= entry.name;
    const root = repositoryRoot();
    const binary = buildPath(project, "sample-app");
    Launch launch;
    launch.directory = project;
    const built = capture([
        compiler(), "-preview=dip1000", "-I" ~ buildPath(root, "tests", "aot", "annotations"),
        "-I" ~ buildPath(root, "packages", "engine-aot", "source"),
        "-I" ~ buildPath(root, "tests", "aot", "support"), "-I" ~ buildPath(project, "src"),
        "-I" ~ buildPath(project, ".flint", "generated", "aot"), "-i", "-of=" ~ binary,
        buildPath(project, "main.d")
    ] ~ sources, launch);
    expect(built.combined()).toEqual("");
    expect(built.ok).toBeTrue();
    const ran = capture([binary], launch);
    expect(ran.ok).toBeTrue();
    expect(ran.output).toEqual(readText(buildPath(root, "tests", "aot", "sample", "expected.txt")));
}

@("every generator diagnostic names its declaration")
unittest
{
    import std.algorithm.searching : canFind;

    const project = copyFixture("diagnostics");
    scope (exit)
        remove(project);
    auto outcome = generate(project);
    expect(outcome.ok).toBeFalse();
    string[] codes;
    foreach (ref item; outcome.diagnostics)
    {
        codes ~= item.code;
        expect(item.file).toEqual("src/bad/app.d");
        expect(item.line > 0).toBeTrue();
    }
    foreach (code; [
        "FLINT-E1101", "FLINT-E1102", "FLINT-E1105", "FLINT-E1106", "FLINT-E1107", "FLINT-E1108",
        "FLINT-E1109", "FLINT-E1110", "FLINT-E1111", "FLINT-E1112", "FLINT-E1113", "FLINT-E1114",
        "FLINT-E1115"
    ])
        expect(codes.canFind(code)).toBeTrue();
}

@("a project without @FlintBootApplication runs no extraction")
unittest
{
    import std.file : write;
    import std.path : buildPath;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    write(buildPath(project, "src", "shop", "app.d"), "module shop.app;\n");
    auto outcome = generate(project);
    expect(outcome.active).toBeFalse();
    expect(outcome.extracted).toEqual(0);
}

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

// ---- SpEL ----

private final class TestScope : imported!"flint_tool.engine.aot.spel".SpelScope
{
    import flint_tool.engine.aot.spel : Compiled;

    bool variable(string name, out Compiled result)
    {
        if (name != "id")
            return false;
        result = Compiled("id", "long");
        return true;
    }

    bool bean(string name, out Compiled result)
    {
        if (name != "clock")
            return false;
        result = Compiled("clock", "shop.Clock");
        return true;
    }

    Compiled placeholder(string expression)
    {
        return Compiled("p(\"" ~ expression ~ "\")", "string");
    }

    bool root(string name, Compiled[] arguments, bool call, out Compiled result)
    {
        if (name != "hasRole" || !call)
            return false;
        result = Compiled("ctx.hasRole(" ~ arguments[0].code ~ ")", "Any");
        return true;
    }

    bool member(string type, string name, Compiled[], bool, string target, out Compiled result)
    {
        if (type != "shop.Clock" || name != "now")
            return false;
        result = Compiled(target ~ ".now()", "long");
        return true;
    }
}

private string spel(string source)
{
    import flint_tool.engine.aot.spel : Compiled, SpelError, compileSpel;

    Compiled result;
    SpelError error;
    assert(compileSpel(source, new TestScope, result, error), error.message);
    return result.code ~ " : " ~ result.type;
}

private string spelError(string source)
{
    import flint_tool.engine.aot.spel : Compiled, SpelError, compileSpel;

    Compiled result;
    SpelError error;
    assert(!compileSpel(source, new TestScope, result, error), source);
    return error.message;
}

@("SpEL compiles to typed D: literals, arithmetic, strings, logic, ternary and Elvis")
unittest
{
    expect(spel("1 + 2 * 3")).toEqual("(1L + (2L * 3L)) : long");
    expect(spel("10 / 4.0")).toEqual("(cast(double) (10L) / 4.0) : double");
    expect(spel("2 ^ 10")).toEqual("(2L ^^ 10L) : long");
    expect(spel("'a' + 1")).toEqual(`("a" ~ imported!"std.conv".to!(string)(1L)) : string`);
    expect(spel("'it''s'")).toEqual(`"it's" : string`);
    expect(spel("#id > 10 and not (#id == 99)")).toEqual("((id > 10L) && !((id == 99L))) : bool");
    expect(spel("#id gt 1 ? 'big' : 'small'")).toEqual(`((id > 1L) ? "big" : "small") : string`);
    expect(spel("'x'.toUpperCase().length()")).toEqual(`cast(long) (imported!"std.uni".toUpper("x")).length : long`);
    expect(spel("${a} ?: 'none'")).toEqual(`((p("${a}")).length ? p("${a}") : "none") : string`);
    expect(spel("${port} + 1")).toEqual(`(imported!"std.conv".to!(long)(p("${port}")) + 1L) : long`);
    expect(spel("@clock.now() * 2")).toEqual("(clock.now() * 2L) : long");
    expect(spel("hasRole('ADMIN') or #id == 1")).toEqual(`((ctx.hasRole("ADMIN")).get!(bool)() || (id == 1L)) : bool`);
    expect(spel("#id == null")).toEqual("((id) is null) : bool");
}

@("SpEL outside the compiled subset is reported, never interpreted at runtime")
unittest
{
    expect(spelError("T(java.lang.Math).random()").canFind("type references")).toBeTrue();
    expect(spelError("#missing").canFind("unknown variable `#missing`")).toBeTrue();
    expect(spelError("@nobody").canFind("no bean named `nobody`")).toBeTrue();
    expect(spelError("@clock.later()").canFind("has no method `later`")).toBeTrue();
    expect(spelError("'a' - 1").canFind("is not a number")).toBeTrue();
    expect(spelError("#id > ").canFind("ends early")).toBeTrue();
    expect(spelError("names.?[length() > 1]").length > 0).toBeTrue();
}

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

/// The source directory of flint:engine-aot, from policy/framework.json, so the test follows the package when it
/// moves (the repo split).
private string runtimeSource()
{
    import std.file : readText;
    import std.json : parseJSON;
    import std.path : buildPath;

    const policy = parseJSON(readText(buildPath(repositoryRoot(), "policy", "framework.json")));
    return buildPath(repositoryRoot(), policy["modules"]["engine-aot"]["directory"].str, "source");
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
        "-I" ~ buildPath(repositoryRoot(), "tests", "aot", "annotations"), "-I" ~ runtimeSource()
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
    expect(first.extracted).toEqual(6);
    expect(first.generated).toEqual(6);
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
        "-I" ~ runtimeSource(), "-I" ~ buildPath(root, "tests", "aot", "support"),
        "-I" ~ buildPath(project, "src"), "-I" ~ buildPath(project, ".flint", "generated", "aot"),
        "-i", "-of=" ~ binary, buildPath(project, "main.d")
    ] ~ sources, launch);
    expect(built.combined()).toEqual("");
    expect(built.ok).toBeTrue();
    // Contract 2 fields.
    const web = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "shop", "web.d"));
    expect(web.canFind(`mapping.beanType = "shop.web.OwnerController";`)).toBeTrue();
    expect(web.canFind("mapping.typeAnnotations = [")).toBeTrue();
    expect(web.canFind("definition.rank = ")).toBeTrue();
    const data = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "shop", "data.d"));
    expect(data.canFind("&construct_Owner_0, true)")).toBeTrue();
    expect(data.canFind("descriptor.enumValue = &enum_OwnerStatus;")).toBeTrue();
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
    bool securityReported;
    foreach (ref item; outcome.diagnostics)
    {
        securityReported = securityReported || item.message.canFind("unknown function `frobnicate()`");
        codes ~= item.code;
        expect(item.file).toEqual("src/bad/app.d");
        expect(item.line > 0).toBeTrue();
    }
    expect(securityReported).toBeTrue();
    foreach (code; [
        "FLINT-E1101", "FLINT-E1102", "FLINT-E1105", "FLINT-E1106", "FLINT-E1107", "FLINT-E1108",
        "FLINT-E1109", "FLINT-E1110", "FLINT-E1111", "FLINT-E1112", "FLINT-E1113", "FLINT-E1114",
        "FLINT-E1115"
    ])
        expect(codes.canFind(code)).toBeTrue();
}

@("ADR-029's @FlintApplication is an alias of @FlintBootApplication")
unittest
{
    import std.path : buildPath;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    edit(buildPath(project, "src", "shop", "app.d"),
            "import flint.boot.autoconfigure : FlintBootApplication;", "import flint.boot : FlintApplication;");
    edit(buildPath(project, "src", "shop", "app.d"), "@FlintBootApplication", "@FlintApplication");
    auto outcome = generate(project);
    expect(outcome.ok).toBeTrue();
    expect(outcome.application).toEqual("shop.app.ShopApplication");
}

@("auto-configurations: excluded at build time by excludeName, switched off at startup by the property")
unittest
{
    import std.file : readText;
    import std.path : buildPath;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    edit(buildPath(project, "src", "shop", "app.d"), "@FlintBootApplication final class",
            `@FlintBootApplication(excludeName: ["flintsample.autoconfig.ExcludedAutoConfiguration"]) final class`);
    const root = repositoryRoot();
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(root, "tests", "aot", "annotations"),
        "-I" ~ buildPath(root, "tests", "aot", "autoconfig", "source")
    ];
    request.flags = ["-preview=dip1000"];
    request.packageDirectories = [buildPath(root, "tests", "aot", "autoconfig")];
    request.environmentKey = "test";
    auto outcome = runAot(request);
    expect(outcome.extractionErrors).toEqual("");
    expect(outcome.ok).toBeTrue();
    expect(outcome.removed.canFind(
            "flintsample.autoconfig.ExcludedAutoConfiguration: excluded by the application's "
            ~ "exclude or excludeName")).toBeTrue();
    const generated = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot",
            "flintsample", "autoconfig.d"));
    expect(generated.canFind(`"flintsample.autoconfig.WidgetAutoConfiguration"`)).toBeTrue();
    expect(generated.canFind("ExcludedAutoConfiguration\";")).toBeFalse();
    expect(generated.canFind(`c.property("flint.boot.enableautoconfiguration", "true", true) `
            ~ `&& !c.isAutoConfigurationExcluded("flintsample.autoconfig.WidgetAutoConfiguration") `
            ~ `&& !c.hasBeanOfType("flintsample.autoconfig.Widget")`)).toBeTrue();
}

/// Source directories of the DUB closure of `roots` (repository-relative package directories), following each
/// dub.sdl's `dependency` lines, so the list follows packages when they move. `flint:x` names resolve to
/// packages/x or framework/x. framework/java comes first: while framework/p1-interim exists it shadows
/// flint.java.lang for packages that do not depend on it.
private string[] closureImports(scope const string[] roots)
{
    import std.algorithm.searching : canFind, startsWith;
    import std.file : exists, isDir, readText;
    import std.path : buildNormalizedPath, buildPath;
    import std.regex : matchAll, regex;

    const root = repositoryRoot();
    string[] seen;
    void visit(string directory)
    {
        directory = buildNormalizedPath(directory);
        if (seen.canFind(directory))
            return;
        seen ~= directory;
        const recipe = buildPath(directory, "dub.sdl");
        if (!exists(recipe))
            return;
        foreach (match; matchAll(readText(recipe), regex(`(?m)^\s*dependency\s+"([^"]+)"(?:\s+path="([^"]+)")?`)))
        {
            const name = match[1];
            if (name.startsWith("flint:"))
            {
                foreach (base; ["packages", "framework"])
                {
                    const candidate = buildPath(root, base, name[6 .. $]);
                    if (exists(candidate) && isDir(candidate))
                    {
                        visit(candidate);
                        break;
                    }
                }
            }
            else if (match[2].length)
                visit(buildPath(directory, match[2]));
        }
    }

    foreach (item; roots)
        visit(buildPath(root, item));
    string[] flags = ["-I" ~ buildPath(root, "framework", "java", "source")];
    foreach (directory; seen)
    {
        if (exists(buildPath(directory, "source")))
            flags ~= "-I" ~ buildPath(directory, "source");
    }
    return flags;
}

@("gs-rest-service against the real web annotations: the table is Spring's and the code compiles")
unittest
{
    import std.algorithm.iteration : map;
    import std.array : array;
    import std.file : dirEntries, readText, SpanMode;
    import std.path : buildPath;
    import flint_tool.engine.aot.driver : AotRequest, runAot;
    import flint_tool.support.process : Launch, capture;

    const project = copyFixture("gs-rest-service");
    scope (exit)
        remove(project);
    // The real web stack. Boot comes from the fixture annotations until framework/web leaves p1-interim
    // (coordination item 1): today Boot's flint:core and web's p1-interim both declare flint.core.annotation.
    auto imports = closureImports(["framework/web", "framework/webmvc"]) ~ [
        "-I" ~ buildPath(repositoryRoot(), "tests", "aot", "annotations")
    ];
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = imports;
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    auto outcome = runAot(request);
    expect(outcome.extractionErrors).toEqual("");
    expect(outcome.ok).toBeTrue();
    expect(outcome.application).toEqual("com.example.restservice.restserviceapplication.RestServiceApplication");
    const controller = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot",
            "com", "example", "restservice", "greetingcontroller.d"));
    expect(controller.canFind(`mapping.paths = ["/greeting"];`)).toBeTrue();
    expect(controller.canFind(`mapping.methods = ["GET"];`)).toBeTrue();
    expect(controller.canFind(`a.kind = ArgumentKind.requestParam; a.name = "name"; a.type = "string"; `
            ~ `a.required = false; a.defaultValue = "World";`)).toBeTrue();
    expect(controller.canFind("mapping.responseBody = true;")).toBeTrue();
    string[] sources;
    foreach (directory; ["src", ".flint/generated/aot"])
        foreach (entry; dirEntries(buildPath(project, directory), "*.d", SpanMode.depth))
            sources ~= entry.name;
    Launch launch;
    launch.directory = project;
    const checked = capture([
        compiler(), "-o-", "-preview=dip1000", "-I" ~ buildPath(project, "src"),
        "-I" ~ buildPath(project, ".flint", "generated", "aot")
    ] ~ imports ~ sources, launch);
    expect(checked.combined()).toEqual("");
    expect(checked.ok).toBeTrue();
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

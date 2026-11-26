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

@("the describer's output reads the same with CRLF line ends (Windows)")
unittest
{
    import flint_tool.engine.aot.extract : ExtractionResult, readOutput;

    ExtractionResult result;
    readOutput("FLINT-AOT-MODULE shop.app\r\nFLINT-AOT-PRESENT flint.x.Y true\r\n"
            ~ "FLINT-AOT-PRESENT flint.x.Z false\r\n", result);
    expect(result.errors).toEqual("");
    expect(result.models.length).toEqual(1);
    expect(result.models[0].name).toEqual("shop.app");
    expect(result.present["flint.x.Y"]).toBeTrue();
    expect(result.present["flint.x.Z"]).toBeFalse();
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

// Fixture annotation types in the model's JSON, for the alias cases of Spring's MergedAnnotationsTests.

/// An attribute: its name, D type, default (JSON) and, optionally, `@AliasFor(annotation, attribute)`.
private string attribute(string name, string type, string default_, string target = null,
        string aliased = null, bool alias_ = false)
{
    const annotations = alias_ || target.length || aliased.length
        ? `[{"type":"flint.core.annotation.AliasFor",` ~ `"modules":[],"values":{"attribute":` ~ (aliased.length
                ? `"` ~ aliased ~ `"` : "null")
        ~ `,"annotation":{"type":"flint.core.annotation.ClassRef","modules":[],"values":{"name":` ~ (
                target.length ? `"` ~ target ~ `"` : "null") ~ `}},"value":null}}]` : "[]";
    return `{"name":"` ~ name ~ `","type":{"name":"` ~ type ~ `","modules":[]},"default":` ~ default_
        ~ `,"annotations":` ~ annotations ~ `}`;
}

/// An annotation type with its meta-annotation declarations (JSON) and attributes.
private string annotationType(string name, string meta, string[] attributes...)
{
    import std.array : join;

    return `{"name":"` ~ name ~ `","modules":["m"],"meta":` ~ meta ~ `,"fields":[` ~ attributes.join(",") ~ `]}`;
}

/// A use of `type` with `values` (JSON object members).
private string use(string type, string values = "")
{
    return `{"type":"` ~ type ~ `","modules":["m"],"values":{` ~ values ~ `}}`;
}

private imported!"flint_tool.engine.aot.merge".MergedSet mergedWith(string types, string annotations)
{
    import flint_tool.engine.aot.merge : merge;
    import flint_tool.engine.aot.model : AnnotationType, ModuleModel, parseModule;

    ModuleModel model;
    string error;
    const document = `{"schema":"flint.aot.model/1","module":"m","types":[{"name":"T","fqn":"m.T","kind":"class",`
        ~ `"annotations":` ~ annotations ~ `}],"annotationTypes":[` ~ types ~ `]}`;
    assert(parseModule(document, model, error), error);
    AnnotationType[string] index;
    foreach (ref type; model.annotationTypes)
        index[type.name] = type;
    return merge(model.types[0].annotations, index);
}

/// `@Meta(foo, bar)`, the root of the alias cases.
private enum metaType = annotationType("m.Meta", "[]", attribute("foo", "string", `""`),
            attribute("bar", "string", `""`), attribute("packages", "string[]", "[]"));

@("an explicit alias maps its attribute's default too (FlintAliasForMetaDefaultOverride)")
unittest
{
    const only = annotationType("m.OnlyValue", `[` ~ use("m.Meta", `"foo":"declared"`) ~ `]`,
            attribute("value", "string", `"fromValue"`, "m.Meta", "foo"));
    const merged = mergedWith(metaType ~ "," ~ only, `[` ~ use("m.OnlyValue", `"value":"fromValue"`) ~ `]`);
    expect(merged.conflicts).toEqual(cast(string[]) null);
    expect(merged.get("m.Meta").text("foo")).toEqual("fromValue");
}

@("an alias may target a meta-meta-annotation, and the nearest declaration wins")
unittest
{
    const middle = annotationType("m.Middle", `[` ~ use("m.Meta", `"bar":"middle"`) ~ `]`,
            attribute("bar", "string", `""`, "m.Meta", "bar"));
    const top = annotationType("m.Top", `[` ~ use("m.Middle") ~ `]`, attribute("foo", "string", `""`,
            "m.Meta", "foo"), attribute("bar", "string", `""`, "m.Meta", "bar"));
    const merged = mergedWith(metaType ~ "," ~ middle ~ "," ~ top, `[` ~ use("m.Top",
            `"foo":"top","bar":"topBar"`) ~ `]`);
    expect(merged.conflicts).toEqual(cast(string[]) null);
    expect(merged.get("m.Meta").text("foo")).toEqual("top");
    expect(merged.get("m.Meta").text("bar")).toEqual("topBar");
    expect(merged.items[2].distance).toEqual(2);
}

@("a single value aliasing an array attribute becomes a one-element array")
unittest
{
    const scan = annotationType("m.Scan", `[` ~ use("m.Meta") ~ `]`, attribute("pkg", "string", `""`,
            "m.Meta", "packages"));
    const merged = mergedWith(metaType ~ "," ~ scan, `[` ~ use("m.Scan", `"pkg":"com.example"`) ~ `]`);
    expect(merged.conflicts).toEqual(cast(string[]) null);
    expect(merged.get("m.Meta").get("packages").strings).toEqual(["com.example"]);
}

@("implicit aliases mirror each other and conflict when they differ")
unittest
{
    const implicit = annotationType("m.Implicit", `[` ~ use("m.Meta") ~ `]`, attribute("xml",
            "string", `""`, "m.Meta", "foo"), attribute("groovy", "string", `""`, "m.Meta", "foo"));
    const merged = mergedWith(metaType ~ "," ~ implicit, `[` ~ use("m.Implicit", `"groovy":"g.groovy"`) ~ `]`);
    expect(merged.conflicts).toEqual(cast(string[]) null);
    expect(merged.get("m.Implicit").text("xml")).toEqual("g.groovy");
    expect(merged.get("m.Meta").text("foo")).toEqual("g.groovy");
    const conflicting = mergedWith(metaType ~ "," ~ implicit, `[` ~ use("m.Implicit", `"xml":"a","groovy":"b"`) ~ `]`);
    expect(conflicting.conflicts.length > 0).toBeTrue();
}

@("aliases inside nested annotation values are resolved")
unittest
{
    const filter = annotationType("m.Filter", "[]", attribute("value", "string[]", "[]", null,
            "classes"), attribute("classes", "string[]", "[]", null, "value"));
    const scan = annotationType("m.Scan", "[]", attribute("excludeFilters", "m.Filter[]", "[]"));
    const nested = `{"type":"m.Filter","modules":["m"],"values":{"value":["m.Skipped"],"classes":[]}}`;
    const merged = mergedWith(filter ~ "," ~ scan, `[` ~ use("m.Scan", `"excludeFilters":[` ~ nested ~ `]`) ~ `]`);
    expect(merged.conflicts).toEqual(cast(string[]) null);
    const filters = merged.get("m.Scan").get("excludeFilters");
    expect(filters.items.length).toEqual(1);
    expect(filters.items[0].nested[0].get("classes").strings).toEqual(["m.Skipped"]);
}

@("misconfigured @AliasFor declarations are reported, as Spring throws AnnotationConfigurationException")
unittest
{
    import std.algorithm.searching : canFind;

    const oneSided = annotationType("m.OneSided", "[]", attribute("value", "string", `""`, null,
            "path"), attribute("path", "string", `""`));
    const defaults = annotationType("m.Defaults", "[]", attribute("value", "string", `"a"`, null,
            "path"), attribute("path", "string", `"b"`, null, "value"));
    const notMeta = annotationType("m.NotMeta", "[]", attribute("foo", "string", `""`, "m.Meta", "foo"));
    const typed = annotationType("m.Typed", `[` ~ use("m.Meta") ~ `]`, attribute("foo", "long", "0", "m.Meta", "foo"));
    const all = metaType ~ "," ~ oneSided ~ "," ~ defaults ~ "," ~ notMeta ~ "," ~ typed;
    const expected = [
        "m.OneSided": "must be declared as an @AliasFor", "m.Defaults": "must have the same default",
        "m.NotMeta": "which is not a meta-annotation", "m.Typed": "does not match"
    ];
    foreach (type, message; expected)
    {
        const merged = mergedWith(all, `[` ~ use(type) ~ `]`);
        bool found;
        foreach (conflict; merged.conflicts)
            found = found || conflict.canFind(message);
        expect(found).toBeTrue();
    }
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

    private Compiled[string] variables;

    bool variable(string name, out Compiled result)
    {
        if (auto bound = name in variables)
        {
            result = *bound;
            return true;
        }
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
    expect(spel("1 + 2 * 3")).toEqual("(1 + (2 * 3)) : int");
    enum runtime = `imported!"flint.engine.aot.expression".`;
    expect(spel("10 / 4.0")).toEqual("(cast(double) (10) / " ~ runtime ~ "spelDouble(4.0)) : double");
    expect(spel("2 ^ 10")).toEqual(runtime ~ "spelPowLong(cast(long) (2), cast(long) (10)) : long");
    expect(spel("'a' + 1")).toEqual(`("a" ~ imported!"std.conv".to!(string)(1)) : string`);
    expect(spel("'it''s'")).toEqual(`"it's" : string`);
    expect(spel("#id > 10 and not (#id == 99)")).toEqual(
            "((id > cast(long) (10)) && !((id == cast(long) (99)))) : bool");
    expect(spel("#id gt 1 ? 'big' : 'small'")).toEqual(`((id > cast(long) (1)) ? "big" : "small") : string`);
    expect(spel("'x'.toUpperCase().length()")).toEqual(`cast(int) (imported!"std.uni".toUpper("x")).length : int`);
    expect(spel("${a} ?: 'none'")).toEqual(`((p("${a}")).length ? p("${a}") : "none") : string`);
    expect(spel("${port} + 1")).toEqual(`(imported!"std.conv".to!(long)(p("${port}")) + cast(long) (1)) : long`);
    expect(spel("@clock.now() * 2")).toEqual("(clock.now() * cast(long) (2)) : long");
    expect(spel("hasRole('ADMIN') or #id == 1")).toEqual(
            `((ctx.hasRole("ADMIN")).get!(bool)() || (id == cast(long) (1))) : bool`);
    expect(spel("#id == null")).toEqual("(" ~ runtime ~ "spelIsNull(id)) : bool");
    // Java's literal typing and binary numeric promotion (sol-template's parity corpus): an unsuffixed integer
    // literal is an int, so int arithmetic wraps at 32 bits; L makes a long, f a float, '.', an exponent or d a
    // double; an int literal outside the int range is an error, as Spring's NOT_AN_INTEGER.
    expect(spel("2147483647 + 1")).toEqual("(2147483647 + 1) : int");
    // Spring orders null first and compares strings by UTF-16 units; its textual operators ignore case.
    expect(spel("null < 0")).toEqual("!(" ~ runtime ~ "spelIsNull(0)) : bool");
    expect(spel("#id >= null")).toEqual("(" ~ runtime ~ "spelIsNull(id) || true) : bool");
    expect(spel("null <= null")).toEqual("true : bool");
    // Spring's ternary yields the chosen branch's own value; Elvis keeps a number and replaces null.
    enum any = `imported!"flint.engine.aot.any".Any`;
    expect(spel("true ? 1 : 2L")).toEqual("(true ? " ~ any ~ ".of(1) : " ~ any ~ ".of(2L)) : Any");
    expect(spel("null ?: 'x'")).toEqual(`"x" : string`);
    expect(spel("0 ?: 1")).toEqual("0 : int");
    expect(spel("'a' lt 'b'")).toEqual("(" ~ runtime ~ `spelCompareStrings("a", "b") < 0) : bool`);
    expect(spel("2 Ge 1 AND NOT (3 Div 2 EQ 2)")).toEqual("((2 >= 1) && !(((3 / 2) == 2))) : bool");
    expect(spel("2147483647L + 1")).toEqual("(2147483647L + cast(long) (1)) : long");
    expect(spel("1.5f * 2")).toEqual("(" ~ runtime ~ "spelFloat(1.5f) * cast(float) (2)) : float");
    expect(spel("1e3 + 2d")).toEqual("(" ~ runtime ~ "spelDouble(1e3) + " ~ runtime ~ "spelDouble(2.0)) : double");
    expect(spel("-0x7F")).toEqual("(-0x7F) : int");
    expect(spel("'abc'.length() + 1L")).toEqual(`(cast(long) (cast(int) ("abc").length) + 1L) : long`);
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
    expect(spelError("2147483648").canFind("cannot be parsed as an int")).toBeTrue();
    expect(spelError("0x80000000").canFind("cannot be parsed as an int")).toBeTrue();
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

@("compiled SpEL agrees with the shared parity corpus")
unittest
{
    import flint_tool.engine.aot.spel : Compiled, SpelError, compileSpel;
    import flint_tool.support.process : Launch, capture;
    import std.array : replace;
    import std.conv : to;
    import std.file : readText, write;
    import std.json : parseJSON;
    import std.path : buildPath;

    const project = copyFixture("spel-parity");
    scope (exit)
        remove(project);
    const cases = parseJSON(readText(buildPath(project, "cases.json"))).arrayNoRef;
    assert(cases.length > 0);
    string definitions, calls, expectedOutput;
    foreach (index, ref row; cases)
    {
        const id = row["id"].str;
        const expected = row["expected"];
        if (auto mode = "runtimeOnly" in row)
        {
            assert(mode.str.length && ("compiledOnly" in row) is null, id);
            continue;
        }
        auto context = new TestScope;
        string parameters, arguments;
        size_t bindings;
        if (auto fixture = "context" in row)
        {
            foreach (name, ref literal; (*fixture)["variables"].objectNoRef)
            {
                Compiled value;
                SpelError bindingError;
                assert(compileSpel(literal.str, context, value, bindingError), id ~ ": " ~ bindingError.message);
                if (bindings)
                {
                    parameters ~= ", ";
                    arguments ~= ", ";
                }
                const parameter = "binding_" ~ (bindings++).to!string;
                const type = value.type == "null" ? "Object" : value.type;
                parameters ~= type ~ " " ~ parameter;
                arguments ~= value.code;
                context.variables[name] = Compiled(parameter, type);
            }
        }
        Compiled result;
        SpelError error;
        const ok = compileSpel(row["expression"].str, context, result, error);
        if (auto rejection = "error" in expected)
        {
            assert(rejection.str == "syntax" && !ok && error.message.length, id);
            continue;
        }
        assert(ok, id ~ ": " ~ error.message);
        const name = "case_" ~ index.to!string;
        const value = result.type == "null" ? "cast(Object)(" ~ result.code ~ ")" : result.code;
        const boxed = result.type == "Any" ? value : "Any.of(" ~ value ~ ")";
        definitions ~= "Any " ~ name ~ "(" ~ parameters ~ ") { return " ~ boxed ~ "; }\n";
        calls ~= "reportValue(" ~ name ~ "(" ~ arguments ~ "));\n";
        expectedOutput ~= expected["type"].str ~ "\t" ~ expected["value"].str ~ "\n";
    }
    assert(calls.length > 0);
    const source = buildPath(project, "compiled.d");
    const reporting = readText(buildPath(project, "reporting.d"));
    write(source, reporting ~ definitions ~ "void main() {\n" ~ calls ~ "}\n");
    const binary = buildPath(project, "compiled");
    Launch launch;
    launch.directory = project;
    const built = capture([
        compiler(), "-preview=dip1000", "-I" ~ runtimeSource(),
        "-I" ~ buildPath(repositoryRoot(), "packages", "serde", "source"), "-i", "-of=" ~ binary,
        source
    ], launch);
    assert(built.ok, built.combined());
    const ran = capture([binary], launch);
    assert(ran.ok, ran.combined());
    expect(ran.output.replace("\r\n", "\n")).toEqual(expectedOutput);
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

    // Contract 3: the described response body's descriptor is in the mapping: the one this module builds, so no
    // descriptorOf!(T) instance.
    const web = imported!"std.file".readText(buildPath(project, ".flint", "generated", "aot",
            "flint_aot", "shop", "web.d"));
    const returnDescriptor = "mapping.returnDescriptor = descriptor_Greeting;";
    expect(imported!"std.algorithm.searching".canFind(web, returnDescriptor)).toBeTrue();
    expect(imported!"std.algorithm.searching".canFind(web, "descriptorOf!(shop.web.Greeting)")).toBeFalse();

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

@("a constant nothing names skips the extraction compile; same models regenerate nothing (early cutoff)")
unittest
{
    import std.file : append;
    import std.path : buildPath;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    auto first = generate(project);
    expect(first.ok).toBeTrue();
    // The build benchmark's incremental edit: a new module-level constant nothing refers to.
    append(buildPath(project, "src", "shop", "web.d"), "\nenum flintMeasureEdit0 = 0;\n");
    auto unreferenced = generate(project);
    expect(unreferenced.ok).toBeTrue();
    expect(unreferenced.extracted).toEqual(0);
    expect(unreferenced.written).toEqual(0);
    // The same name in two modules: each may refer to the other's, so both are extracted again, but their models
    // are unchanged and nothing is regenerated.
    append(buildPath(project, "src", "shop", "pricing.d"), "\nprivate int flintMeasureEdit0() { return 1; }\n");
    auto twice = generate(project);
    expect(twice.ok).toBeTrue();
    expect(twice.extracted > 0).toBeTrue();
    expect(twice.written).toEqual(0);
    // A constant an annotation uses is part of the key: changing it re-extracts and regenerates.
    edit(buildPath(project, "src", "shop", "web.d"), `@GetMapping("/{id}")`, `@GetMapping(greetingPath)`);
    append(buildPath(project, "src", "shop", "web.d"), "\nenum greetingPath = \"/{id}\";\n");
    auto named = generate(project);
    expect(named.extracted).toEqual(1);
    edit(buildPath(project, "src", "shop", "web.d"), `enum greetingPath = "/{id}";`,
            `enum greetingPath = "/{id}/hello";`);
    auto changed = generate(project);
    expect(changed.extracted).toEqual(1);
    expect(changed.written).toEqual(1);
}

@("top-level value and function declarations are found in the interface text")
unittest
{
    import flint_tool.engine.aot.iface : ModuleInterface, readInterface;

    ModuleInterface found;
    assert(readInterface("module m;\n@safe:\nimport a.b;\nenum limit = 3;\nprivate immutable string[] names = "
            ~ "[\"a\"];\nint twice(int x) { return x * 2; }\nT id(T)(T x) { return x; }\nalias L = int;\n"
            ~ "enum Color { red }\nstruct S { int f() { return 1; } }\nenum f = () { return 1; }();\n"
            ~ "int a = 1, b = 2;\nstatic if (true) { enum hidden = 1; }\n", found));
    string[] names;
    foreach (ref value; found.values)
    {
        names ~= value.name;
        expect(found.text[value.start .. value.end].length > 0).toBeTrue();
    }
    expect(names).toEqual(["limit", "names", "twice", "f"]);
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
    expect(web.canFind("mapping.typeAnnotations = permanent.list!(MergedAnnotation)(")).toBeTrue();
    // Start-up tables carved from one block per module (flint.engine.aot.permanent).
    expect(web.canFind("    auto permanent = Permanent(permanentBytes);\n")).toBeTrue();
    expect(web.canFind("private enum size_t permanentBytes = ")).toBeTrue();
    expect(web.canFind("mapping.paths = permanent.list!(string)(")).toBeTrue();
    expect(web.canFind(", permanent.any(() { ")).toBeTrue();
    expect(web.canFind("definition.rank = ")).toBeTrue();
    const pricing = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "shop", "pricing.d"));
    expect(pricing.canFind("return Any.of((context.argument(0).get!(long)() > cast(long) (10)));")).toBeTrue();
    expect(pricing.canFind("listener.conditionExpression = &condition_shop_pricing_Pricing_onNumber;")).toBeTrue();
    expect(pricing.canFind("listener.invokeForResult = &listen_shop_pricing_Pricing_onGreeting;")).toBeTrue();
    expect(pricing.canFind("listener.invoke = &listen_shop_pricing_Pricing_onNumber;")).toBeTrue();
    // A cache-advised method's array argument gets its descriptor, for SimpleKeyGenerator's element-wise keys.
    const owners = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "shop", "owners.d"));
    expect(owners.canFind("descriptorOf!(long[])()")).toBeTrue();
    const data = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "shop", "data.d"));
    expect(data.canFind("&construct_Owner_0, true)")).toBeTrue();
    expect(data.canFind("descriptor.enumValue = &enum_OwnerStatus;")).toBeTrue();
    expect(data.canFind("(ref Permanent permanent)\n{\n    auto descriptor = permanent.make!(Descriptor)(")).toBeTrue();
    expect(data.canFind("private enum size_t describeBytes_Owner = ")).toBeTrue();
    const ran = capture([binary], launch);
    expect(ran.ok).toBeTrue();
    // Windows' text-mode stdout ends lines with CRLF; expected.txt uses LF.
    expect(imported!"std.array".replace(ran.output, "\r\n", "\n")).toEqual(readText(buildPath(root,
            "tests", "aot", "sample", "expected.txt")));
}

@("Boot class-presence conditions control which configurations register beans")
unittest
{
    import std.path : buildPath;

    const project = copyFixture("class-conditions");
    scope (exit)
        remove(project);
    runGeneratedStartup(project, bootConditionImports(project, ["-I" ~ runtimeSource()]),
            ["-I" ~ buildPath(repositoryRoot(), "tests", "aot", "support")]);
}

@("Boot web-application conditions distinguish servlet, reactive and non-web contexts")
unittest
{
    runGeneratedContextStartup("web-conditions");
}

@("Boot property conditions select beans from the application environment at refresh")
unittest
{
    runGeneratedContextStartup("property-conditions");
}

@("Boot property conditions resolve relaxed names through the real application environment")
unittest
{
    import std.file : getcwd;
    import std.process : environment;
    import flint_tool.app : dispatch;

    const project = copyFixture("property-relaxed");
    scope (exit)
        remove(project);
    const directory = getcwd();
    const variables = environment.toAA();
    scope (exit)
    {
        assert(getcwd() == directory, "property-relaxed commands changed the working directory");
        const current = environment.toAA();
        assert(current == variables, "property-relaxed commands changed the process environment");
    }
    version (LDC)
        enum testCompiler = "ldc2";
    else
        enum testCompiler = "dmd";
    assert(dispatch(["lock", "-C", project]) == 0, "property-relaxed lock");
    assert(dispatch(["test", "-C", project, "--compiler", testCompiler, "--locked"]) == 0, "property-relaxed test");
}

private void runGeneratedContextStartup(string fixture)
{
    const project = copyFixture(fixture);
    scope (exit)
        remove(project);
    // The context is real. Use the fixture's Boot application marker so this test does not pull in
    // Boot's terminal and signal handling through the module that declares the real marker.
    string[] linkFlags;
    version (Windows)
        linkFlags = ["-L=ws2_32.lib"]; // The context's reactor dependency links Winsock.
    runGeneratedStartup(project, bootConditionImports(project, closureImports(["context"])), linkFlags);
}

private string[] bootConditionImports(string project, string[] runtimeImports)
{
    import std.file : copy, mkdirRecurse;
    import std.path : buildPath, dirName;

    const root = repositoryRoot();
    const overlay = buildPath(project, "boot-annotations");
    const condition = buildPath(overlay, "flint", "boot", "autoconfigure", "condition.d");
    const properties = buildPath(overlay, "flint", "boot", "context", "properties", "package.d");
    mkdirRecurse(dirName(condition));
    mkdirRecurse(dirName(properties));
    // Resolve both real Boot UDA modules ahead of the fixture's other annotation stubs.
    copy(buildPath(root, "boot", "core", "flint-boot-autoconfigure", "source", "flint", "boot",
            "autoconfigure", "condition.d"), condition);
    copy(buildPath(root, "boot", "core", "flint-boot", "source", "flint", "boot", "context",
            "properties", "package.d"), properties);
    // Keep the real context modules ahead of the annotation stubs when a fixture supplies them.
    return ["-I" ~ overlay] ~ runtimeImports ~ [
        "-I" ~ buildPath(root, "tests", "aot", "annotations")
    ];
}

private void runGeneratedStartup(string project, string[] imports, string[] extraCompileFlags)
{
    import std.file : dirEntries, SpanMode;
    import std.path : baseName, buildPath;
    import flint_tool.engine.aot.driver : AotRequest, runAot;
    import flint_tool.support.process : Launch, capture;

    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = imports;
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    const outcome = runAot(request);
    assert(outcome.extractionErrors.length == 0, outcome.extractionErrors);
    foreach (ref diagnostic; outcome.diagnostics)
        assert(false, diagnostic.code ~ " " ~ diagnostic.message);
    assert(outcome.active && outcome.ok);

    const source = buildPath(project, "src");
    const generated = buildPath(project, ".flint", "generated", "aot");
    string[] sources;
    foreach (directory; [source, generated])
        foreach (entry; dirEntries(directory, "*.d", SpanMode.depth))
            sources ~= entry.name;
    const binary = buildPath(project, baseName(project));
    Launch launch;
    launch.directory = project;
    const built = capture([compiler(), "-preview=dip1000",
        "-unittest"] ~ imports ~ extraCompileFlags ~ [
        "-I" ~ source, "-I" ~ generated, "-i", "-of=" ~ binary, buildPath(project, "main.d")
    ] ~ sources, launch);
    assert(built.ok, built.combined());
    const ran = capture([binary], launch);
    assert(ran.ok, ran.combined());
}

@("the array invokers' scope is DIP1000-checked: a body that keeps the argument slice does not compile")
unittest
{
    import std.algorithm.searching : find;
    import std.array : join;
    import std.file : readText, write;
    import std.path : buildPath;
    import std.string : lineSplitter, startsWith;
    import flint_tool.support.process : Launch, capture;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    expect(generate(project).ok).toBeTrue();
    const web = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "shop", "web.d"));
    // The emitted signatures, verbatim, with bodies that keep the slice or only read it.
    string[] signatures;
    foreach (line; web.lineSplitter)
        if (line.startsWith("private void handleArray_") || line.startsWith("private void exceptionArray_"))
            signatures ~= line;
    expect(signatures.length).toEqual(2);
    expect(signatures.join("\n").find("scope Any[] arguments").length > 0).toBeTrue();
    string probe(string statement)
    {
        string text = "module flint_aot_scope_probe;\nimport flint.engine.aot.any : Any;\nAny[] kept;\nAny last;\n"
            ~ "@safe:\n";
        foreach (signature; signatures)
            text ~= signature ~ "\n{\n    " ~ statement ~ "\n}\n";
        return text;
    }

    Launch launch;
    launch.directory = project;
    const file = buildPath(project, "scope_probe.d");
    string[] check = [compiler(), "-o-", "-preview=dip1000", "-I" ~ runtimeSource(), file];
    write(file, probe("last = arguments[0];"));
    const reads = capture(check, launch);
    expect(reads.combined()).toEqual("");
    expect(reads.ok).toBeTrue();
    write(file, probe("kept = arguments;"));
    const stores = capture(check, launch);
    expect(stores.ok).toBeFalse();
    // DMD 2.11x: "assigning scope variable `arguments` to global variable `kept` is not allowed in a `@safe` function".
    expect(stores.combined().find("scope variable `arguments` to global variable `kept`").length > 0).toBeTrue();
}

@("META-INF/services providers: the registry imports each listed provider's module once, as ServiceLoader finds them")
unittest
{
    import std.algorithm.searching : canFind, countUntil;
    import std.file : mkdirRecurse, readText, write;
    import std.path : buildPath;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    // A package of the closure lists a provider found on the import paths; the project lists one of its own
    // modules, again under a second service, with comments and blank lines.
    const package_ = buildPath(project, "..", "driver-package");
    mkdirRecurse(buildPath(package_, "META-INF", "services"));
    write(buildPath(package_, "META-INF", "services", "flint.java.sql.Driver"),
            "# The engine driver.\nflint.web.bind.annotation.RestController\n");
    mkdirRecurse(buildPath(project, "META-INF", "services"));
    write(buildPath(project, "META-INF", "services", "shop.Codec"),
            "shop.data.Owner # the project's own\n\n# a comment line\nshop.data.OwnerStatus\n");
    write(buildPath(project, "META-INF", "services", "shop.Format"), "shop.data.Owner\n");
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(repositoryRoot(), "tests", "aot", "annotations"), "-I" ~ runtimeSource()
    ];
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    request.packageDirectories = [package_];
    auto outcome = runAot(request);
    expect(outcome.ok).toBeTrue();
    const registry = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot_registry.d"));
    const platform = registry.countUntil("static import flint.web.bind.annotation;\n");
    const own = registry.countUntil("static import shop.data;\n");
    expect(platform >= 0 && own > platform).toBeTrue();
    expect(countOccurrences(registry, "static import shop.data;")).toEqual(1);

    // A provider whose module is nowhere in the closure: FLINT-E1117 at the listing's line.
    write(buildPath(project, "META-INF", "services", "shop.Format"), "# first\nshop.missing.Formatter\n");
    auto failed = runAot(request);
    expect(failed.ok).toBeFalse();
    expect(failed.diagnostics.length).toEqual(1);
    expect(failed.diagnostics[0].code).toEqual("FLINT-E1117");
    expect(failed.diagnostics[0].line).toEqual(2);
    expect(failed.diagnostics[0].message.canFind("shop.missing.Formatter")).toBeTrue();
    expect(failed.diagnostics[0].file.canFind("shop.Format")).toBeTrue();
}

/// How often `needle` occurs in `text`.
private size_t countOccurrences(string text, string needle)
{
    import std.algorithm.searching : count;

    return text.count(needle);
}

@("a build after a cold one extracts nothing when an @Import pulled in a module from outside src/")
unittest
{
    import std.file : mkdirRecurse, rename;
    import std.path : buildPath, dirName;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    // shared_.things leaves src/ for a library directory on the import path: imp.configs imports it, and its
    // configurations are only reachable through @Import, so the first build adds it to the sources mid-run.
    const project = copyFixture("imports");
    scope (exit)
        remove(project);
    const library = buildPath(dirName(project), "library");
    mkdirRecurse(library);
    rename(buildPath(project, "src", "shared_"), buildPath(library, "shared_"));
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(repositoryRoot(), "tests", "aot", "annotations"), "-I" ~ runtimeSource(),
        "-I" ~ library
    ];
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    auto cold = runAot(request);
    expect(cold.extractionErrors).toEqual("");
    expect(cold.ok).toBeTrue();
    expect(cold.extracted > 0).toBeTrue();
    auto next = runAot(request);
    expect(next.ok).toBeTrue();
    expect(next.extracted).toEqual(0);
    expect(next.written).toEqual(0);
}

@("the native extractor's root imports the modules only; its request lists them in order, then the held types")
unittest
{
    import std.algorithm.searching : canFind;
    import flint_tool.engine.aot.extract : renderNativeRequest, renderRoot;

    const describer = renderRoot(["shop.web", "shop.data"], ["flint.web.Missing"]);
    const native = renderRoot(["shop.web", "shop.data"], ["flint.web.Missing"], true);
    expect(describer.canFind("import flint_aot_describe : describeModule;")).toBeTrue();
    expect(describer.canFind(`static if (describeModule!(shop.web, "shop.web"))`)).toBeTrue();
    expect(native.canFind("describeModule")).toBeFalse();
    expect(native.canFind("static import shop.web;\nstatic import shop.data;\n")).toBeTrue();
    // Presence questions stay pragma(msg) lines in both roots.
    expect(native.canFind(`pragma(msg, "FLINT-AOT-PRESENT flint.web.Missing ", __traits(compiles,`)).toBeTrue();
    expect(renderNativeRequest(["shop.web", "shop.data"], ["flint.stereotype.Service"])).toEqual(
            "module shop.web\nmodule shop.data\nknown flint.stereotype.Service\n");
}

@("the extraction compile takes the version lines of the compile server's prelude, in order")
unittest
{
    import flint_tool.engine.aot.step : preludeVersions;

    const prelude = "-I/p/web/source\n-version=FlintNativeLlhttp\n-version=FlintNativeOpenssl\n-preview=dip1000\n"
        ~ "-debug\nflint.web\nflint.web.version_\n";
    expect(preludeVersions(prelude)).toEqual([
        "-version=FlintNativeLlhttp", "-version=FlintNativeOpenssl"
    ]);
    expect(preludeVersions("-I/p/source\n-preview=dip1000\nflint.web\n").length).toEqual(0);
    expect(preludeVersions("").length).toEqual(0);
}

@("only a compiler without -flint-aot-extract falls back to the describer; the fork's own errors are reported")
unittest
{
    import flint_tool.engine.aot.extract : rejectsNativeSwitch;

    expect(rejectsNativeSwitch("Error: unrecognized switch '-flint-aot-extract=/p/flint_aot_request.txt'\n"
            ~ "       run `dmd` to print the compiler manual\n")).toBeTrue();
    expect(rejectsNativeSwitch("ldc2: Unknown command line argument '-flint-aot-extract=r.txt'.  Try: 'ldc2 --help'"))
        .toBeTrue();
    const notImported = "Error: Flint AOT: module `shop.web` is not imported by the extraction root";
    expect(rejectsNativeSwitch(notImported)).toBeFalse();
    expect(rejectsNativeSwitch("Error: cannot read the Flint AOT request `/p/flint_aot_request.txt`")).toBeFalse();
    // A message that merely names the switch, after lines were extracted, is not a missing switch.
    expect(rejectsNativeSwitch("FLINT-AOT-MODULE {}\nError: unrecognized switch '-flint-aot-extract=x'")).toBeFalse();
}

version (Posix) @("a fork error fails the extraction without falling back; an unforked compiler falls back")
unittest
{
    import std.algorithm.searching : canFind;
    import std.conv : octal;
    import std.file : setAttributes, write;
    import std.path : buildPath, dirName;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    // A stand-in compiler: the real one, except that the native switch gets the given reply and exit status 1.
    string standIn(string name, string reply)
    {
        const path = buildPath(dirName(project), name);
        write(path ~ ".reply", reply ~ "\n");
        write(path, "#!/bin/sh\nfor a in \"$@\"; do case \"$a\" in -flint-aot-extract=*) cat '"
                ~ path ~ ".reply' >&2; exit 1;; esac; done\nexec '" ~ compiler() ~ "' \"$@\"\n");
        setAttributes(path, octal!755);
        return path;
    }

    AotRequest request;
    request.root = project;
    request.importPaths = [
        "-I" ~ buildPath(repositoryRoot(), "tests", "aot", "annotations"), "-I" ~ runtimeSource()
    ];
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    const notImported = "Error: Flint AOT: module `shop.web` is not imported by the extraction root";
    request.compiler = standIn("fork-dmd", notImported);
    auto failed = runAot(request);
    expect(failed.ok).toBeFalse();
    expect(failed.extractionErrors.canFind("Flint AOT: module `shop.web` is not imported")).toBeTrue();
    expect(failed.extractor).toEqual("native extractor");

    request.compiler = standIn("stock-dmd", "Error: unrecognized switch '-flint-aot-extract=x'");
    auto fallback = runAot(request);
    expect(fallback.extractionErrors).toEqual("");
    expect(fallback.ok).toBeTrue();
    expect(fallback.extracted).toEqual(6);
    expect(fallback.extractor).toEqual("describer");
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
    const excluding = `@FlintBootApplication(excludeName: ["flintsample.autoconfig.ExcludedAutoConfiguration"])`;
    edit(buildPath(project, "src", "shop", "app.d"), "@FlintBootApplication\nfinal class", excluding ~ "\nfinal class");
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
            ~ `&& !c.isAutoConfigurationExcluded("flintsample.autoconfig.WidgetAutoConfiguration");`)).toBeTrue();
    // A @Bean method is conditional on its configuration having registered, not on a copy of its terms.
    expect(generated.canFind(`c.hasBeanNamed("flintsample.autoconfig.WidgetAutoConfiguration") `
            ~ `&& !c.hasBeanOfType("flintsample.autoconfig.Widget");`)).toBeTrue();
}

@("@Import: Spring's definition order, importer-registered conditions, scanned imports, interfaces")
unittest
{
    import std.algorithm.searching : canFind, count;
    import std.file : readText;
    import std.path : buildPath;

    const project = copyFixture("imports");
    scope (exit)
        remove(project);
    auto outcome = generate(project);
    expect(outcome.extractionErrors).toEqual("");
    foreach (ref item; outcome.diagnostics)
        expect(item.code ~ " " ~ item.message).toEqual("");
    expect(outcome.ok).toBeTrue();
    const aot = buildPath(project, ".flint", "generated", "aot", "flint_aot");
    const configs = readText(buildPath(aot, "imp", "configs.d"));
    const things = readText(buildPath(aot, "shared_", "things.d"));
    // Ranks: every scanned class first; then each configuration's imports, placed at the first importer, before
    // its own @Bean methods (gh-24643: the importer's `thing` overrides the imported one).
    expect(rankOf(configs, "gammaConfig") < rankOf(things, "shared_.things.SharedConfig")).toBeTrue();
    expect(rankOf(things, "thing") < rankOf(configs, "thing")).toBeTrue();
    expect(rankOf(things, "shared_.things.SharedConfig") < rankOf(configs, "scannedThing")).toBeTrue();
    // The shared configuration registers when either importer did.
    expect(things.canFind(`return (c.hasBeanNamed("alphaConfig") || c.hasBeanNamed("betaConfig"));`)).toBeTrue();
    expect(things.canFind(`return c.hasBeanNamed("shared_.things.SharedConfig");`)).toBeTrue();
    // A scanned class that is also imported is defined once, as scanned.
    expect(configs.count(`definition.name = "scannedConfig";`)).toEqual(1);
    expect(things.canFind(`"imp.configs.ScannedConfig"`)).toBeFalse();
    // @Import on an implemented interface.
    expect(things.canFind(`definition.name = "shared_.things.MarkedConfig";`)).toBeTrue();
    expect(things.canFind(`return (c.hasBeanNamed("gammaConfig"));`)).toBeTrue();
}

/// The rank of the definition named `name` in `text`.
private int rankOf(string text, string name)
{
    import std.conv : to;
    import std.string : indexOf;

    const at = text.indexOf(`definition.name = "` ~ name ~ `";`);
    assert(at >= 0, "no definition named " ~ name);
    const rank = text.indexOf("definition.rank = ", at) + "definition.rank = ".length;
    return text[rank .. rank + text[rank .. $].indexOf(';')].to!int;
}

@("class-level mappings come from interfaces and handler methods from base classes (TYPE_HIERARCHY)")
unittest
{
    import std.algorithm.searching : canFind;
    import std.file : readText;
    import std.path : buildPath;

    const project = copyFixture("hierarchy");
    scope (exit)
        remove(project);
    auto outcome = generate(project);
    expect(outcome.extractionErrors).toEqual("");
    foreach (ref item; outcome.diagnostics)
        expect(item.code ~ " " ~ item.message).toEqual("");
    expect(outcome.ok).toBeTrue();
    const web = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "hier", "web.d"));
    expect(web.canFind(`mapping.paths = permanent.list!(string)("/api/ping");`)).toBeTrue();
    expect(web.canFind(`mapping.paths = permanent.list!(string)("/api/version");`)).toBeTrue();
    // RequestMappingInfo.combine: the class's methods, params and headers join the method's, each once.
    expect(web.canFind(`mapping.paths = permanent.list!(string)("/v2/status");`)).toBeTrue();
    expect(web.canFind(`mapping.methods = permanent.list!(string)("GET", "HEAD");`)).toBeTrue();
    expect(web.canFind(`mapping.params = permanent.list!(string)("version=2", "full");`)).toBeTrue();
    expect(web.canFind(`mapping.headers = permanent.list!(string)("X-Api=1");`)).toBeTrue();
    // Contract 3: the controller's descriptor carries PingApi's @RequestMapping as aggregate 1.
    expect(web.canFind(`MergedAnnotation("flint.web.bind.annotation.RequestMapping", permanent.any(`)).toBeTrue();
    expect(web.canFind(`), 0, 1)`)).toBeTrue();
    // The first aggregate with a match wins: ReportService's meta-annotated @Transactional, not BaseService's.
    const service = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "hier", "service.d"));
    expect(service.canFind(`a.value = "readOnlyManager";`)).toBeTrue();
    // BaseService's own @Transactional is only in the descriptor's table, as aggregate 1.
    foreach (line; imported!"std.string".splitLines(service))
    {
        if (line.canFind(`"baseManager"`))
            expect(line.canFind("), 0, 1)")).toBeTrue(); // the list's last element closes the call
    }
}

@("a platform module exporting flintAotDescriptors is called instead of described (template diet)")
unittest
{
    import std.algorithm.searching : canFind;
    import std.file : readText;
    import std.path : buildPath;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    const root = repositoryRoot();
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(root, "tests", "aot", "annotations"), "-I" ~ runtimeSource(),
        "-I" ~ buildPath(root, "tests", "aot", "exporter", "source")
    ];
    request.flags = ["-preview=dip1000"];
    request.packageDirectories = [buildPath(root, "tests", "aot", "exporter")];
    request.environmentKey = "test";
    auto outcome = runAot(request);
    expect(outcome.extractionErrors).toEqual("");
    expect(outcome.ok).toBeTrue();
    const generated = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot",
            "flintexporter", "config.d"));
    expect(generated.canFind("foreach (descriptor; flintexporter.config.flintAotDescriptors())")).toBeTrue();
    expect(generated.canFind("describe_ExporterProperties")).toBeFalse();
    expect(generated.canFind("descriptorOf!(string[])")).toBeFalse();
    // A platform module's generated text names its sources from their source/ root, not the checkout, so flint
    // build can cache the AOT library across projects and checkouts.
    expect(generated.canFind(root)).toBeFalse();
    expect(generated.canFind(`"flintexporter/config.d:`)).toBeTrue();
    // The properties bean is still generated: beans and conditions stay with the application.
    expect(generated.canFind(`"exporter-flintexporter.config.ExporterProperties"`)).toBeTrue();
}

@("a platform module's generated code may not import a project module (FLINT-E1116)")
unittest
{
    import std.file : mkdirRecurse, write;
    import std.path : buildPath, dirName;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    // An auto-configuration whose @Value names the sample's `pricing` bean: its factory would cast to
    // shop.pricing.Pricing, a project class, so the AOT library could not be compiled apart from the project.
    const package_ = buildPath(dirName(project), "leaky");
    mkdirRecurse(buildPath(package_, "META-INF", "flint"));
    mkdirRecurse(buildPath(package_, "source", "leaky"));
    write(buildPath(package_, "META-INF", "flint",
            "flint.boot.autoconfigure.AutoConfiguration.imports"), "leaky.config.LeakyAutoConfiguration\n");
    write(buildPath(package_, "source", "leaky", "config.d"), "module leaky.config;\n"
            ~ "import flint.beans.factory.annotation : Value;\nimport flint.boot.autoconfigure : AutoConfiguration;\n"
            ~ "import flint.context.annotation : Bean;\n@safe:\nclass Limit { long value; this(long value) "
            ~ "{ this.value = value; } }\n@AutoConfiguration class LeakyAutoConfiguration\n{\n"
            ~ "    @Bean Limit limit(@Value(\"#{@pricing.doubled}\") long doubled)\n"
            ~ "    {\n        return new Limit(doubled);\n    }\n}\n");
    const root = repositoryRoot();
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(root, "tests", "aot", "annotations"), "-I" ~ buildPath(package_, "source")
    ];
    request.flags = ["-preview=dip1000"];
    request.packageDirectories = [package_];
    request.environmentKey = "test";
    auto outcome = runAot(request);
    expect(outcome.extractionErrors).toEqual("");
    expect(outcome.ok).toBeFalse();
    string[] codes;
    foreach (ref item; outcome.diagnostics)
        codes ~= item.code;
    expect(codes).toEqual(["FLINT-E1116"]);
}

@("The shared cache serves platform modules' models and presence answers to a cold build of another copy")
unittest
{
    import std.conv : to;
    import std.file : exists, readText, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import flint_tool.engine.aot.driver : AotOutcome, AotRequest, runAot;

    const shared_ = buildPath(tempDir, "flint-aot-shared-" ~ thisProcessID.to!string);
    if (exists(shared_))
        rmdirRecurse(shared_);
    scope (exit)
        if (exists(shared_))
            rmdirRecurse(shared_);
    const root = repositoryRoot();
    string[2] outputs;
    AotOutcome[2] outcomes;
    foreach (run; 0 .. 2)
    {
        const project = copyFixture("sample");
        scope (exit)
            remove(project);
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
        request.sharedCache = shared_;
        outcomes[run] = runAot(request);
        expect(outcomes[run].extractionErrors).toEqual("");
        expect(outcomes[run].ok).toBeTrue();
        outputs[run] = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot",
                "flintsample", "autoconfig.d"));
    }
    // The auto-configuration modules are outside src/: extracted once, then reused; the user modules are extracted.
    expect(outcomes[0].reused).toEqual(0);
    expect(outcomes[1].reused > 0).toBeTrue();
    expect(outcomes[1].extracted + outcomes[1].reused).toEqual(outcomes[0].extracted);
    expect(outputs[1]).toEqual(outputs[0]);
}

@("the shared cache keeps platform modules' interfaces per environment; a damaged entry is searched again")
unittest
{
    import std.algorithm.searching : canFind;
    import std.conv : to;
    import std.file : SpanMode, dirEntries, exists, readText, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    const shared_ = buildPath(tempDir, "flint-aot-interfaces-" ~ thisProcessID.to!string);
    if (exists(shared_))
        rmdirRecurse(shared_);
    scope (exit)
        if (exists(shared_))
            rmdirRecurse(shared_);
    const root = repositoryRoot();
    string generateCopy()
    {
        const project = copyFixture("sample");
        scope (exit)
            remove(project);
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
        request.sharedCache = shared_;
        auto outcome = runAot(request);
        expect(outcome.extractionErrors).toEqual("");
        expect(outcome.ok).toBeTrue();
        return readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "flintsample", "autoconfig.d"));
    }

    const first = generateCopy();
    string[] entries;
    foreach (entry; dirEntries(buildPath(shared_, "interfaces"), "*.json", SpanMode.shallow))
        entries ~= entry.name;
    expect(entries.length).toEqual(1);
    const recorded = readText(entries[0]);
    expect(recorded.canFind(`"environment":"test"`)).toBeTrue();
    expect(recorded.canFind(`"flintsample.autoconfig"`)).toBeTrue();
    // A fresh copy reads the entry instead of searching and lexing the platform sources: the same output.
    expect(generateCopy()).toEqual(first);
    // A damaged entry is ignored and rewritten.
    write(entries[0], "{\"environment\": ");
    expect(generateCopy()).toEqual(first);
    expect(readText(entries[0]).canFind(`"flintsample.autoconfig"`)).toBeTrue();
}

@("an edited platform module is read again: its new interface reaches the model and the output, cached or not")
unittest
{
    import std.algorithm.searching : canFind;
    import std.array : replace;
    import std.conv : to;
    import std.file : exists, readText, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    // A workspace package has no content hash, so the environment key stays the same across the edit.
    const shared_ = buildPath(tempDir, "flint-aot-platform-edit-" ~ thisProcessID.to!string);
    if (exists(shared_))
        rmdirRecurse(shared_);
    scope (exit)
        if (exists(shared_))
            rmdirRecurse(shared_);
    const platform = copyFixture("autoconfig");
    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    string generate(string root)
    {
        AotRequest request;
        request.root = root;
        request.compiler = compiler();
        request.importPaths = [
            "-I" ~ buildPath(repositoryRoot(), "tests", "aot", "annotations"),
            "-I" ~ buildPath(platform, "source")
        ];
        request.flags = ["-preview=dip1000"];
        request.packageDirectories = [platform];
        request.environmentKey = "test";
        request.sharedCache = shared_;
        auto outcome = runAot(request);
        expect(outcome.extractionErrors).toEqual("");
        expect(outcome.ok).toBeTrue();
        return readText(buildPath(root, ".flint", "generated", "aot", "flint_aot", "flintsample", "autoconfig.d"));
    }

    expect(generate(project).canFind(".widget()")).toBeTrue();
    const source = buildPath(platform, "source", "flintsample", "autoconfig.d");
    write(source, readText(source).replace("    Widget widget()", "    Widget primaryWidget()"));
    // The same project, its state remembering the old interface.
    const edited = generate(project);
    expect(edited.canFind(".primaryWidget()")).toBeTrue();
    expect(edited.canFind(".widget()")).toBeFalse();
    // A fresh project, seeded from the shared interface entry.
    const fresh = copyFixture("sample");
    expect(generate(fresh)).toEqual(edited);
}

@("a cached cold build (a clean .flint, the shared cache kept) extracts nothing and restores the output")
unittest
{
    import std.conv : to;
    import std.file : exists, readText, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import flint_tool.engine.aot.driver : AotOutcome, AotRequest, projectCacheName, runAot;

    const shared_ = buildPath(tempDir, "flint-aot-cold-" ~ thisProcessID.to!string);
    if (exists(shared_))
        rmdirRecurse(shared_);
    scope (exit)
        if (exists(shared_))
            rmdirRecurse(shared_);
    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    const root = repositoryRoot();
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(root, "tests", "aot", "annotations"), "-I" ~ runtimeSource()
    ];
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    request.sharedCache = shared_;
    const generated = buildPath(project, ".flint", "generated", "aot", "flint_aot", "shop", "web.d");
    AotOutcome[2] outcomes;
    string[2] texts;
    foreach (run; 0 .. 2)
    {
        if (exists(buildPath(project, ".flint")))
            rmdirRecurse(buildPath(project, ".flint"));
        outcomes[run] = runAot(request);
        expect(outcomes[run].extractionErrors).toEqual("");
        expect(outcomes[run].ok).toBeTrue();
        texts[run] = readText(generated);
    }
    expect(outcomes[0].extracted > 0).toBeTrue();
    // The project's models come from the shared cache too (keyed with the project root), and the generated
    // output is restored, with what the step reports about it.
    expect(outcomes[1].extracted).toEqual(0);
    expect(outcomes[1].reused).toEqual(outcomes[0].extracted);
    expect(outcomes[1].application).toEqual(outcomes[0].application);
    expect(outcomes[1].generated).toEqual(outcomes[0].generated);
    expect(outcomes[1].removed).toEqual(outcomes[0].removed);
    expect(texts[1]).toEqual(texts[0]);
    expect(exists(buildPath(project, ".flint", "generated", "aot", "flint_aot_registry.d"))).toBeTrue();
    // Project-keyed entries live under projects/<root hash>/, apart from the platform's: without them (a
    // platform-only copy of the cache, as the cold build benchmark starts from) the project is extracted again.
    const projectPart = buildPath(shared_, "projects", projectCacheName(project));
    expect(exists(buildPath(projectPart, "models"))).toBeTrue();
    expect(exists(buildPath(projectPart, "outputs"))).toBeTrue();
    rmdirRecurse(buildPath(shared_, "projects"));
    rmdirRecurse(buildPath(project, ".flint"));
    auto platformOnly = runAot(request);
    expect(platformOnly.ok).toBeTrue();
    expect(platformOnly.extracted).toEqual(outcomes[0].extracted);
    expect(readText(generated)).toEqual(texts[0]);
}

@("shared model entries are raw, versioned and checked: a truncated or corrupt one is never used")
unittest
{
    import flint_tool.engine.aot.driver : parseSharedModel, renderSharedModel;

    const document = `{"schema":"flint.aot.model/1","module":"m","types":[]}`;
    const entry = renderSharedModel(document, "abc123");
    string read, set, hash;
    expect(parseSharedModel(entry, read, set, hash)).toBeTrue();
    expect(read).toEqual(document);
    expect(set).toEqual("abc123");
    expect(hash.length).toEqual(64);
    // Truncated, extended, a corrupted body, a foreign format line, or a JSON-era entry: each is a miss.
    expect(parseSharedModel(entry[0 .. $ - 1], read, set, hash)).toBeFalse();
    expect(parseSharedModel(entry ~ " ", read, set, hash)).toBeFalse();
    expect(parseSharedModel(entry[0 .. $ - 2] ~ "]]", read, set, hash)).toBeFalse();
    const foreign = "flint.aot.shared-model/1" ~ entry["flint.aot.shared-model/2".length .. $];
    expect(parseSharedModel(foreign, read, set, hash)).toBeFalse();
    expect(parseSharedModel(`{"model":"{}","annotationSet":"abc"}`, read, set, hash)).toBeFalse();
    expect(parseSharedModel("", read, set, hash)).toBeFalse();
}

@("a corrupt shared model entry is extracted again, with the same output")
unittest
{
    import std.conv : to;
    import std.file : SpanMode, dirEntries, exists, readText, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import flint_tool.engine.aot.driver : AotOutcome, AotRequest, runAot;

    const shared_ = buildPath(tempDir, "flint-aot-corrupt-" ~ thisProcessID.to!string);
    if (exists(shared_))
        rmdirRecurse(shared_);
    scope (exit)
        if (exists(shared_))
            rmdirRecurse(shared_);
    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(repositoryRoot(), "tests", "aot", "annotations"), "-I" ~ runtimeSource()
    ];
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    request.sharedCache = shared_;
    auto first = runAot(request);
    expect(first.ok).toBeTrue();
    const expected = generatedFiles(project);
    // Truncate one project model entry and drop the stored output: the next cold build must extract that module.
    bool truncated;
    foreach (entry; dirEntries(buildPath(shared_, "projects"), "*.r2", SpanMode.depth))
    {
        if (!truncated)
        {
            const text = readText(entry.name);
            write(entry.name, text[0 .. $ / 2]);
            truncated = true;
        }
    }
    expect(truncated).toBeTrue();
    foreach (entry; dirEntries(buildPath(shared_, "projects"), "*.json", SpanMode.depth))
    {
        if (imported!"std.algorithm.searching".canFind(entry.name, "outputs"))
            imported!"std.file".remove(entry.name);
    }
    rmdirRecurse(buildPath(project, ".flint"));
    auto second = runAot(request);
    expect(second.ok).toBeTrue();
    expect(second.extracted).toEqual(1);
    expect(second.reused).toEqual(first.extracted - 1);
    const actual = generatedFiles(project);
    expect(actual.length).toEqual(expected.length);
    foreach (path, text; expected)
        expect(actual.get(path, null)).toEqual(text);
}

/// Every generated file of a project, by path relative to the generated directory.
private string[string] generatedFiles(string project)
{
    import std.file : SpanMode, dirEntries, isFile, readText;
    import std.path : buildPath, relativePath;

    const directory = buildPath(project, ".flint", "generated", "aot");
    string[string] files;
    foreach (entry; dirEntries(directory, "*.d", SpanMode.depth))
    {
        if (isFile(entry.name))
            files[relativePath(entry.name, directory)] = readText(entry.name);
    }
    return files;
}

@("a fresh platform-only cache: the project's extraction skips the cached platform annotation types, same output")
unittest
{
    import std.conv : to;
    import std.file : exists, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import flint_tool.engine.aot.driver : AotRequest, runAot;

    const shared_ = buildPath(tempDir, "flint-aot-known-" ~ thisProcessID.to!string);
    if (exists(shared_))
        rmdirRecurse(shared_);
    scope (exit)
        if (exists(shared_))
            rmdirRecurse(shared_);
    const root = repositoryRoot();
    AotRequest request;
    request.compiler = compiler();
    request.importPaths = [
        "-I" ~ buildPath(root, "tests", "aot", "annotations"),
        "-I" ~ buildPath(root, "tests", "aot", "autoconfig", "source"), "-I" ~ runtimeSource()
    ];
    request.flags = ["-preview=dip1000"];
    request.packageDirectories = [buildPath(root, "tests", "aot", "autoconfig")];
    request.environmentKey = "test";
    request.sharedCache = shared_;
    string[string][2] outputs;
    foreach (run; 0 .. 2)
    {
        const project = copyFixture("sample");
        scope (exit)
            remove(project);
        // The second project starts from the platform part only, as the cold build benchmark does: the platform
        // model and its annotation types are reused, the project's modules are extracted with those types known.
        if (run == 1)
            rmdirRecurse(buildPath(shared_, "projects"));
        request.root = project;
        auto outcome = runAot(request);
        expect(outcome.extractionErrors).toEqual("");
        expect(outcome.ok).toBeTrue();
        if (run == 1)
        {
            expect(outcome.reused > 0).toBeTrue();
            expect(outcome.extracted > 0).toBeTrue();
        }
        outputs[run] = generatedFiles(project);
    }
    expect(outputs[1].length).toEqual(outputs[0].length);
    foreach (path, text; outputs[0])
        expect(outputs[1].get(path, null)).toEqual(text);
}

@("an incremental extraction with known annotation types matches a full one; project annotation types are redescribed")
unittest
{
    import std.path : buildPath;

    const incremental = copyFixture("hierarchy");
    scope (exit)
        remove(incremental);
    expect(generate(incremental).ok).toBeTrue();
    // An interface edit re-extracts one module with the cached annotation types known; then an edit to the
    // project's own composed annotation must be described again, not taken from the cache.
    edit(buildPath(incremental, "src", "hier", "web.d"), `@GetMapping("/ping")`, `@GetMapping("/pong")`);
    expect(generate(incremental).ok).toBeTrue();
    edit(buildPath(incremental, "src", "hier", "service.d"), `"readOnlyManager"`, `"reportManager"`);
    expect(generate(incremental).ok).toBeTrue();
    const full = copyFixture("hierarchy");
    scope (exit)
        remove(full);
    edit(buildPath(full, "src", "hier", "web.d"), `@GetMapping("/ping")`, `@GetMapping("/pong")`);
    edit(buildPath(full, "src", "hier", "service.d"), `"readOnlyManager"`, `"reportManager"`);
    expect(generate(full).ok).toBeTrue();
    const expected = generatedFiles(full);
    const actual = generatedFiles(incremental);
    expect(actual.length).toEqual(expected.length);
    foreach (path, text; expected)
        expect(actual.get(path, null)).toEqual(text);
    expect(imported!"std.algorithm.searching".canFind(actual[buildPath("flint_aot", "hier",
            "service.d")], `"reportManager"`)).toBeTrue();
}

/// Source directories of the DUB closure of `roots` (repository-relative package directories), following each
/// dub.sdl's `dependency` lines, so the list follows packages when they move. `flint:x` names resolve to
/// framework/x or packages/x, whichever has a dub.sdl. framework/java comes first: while framework/p1-interim exists it shadows
/// flint.java.lang for packages that do not depend on it.
/// The directory of each root DUB sub-package, by its `name`.
private string[string] subPackageDirectories(string root)
{
    import std.file : exists, readText;
    import std.path : buildPath;
    import std.regex : matchFirst, matchAll, regex;

    string[string] directories;
    foreach (match; matchAll(readText(buildPath(root, "dub.sdl")), regex(`(?m)^subPackage\s+"([^"]+)"`)))
    {
        const recipe = buildPath(root, match[1], "dub.sdl");
        if (!exists(recipe))
            continue;
        const name = matchFirst(readText(recipe), regex(`(?m)^name\s+"([^"]+)"`));
        if (!name.empty)
            directories[name[1]] = buildPath(root, match[1]);
    }
    return directories;
}

private string[] closureImports(scope const string[] roots)
{
    import std.algorithm.searching : canFind, startsWith;
    import std.file : exists, readText;
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
                // Only a directory with a recipe is a package: a checkout can keep a stale directory where a package
                // used to live (packages/engine-aot before framework/engine-aot).
                bool found;
                foreach (base; ["framework", "packages"])
                {
                    const candidate = buildPath(root, base, name[6 .. $]);
                    if (exists(buildPath(candidate, "dub.sdl")))
                    {
                        visit(candidate);
                        found = true;
                        break;
                    }
                }
                // Boot's packages are root sub-packages whose directories do not spell their names
                // (flint:boot-core is boot/core/flint-boot).
                if (!found)
                {
                    if (auto subPackage = name[6 .. $] in subPackageDirectories(root))
                        visit(*subPackage);
                }
            }
            else if (match[2].length)
                visit(buildPath(directory, match[2]));
        }
    }

    // A root is a directory, or a root sub-package's name, so packages that move (security/ left framework/)
    // need no change here.
    foreach (item; roots)
    {
        if (auto directory = item in subPackageDirectories(root))
            visit(*directory);
        else
            visit(buildPath(root, item));
    }
    string[] flags = ["-I" ~ buildPath(root, "framework", "java", "source")];
    foreach (directory; seen)
    {
        if (exists(buildPath(directory, "source")))
            flags ~= "-I" ~ buildPath(directory, "source");
    }
    return flags;
}

@("gs-rest-service against the real web and Boot annotations: the table is Spring's and the code compiles")
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
    auto imports = closureImports([
        "framework/web", "framework/webmvc", "boot/core/flint-boot-autoconfigure"
    ]);
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
    expect(controller.canFind(`mapping.paths = permanent.list!(string)("/greeting");`)).toBeTrue();
    expect(controller.canFind(`mapping.methods = permanent.list!(string)("GET");`)).toBeTrue();
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

@("a described java.util.Date registers Jackson's JavaUtilDateModule through a generated builder customizer")
unittest
{
    import std.file : dirEntries, readText, SpanMode;
    import std.path : buildPath;
    import flint_tool.engine.aot.driver : AotRequest, runAot;
    import flint_tool.support.process : Launch, capture;

    const project = copyFixture("date");
    scope (exit)
        remove(project);
    auto imports = closureImports([
        "framework/web", "framework/webmvc", "boot/core/flint-boot-autoconfigure",
        "boot/module/flint-boot-jackson"
    ]);
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = imports;
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    auto outcome = runAot(request);
    expect(outcome.extractionErrors).toEqual("");
    foreach (ref item; outcome.diagnostics)
        expect(item.code ~ " " ~ item.message).toEqual("");
    expect(outcome.ok).toBeTrue();
    // In the application's own generated module, not the platform's (whose generated code stays project-free).
    const application = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot",
            "com", "example", "dated", "application.d"));
    expect(application.canFind(`definition.name = "flintAotJavaUtilDateModuleCustomizer";`)).toBeTrue();
    enum customizer = `"flint.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer"`;
    expect(application.canFind("definition.types = permanent.list!(string)(" ~ customizer ~ ");")).toBeTrue();
    const added = "builder.addModule(new flint.jackson.databind.module_.JavaUtilDateModule());";
    expect(application.canFind(added)).toBeTrue();
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

@("no java.util.Date described: no customizer")
unittest
{
    import std.file : readText;
    import std.path : buildPath;

    const project = copyFixture("sample");
    scope (exit)
        remove(project);
    expect(generate(project).ok).toBeTrue();
    const app = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot", "shop", "app.d"));
    expect(app.canFind("flintAotJavaUtilDateModuleCustomizer")).toBeFalse();
}

@("petclinic-rest's shapes: interface mappings, @PreAuthorize SpEL, inherited properties, real annotations")
unittest
{
    import std.file : dirEntries, readText, SpanMode;
    import std.path : buildPath;
    import flint_tool.engine.aot.driver : AotRequest, runAot;
    import flint_tool.support.process : Launch, capture;

    const project = copyFixture("petclinic-rest");
    scope (exit)
        remove(project);
    auto imports = closureImports([
        "framework/web", "framework/webmvc", "framework/tx", "framework/jakarta-validation",
        "security-config", "boot/core/flint-boot-autoconfigure"
    ]);
    AotRequest request;
    request.root = project;
    request.compiler = compiler();
    request.importPaths = imports;
    request.flags = ["-preview=dip1000"];
    request.environmentKey = "test";
    auto outcome = runAot(request);
    expect(outcome.extractionErrors).toEqual("");
    foreach (ref item; outcome.diagnostics)
        expect(item.code ~ " " ~ item.message).toEqual("");
    expect(outcome.ok).toBeTrue();
    const generated = buildPath(project, ".flint", "generated", "aot", "flint_aot", "org",
            "springframework", "samples", "petclinic");
    const controller = readText(buildPath(generated, "rest", "controller", "ownerrestcontroller.d"));
    // The mapping is found on the implemented OwnersApi method, combined with the class's /api.
    expect(controller.canFind(`mapping.paths = permanent.list!(string)("/api/owners/{ownerId}");`)).toBeTrue();
    expect(controller.canFind(`mapping.produces = permanent.list!(string)("application/json");`)).toBeTrue();
    expect(controller.canFind(`a.kind = ArgumentKind.pathVariable; a.name = "ownerId"; a.type = "int";`)).toBeTrue();
    expect(controller.canFind(`a.kind = ArgumentKind.requestBody; a.name = "ownerFieldsDto"; `
            ~ `a.type = "org.springframework.samples.petclinic.rest.dto.ownerdto.OwnerFieldsDto"; a.required = true; `
            ~ `a.validate = true;`)).toBeTrue();
    expect(controller.canFind(`MergedAnnotation("flint.web.bind.annotation.CrossOrigin"`)).toBeTrue();
    // Contract 3: the request body's type is described in its own module (the DTO's), so the spec carries no
    // descriptor and dispatch looks it up by name; no descriptorOf!(T) instance in the controller's module.
    expect(controller.canFind(`descriptorOf!(org.springframework.samples.petclinic.rest.dto`)).toBeFalse();
    // @PreAuthorize("hasRole(@roles.OWNER_ADMIN)") is compiled: a bean's field passed to a root function.
    expect(controller.canFind(`return context.rootFunction("hasRole", [Any.of(((cast(org.springframework.samples.`
            ~ `petclinic.security.roles.Roles) context.bean("roles"))).OWNER_ADMIN)]);`)).toBeTrue();
    expect(controller.canFind(`ExpressionSpec("flint.security.access.prepost.PreAuthorize", "value", `
            ~ `"hasRole(@roles.OWNER_ADMIN)", &spel_OwnerRestController_`)).toBeTrue();
    expect(controller.canFind("final class OwnerRestController__FlintProxy")).toBeTrue();
    // Method validation: @Validated on OwnersApi advises the controller, and @Min on the interface's parameter is in
    // the advised method's parameter descriptor.
    expect(controller.canFind(`MergedAnnotation("flint.validation.annotation.Validated"`)).toBeTrue();
    expect(controller.canFind(`ParameterDescriptor("size", "int", permanent.list!(MergedAnnotation)(`)).toBeTrue();
    expect(controller.canFind(`MergedAnnotation("flint.jakarta.validation.constraints.Min", permanent.any(() { `
            ~ `flint.jakarta.validation.constraints.Min a;`)).toBeTrue();
    // Contract 3: in the parameter's table, @Min comes from the implemented OwnersApi method, aggregate 1 (the
    // handler's ArgumentSpec keeps the merged view).
    bool aggregated;
    foreach (line; imported!"std.string".splitLines(controller))
        aggregated = aggregated || (line.canFind(`MergedAnnotation("flint.jakarta.validation.constraints.Min"`)
                && line.canFind("), 0, 1)"));
    expect(aggregated).toBeTrue();
    // Container-typed arguments: named by the runtime's canonical spelling as a literal (no typeNameOf!(T) instance
    // in the generated module), with their descriptors registered.
    expect(controller.canFind(`a.type = "flint.java.util.Optional!string"; a.required = false;`)).toBeTrue();
    expect(controller.canFind(`typeNameOf!(`)).toBeFalse();
    expect(controller.canFind(`descriptorOf!(flint.java.util.Optional!(string))()`)).toBeTrue();
    // A flint.java.util list goes through the erased builder (no descriptorOf instance), with a create function
    // because the binder builds the argument.
    expect(controller.canFind(`rawListDescriptor("flint.java.util.List!int", "int", &newContainer_`)).toBeTrue();
    expect(controller.canFind(`descriptorOf!(flint.java.util.List!(int))`)).toBeFalse();
    // A root property's member is a dotted root path the runtime resolves.
    expect(controller.canFind(`(context.rootProperty("authentication.name")).get!(string)() == "admin"`)).toBeTrue();
    // @EnableMethodSecurity's @Import: the imported configuration and its advisor bean register only where
    // BasicAuthenticationConfig's condition holds.
    const imported = readText(buildPath(project, ".flint", "generated", "aot", "flint_aot",
            "flint", "security", "config", "annotation", "method", "configuration.d"));
    expect(imported.canFind(`definition.name = "flint.security.config.annotation.method.configuration.`
            ~ `PrePostMethodSecurityConfiguration";`)).toBeTrue();
    expect(imported.canFind(`definition.name = "preAuthorizeAuthorizationMethodInterceptor";`)).toBeTrue();
    expect(imported.canFind(`return (c.hasBeanNamed("basicAuthenticationConfig"));`)).toBeTrue();
    expect(imported.canFind(`return c.hasBeanNamed("flint.security.config.annotation.method.configuration.`
            ~ `PrePostMethodSecurityConfiguration")`)).toBeTrue();
    // A FactoryBean's object types come first, so getBean(Vets) finds the factory's object.
    const vets = readText(buildPath(generated, "model", "vets.d"));
    enum vetsType = `"org.springframework.samples.petclinic.model.vets.Vets"`;
    expect(vets.canFind("definition.objectTypes = permanent.list!(string)(" ~ vetsType ~ ");")).toBeTrue();
    // A DTO's container-typed properties have their descriptors registered (data-access: List!(VisitDto),
    // Nullable!int in petclinic-rest's DTOs).
    const dto = readText(buildPath(generated, "rest", "dto", "ownerdto.d"));
    // Named as typeNameOf names them: the instance with its arguments short (DMD and LDC agree), the element fully
    // qualified, as its own descriptor is registered.
    expect(dto.canFind(`rawListDescriptor("flint.java.util.List!(PetDto)", `
            ~ `"org.springframework.samples.petclinic.rest.dto.ownerdto.PetDto", &newContainer_`)).toBeTrue();
    expect(dto.canFind(`return Any.of(cast(flint.java.util.List!(org.springframework.samples.petclinic.rest.dto.`
            ~ `ownerdto.PetDto)) new flint.java.util.ArrayList!(org.springframework.samples.petclinic.rest.dto.`
            ~ `ownerdto.PetDto)());`)).toBeTrue();
    expect(dto.canFind(`descriptorOf!(std.typecons.Nullable!(int))()`)).toBeTrue();
    // Properties inherited through getters: Owner : Person : BaseEntity.
    const model = readText(buildPath(generated, "model", "baseentity.d"));
    foreach (property; [`"telephone"`, `"firstName"`, `"id"`])
        expect(model.canFind(`PropertyDescriptor(` ~ property)).toBeTrue();
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

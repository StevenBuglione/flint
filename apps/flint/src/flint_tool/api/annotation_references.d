/// Complete annotation fields that reference mapped Java enum and annotation types.
module flint_tool.api.annotation_references;

import flint_tool.api.coverage : Classifier, Status, validSymbol;
import flint_tool.api.java : Member, MemberKind, TypeKind;
import flint_tool.api.manifest : ApiType, Manifest, memberId;
import std.json : JSONType, JSONValue;

@safe:

private alias AnnotationScope = bool delegate(const ref ApiType, out JSONValue, out string) @safe;

/// Complete the helper's draft body. An empty result reports a reference that cannot be ported.
string resolveReferenceBody(const ref Manifest manifest, const ref ApiType annotation, const ref Classifier classifier,
        string module_, const ref JSONValue candidate, out string error, scope AnnotationScope loadScope = null)
{
    const markers = "metaMarkers" in candidate;
    const draft = candidate[markers is null ? "referenceBody" : "metaBody"].str;
    const references = JavaReferences(manifest.types, candidate["package"].str,
            candidate["referenceImports"].arrayNoRef);
    string rendered;
    if (markers !is null)
    {
        rendered = resolveMarkers(references, annotation, classifier, module_, markers.arrayNoRef, error);
        if (error.length)
            return null;
    }
    size_t cursor;
    foreach (ref field; candidate["members"].arrayNoRef)
    {
        if ("reference" !in field)
            continue;
        const reference = field["reference"];
        const offset = reference["offset"].integer;
        if (offset < 0 || offset < cursor || offset >= draft.length)
        {
            error = "invalid helper offset for referenced annotation field";
            return null;
        }
        const attribute = memberNamed(annotation.decl.members, field["name"].str, MemberKind.attribute);
        if (attribute is null)
        {
            error = "referenced annotation field does not match the pinned manifest";
            return null;
        }
        const declaration = referenceField(references, classifier, module_, *attribute, field, loadScope, error);
        if (error.length)
            return null;
        rendered ~= draft[cursor .. cast(size_t) offset] ~ declaration;
        cursor = cast(size_t) offset;
    }
    return rendered ~ draft[cursor .. $];
}

private string resolveMarkers(const ref JavaReferences references, const ref ApiType annotation,
        const ref Classifier classifier, string module_, const(JSONValue)[] markers, out string error)
{
    import std.algorithm.searching : canFind;

    string result;
    size_t pinned;
    foreach (ref marker; markers)
    {
        const spelling = marker.str;
        if (!pinnedMarker(annotation.decl.annotations, spelling, pinned))
        {
            error = "unsupported meta-annotation does not match the pinned declaration or order: " ~ spelling;
            return null;
        }
        const id = references.typeId(spelling);
        const nested = references.findType(id);
        if (nested is null || id == annotation.decl.id || nested.decl.kind != TypeKind.annotation
                || nested.decl.members.length)
        {
            error = "unsupported meta-annotation without an unambiguous marker declaration: " ~ spelling;
            return null;
        }
        const symbol = localSymbol(mappedSymbol(classifier, id), module_ ~ ".");
        if (!symbol.length)
        {
            error = "unsupported meta-annotation outside destination module or without an exact mapping: " ~ id;
            return null;
        }
        const entry = classifier.classify(id);
        if (entry.status == Status.adapted && !entry.rules.canFind("R2"))
        {
            error = "unsupported adapted meta-annotation without R2: " ~ id;
            return null;
        }
        result ~= "@" ~ symbol ~ "\n";
    }
    return result;
}

private bool pinnedMarker(const(string)[] annotations, string spelling, ref size_t next)
{
    const expression = "@" ~ spelling;
    const withParens = expression ~ "()";
    while (next < annotations.length)
    {
        const value = annotations[next++];
        if (value == expression || value == withParens)
            return true;
    }
    return false;
}

private string referenceField(const ref JavaReferences references, const ref Classifier classifier, string module_,
        const ref Member attribute, const ref JSONValue field, scope AnnotationScope loadScope, out string error)
{
    import std.algorithm.searching : canFind;

    const reference = field["reference"];
    const javaType = reference["type"].str;
    const id = references.typeId(javaType);
    const array = reference["array"].boolean;
    const option = references.findType(id);
    if (option is null || (option.decl.kind != TypeKind.enum_
            && option.decl.kind != TypeKind.annotation) || !matchesAttribute(attribute.type, javaType, array))
    {
        error = attribute.name ~ ": unsupported annotation type " ~ javaType ~ " in the pinned manifest";
        return null;
    }

    const nested = option.decl.kind == TypeKind.annotation;
    const typeSymbol = mappedSymbol(classifier, id);
    const modulePrefix = module_ ~ ".";
    const fieldType = localSymbol(typeSymbol, modulePrefix);
    if (!fieldType.length)
    {
        const kind = nested ? "nested annotation" : "enum";
        error = attribute.name ~ ": unsupported " ~ kind ~ " type outside destination module or without a mapping: "
            ~ id;
        return null;
    }
    if (classifier.classify(id).rules.canFind("R15"))
    {
        error = attribute.name ~ ": unsupported R15 enum annotation type: " ~ id;
        return null;
    }
    if (nested && !classifier.classify(id).rules.canFind("R2"))
    {
        error = attribute.name ~ ": unsupported nested annotation type without an R2 mapping: " ~ id;
        return null;
    }
    const defaults = reference["defaults"];
    string declaration = "    " ~ fieldType ~ (array ? "[] " : " ") ~ field["symbol"].str;
    if (!defaults.isNull)
        declaration ~= referenceInitializer(references, classifier, *option, attribute,
                typeSymbol, modulePrefix, defaults, array, loadScope, error);
    else if (attribute.defaultValue.length)
        error = attribute.name ~ ": unsupported reference default does not match the pinned manifest";
    return declaration ~ ";\n";
}

private bool matchesAttribute(string spelling, string helperType, bool array)
{
    import std.algorithm.searching : endsWith;

    if (array != spelling.endsWith("[]"))
        return false;
    const base = array ? spelling[0 .. $ - 2] : spelling;
    return base == helperType;
}

private string referenceInitializer(const ref JavaReferences references, const ref Classifier classifier,
        const ref ApiType option, const ref Member attribute, string typeSymbol, string modulePrefix,
        const ref JSONValue defaults, bool array, scope AnnotationScope loadScope, out string error)
{
    import std.array : join;

    const javaDefaults = manifestDefaults(attribute.defaultValue);
    const elements = defaults.arrayNoRef;
    if ((!array && elements.length != 1) || elements.length != javaDefaults.length || !attribute.defaultValue.length)
    {
        error = attribute.name ~ ": unsupported reference default does not match the pinned manifest";
        return null;
    }
    string[] names;
    foreach (index, ref element; elements)
    {
        string symbol;
        if (element.type == JSONType.object && option.decl.kind == TypeKind.annotation)
            symbol = enumArgument(references, classifier, option, typeSymbol, modulePrefix,
                    element, javaDefaults[index], loadScope, error);
        else if (element.type != JSONType.string || element.str != javaDefaults[index])
        {
            error = attribute.name ~ ": unsupported reference default does not match the pinned manifest";
            return null;
        }
        else
            symbol = option.decl.kind == TypeKind.annotation ? nestedDefault(references, option,
                    attribute, typeSymbol, element.str, error) : enumDefault(references, classifier,
                    option, attribute, typeSymbol, element.str, error);
        if (error.length)
            return null;
        names ~= symbol[modulePrefix.length .. $];
    }

    return array ? " = [" ~ names.join(", ") ~ "]" : " = " ~ names[0];
}

private string localSymbol(string symbol, string prefix)
{
    import std.algorithm.searching : startsWith;
    import std.string : indexOf;

    if (!symbol.startsWith(prefix) || symbol[prefix.length .. $].indexOf('.') >= 0)
        return null;
    return symbol[prefix.length .. $];
}

private string enumDefault(const ref JavaReferences references, const ref Classifier classifier,
        const ref ApiType option, const ref Member attribute, string typeSymbol, string expression, out string error)
{
    const name = references.constantName(option, expression);
    const constant = memberNamed(option.decl.members, name, MemberKind.constant);
    if (constant is null)
    {
        error = attribute.name ~ ": unsupported enum constant in the pinned manifest: " ~ expression;
        return null;
    }
    const prefix = typeSymbol ~ ".";
    const symbol = mappedSymbol(classifier, memberId(option.decl, *constant));
    if (!localSymbol(symbol, prefix).length)
    {
        error = attribute.name ~ ": unsupported enum constant mapping: " ~ expression;
        return null;
    }
    return symbol;
}

private string enumArgument(const ref JavaReferences useSite, const ref Classifier classifier, const ref ApiType nested,
        string typeSymbol, string modulePrefix, const ref JSONValue expression, string pinned,
        scope AnnotationScope loadScope, out string error)
{
    import flint_tool.api.java : lex, render;
    import std.algorithm.searching : canFind;

    const javaName = expression["annotation"].str;
    const token = expression["constant"].str;
    const spelling = "@" ~ javaName ~ "(" ~ (expression["named"].boolean ? "value = " : "") ~ token ~ ")";
    if (spelling != pinned || render(lex(expression["source"].str)) != pinned
            || useSite.typeId(javaName) != nested.decl.id)
    {
        error = nested.decl.id ~ ": unsupported nested argument does not match the pinned manifest: " ~ spelling;
        return null;
    }

    const value = memberNamed(nested.decl.members, "value", MemberKind.attribute);
    if (value is null || mappedSymbol(classifier, memberId(nested.decl,
            *value)) != typeSymbol ~ ".value" || !classifier.classify(memberId(nested.decl,
            *value)).rules.canFind("R2"))
    {
        error = nested.decl.id ~ ": unsupported single argument without an exact R2 value mapping";
        return null;
    }
    const required = requiredAttribute(nested, "value");
    if (required.length)
    {
        error = nested.decl.id ~ ": unsupported single argument with required attribute " ~ required;
        return null;
    }

    const option = nestedValueEnum(useSite.types, nested, value.type, loadScope, error);
    if (option is null)
        return null;
    const enumSymbol = mappedSymbol(classifier, option.decl.id);
    if (!localSymbol(enumSymbol, modulePrefix).length || classifier.classify(option.decl.id).rules.canFind("R15"))
    {
        error = nested.decl.id ~ ": unsupported enum value without a D enum mapping in the destination module";
        return null;
    }
    const constant = enumDefault(useSite, classifier, *option, *value, enumSymbol, token, error);
    return error.length ? null : typeSymbol ~ "(" ~ constant[modulePrefix.length .. $] ~ ")";
}

private const(ApiType)* nestedValueEnum(const(ApiType)[] types, const ref ApiType nested,
        string javaType, scope AnnotationScope loadScope, out string error)
{
    JSONValue declaration;
    if (loadScope is null || !loadScope(nested, declaration, error))
    {
        error = nested.decl.id ~ ": unsupported annotation declaration scope: " ~ error;
        return null;
    }
    if (declaration["package"].str != nested.decl.package_ || declaration["name"].str != nested.decl.name)
    {
        error = nested.decl.id ~ ": unsupported annotation scope does not match the pinned manifest";
        return null;
    }
    const scope_ = JavaReferences(types, nested.decl.package_, declaration["referenceImports"].arrayNoRef);
    const option = scope_.findType(scope_.typeId(javaType));
    if (option is null || option.decl.kind != TypeKind.enum_)
    {
        error = nested.decl.id ~ ": unsupported value type in the pinned enum manifest: " ~ javaType;
        return null;
    }
    return option;
}

private string requiredAttribute(const ref ApiType nested, string supplied = "")
{
    foreach (ref member; nested.decl.members)
        if (member.name != supplied && !member.defaultValue.length)
            return member.name;
    return null;
}

private string nestedDefault(const ref JavaReferences references, const ref ApiType nested,
        const ref Member attribute, string typeSymbol, string expression, out string error)
{
    import std.algorithm.searching : endsWith;

    if (expression.length && expression[0] == '@')
    {
        const spelling = expression[1 .. $];
        const name = spelling.endsWith("()") ? spelling[0 .. $ - 2] : spelling;
        if (references.typeId(name) == nested.decl.id)
        {
            const required = requiredAttribute(nested);
            if (required.length)
            {
                error = attribute.name ~ ": unsupported zero-argument nested default for "
                    ~ nested.decl.id ~ " with required attribute " ~ required;
                return null;
            }
            return typeSymbol ~ ".init";
        }
    }
    error = attribute.name ~ ": unsupported nested annotation default: " ~ expression;
    return null;
}

/// Split a canonical manifest default whose elements are single tokens or comma-free expressions.
package string[] manifestDefaults(string text)
{
    import std.algorithm.iteration : splitter;
    import std.string : strip;

    text = text.strip;
    if (!text.length)
        return null;
    if (text[0] == '{' && text[$ - 1] == '}')
    {
        text = text[1 .. $ - 1].strip;
        if (text.length && text[$ - 1] == ',')
            text = text[0 .. $ - 1].strip;
    }
    string[] names;
    if (text.length)
        foreach (value; text.splitter(','))
            names ~= value.strip;
    return names;
}

private string simpleName(string spelling)
{
    import std.string : lastIndexOf;

    return spelling[spelling.lastIndexOf('.') + 1 .. $];
}

private struct JavaReferences
{
    private struct ImportMatch
    {
        string id;
        bool ambiguous;
    }

    const(ApiType)[] types;
    string package_;
    const(JSONValue)[] imports;

    const(ApiType)* findType(string id) const
    {
        if (!id.length)
            return null;
        foreach (ref type; types)
            if (type.decl.id == id)
                return &type;
        return null;
    }

    string typeId(string name) const
    {
        import std.string : indexOf;

        if (name.indexOf('.') >= 0)
            return name;
        const explicit_ = singleImport(name, false);
        if (explicit_.ambiguous || explicit_.id.length)
            return explicit_.id;
        const local = package_ ~ "." ~ name;
        if (findType(local) !is null)
            return local;
        return onDemand(name, false);
    }

    string constantName(const ref ApiType type, string name) const
    {
        import std.string : lastIndexOf;

        const period = name.lastIndexOf('.');
        if (period >= 0)
            return typeId(name[0 .. period]) == type.decl.id ? name[period + 1 .. $] : null;
        const explicit_ = singleImport(name, true);
        if (explicit_.ambiguous)
            return null;
        const id = explicit_.id.length ? explicit_.id : onDemand(name, true);
        return id == type.decl.id ~ "." ~ name ? name : null;
    }

    private ImportMatch singleImport(string name, bool static_) const
    {
        string match;
        foreach (ref item; imports)
        {
            if (item["static"].boolean != static_ || item["wildcard"].boolean)
                continue;
            const path = item["path"].str;
            if (simpleName(path) != name)
                continue;
            if (match.length && match != path)
                return ImportMatch(null, true);
            match = path;
        }
        return ImportMatch(match);
    }

    private string onDemand(string name, bool static_) const
    {
        string match;
        foreach (ref item; imports)
        {
            if (item["static"].boolean != static_ || !item["wildcard"].boolean)
                continue;
            const path = item["path"].str;
            if (!knownScope(path, static_))
                return null;
            const id = path ~ "." ~ name;
            if (!hasImportedName(path, id, name, static_))
                continue;
            if (match.length && match != id)
                return null;
            match = id;
        }
        return match;
    }

    private bool knownScope(string path, bool static_) const
    {
        if (findType(path) !is null)
            return true;
        if (!static_)
        {
            foreach (ref type; types)
                if (type.decl.package_ == path)
                    return true;
        }
        return false;
    }

    private bool hasImportedName(string path, string id, string name, bool static_) const
    {
        if (!static_)
            return findType(id) !is null;
        const owner = findType(path);
        return memberNamed(owner.decl.members, name, MemberKind.constant) !is null
            || memberNamed(owner.decl.members, name, MemberKind.field) !is null;
    }
}

private const(Member)* memberNamed(const(Member)[] members, string name, MemberKind kind)
{
    foreach (ref member; members)
        if (member.kind == kind && member.name == name)
            return &member;
    return null;
}

private string mappedSymbol(const ref Classifier classifier, string id)
{
    const entry = classifier.classify(id);
    if (entry is null || entry.match != id || (entry.status != Status.ported
            && entry.status != Status.adapted) || !validSymbol(entry.symbol))
        return null;
    return entry.symbol;
}

@("marker meta-annotations use exact same-module mapping and pinned order")
unittest
{
    import flint_tool.api.coverage : Mapping, parseMapping;
    import std.json : parseJSON;
    import std.string : indexOf;

    Manifest manifest;
    manifest.types.length = 3;
    foreach (ref marker; manifest.types)
        marker.decl.kind = TypeKind.annotation;
    manifest.types[0].decl.package_ = "one";
    manifest.types[0].decl.name = "Index";
    manifest.types[1].decl.package_ = "two";
    manifest.types[1].decl.name = "Root";
    manifest.types[2].decl.package_ = "two";
    manifest.types[2].decl.name = "Index";
    ApiType annotation;
    annotation.decl.package_ = "example";
    annotation.decl.name = "Setting";
    annotation.decl.annotations = ["@Root()", "@Index"];
    Mapping mapping;
    string error;
    assert(parseMapping(`{"elements":{
        "one.Index":{"status":"ported","d":"flint.example.Indexed"},
        "two.Root":{"status":"adapted","rules":["R2"],"d":"flint.example.Rooted"},
        "two.Index":{"status":"excluded","category":"deferred","phase":"2"}
    }}`, mapping, error), error);
    const classifier = Classifier(mapping);
    auto candidate = parseJSON(`{"package":"example","metaMarkers":["Root","Index"],
        "referenceImports":[{"path":"one.Index","static":false,"wildcard":false},
        {"path":"two","static":false,"wildcard":true}],
        "members":[],"metaBody":"struct Setting {}\n"}`);
    assert(resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate,
            error) == "@Rooted\n@Indexed\nstruct Setting {}\n", error);
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.other", candidate, error).length);
    assert(error.indexOf("outside destination module") >= 0, error);

    annotation.decl.annotations = ["@Index", "@Root()"];
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate, error).length);
    assert(error.indexOf("pinned declaration or order") >= 0, error);
    annotation.decl.annotations = ["@Root(42)", "@Index"];
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate, error).length);
    assert(error.indexOf("pinned declaration or order") >= 0, error);

    annotation.decl.annotations = ["@Root", "@Index"];
    candidate["referenceImports"][0]["path"] = JSONValue("two.Index");
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate, error).length);
    assert(error.indexOf("without an exact mapping") >= 0, error);
    candidate["referenceImports"][0]["path"] = JSONValue("one");
    candidate["referenceImports"][0]["wildcard"] = JSONValue(true);
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate, error).length);
    assert(error.indexOf("unambiguous marker declaration") >= 0, error);
}

@("enum defaults use exact manifest constants and canonical mapped symbols")
unittest
{
    import flint_tool.api.coverage : Mapping, parseMapping;
    import std.json : parseJSON;
    import std.string : indexOf;

    Manifest manifest;
    manifest.types.length = 1;
    auto option = &manifest.types[0].decl;
    option.name = "Mode";
    option.package_ = "example";
    option.kind = TypeKind.enum_;
    option.members.length = 1;
    option.members[0].name = "FAST";
    option.members[0].kind = MemberKind.constant;
    ApiType annotation;
    annotation.decl.members.length = 1;
    annotation.decl.members[0] = Member(MemberKind.attribute, "value");
    annotation.decl.members[0].type = "Mode[]";
    annotation.decl.members[0].defaultValue = "{ Mode.FAST, }";
    Mapping mapping;
    string error;
    assert(parseMapping(`{"elements":{
        "example.Mode":{"status":"ported","d":"flint.example.Choice"},
        "example.Mode#FAST":{"status":"adapted","rules":["R19"],"d":"flint.example.Choice.fast_"},
        "example.Mode#MISSING":{"status":"ported","d":"flint.example.Choice.missing"}
    }}`, mapping, error), error);
    const classifier = Classifier(mapping);
    const candidate = parseJSON(`{"package":"example","referenceImports":[],"referenceBody":"struct Setting\n{\n}\n",
        "members":[{"name":"value","symbol":"value",
        "reference":{"type":"Mode","offset":17,"array":true,"defaults":["Mode.FAST"]}}]}`);
    assert(resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate,
            error) == "struct Setting\n{\n    Choice[] value = [Choice.fast_];\n}\n", error);

    Mapping structEnum;
    assert(parseMapping(`{"elements":{
        "example.Mode":{"status":"adapted","rules":["R15"],"d":"flint.example.Choice"}
    }}`, structEnum, error), error);
    const structClassifier = Classifier(structEnum);
    assert(!resolveReferenceBody(manifest, annotation, structClassifier, "flint.example", candidate, error).length);
    assert(error.indexOf("unsupported R15 enum annotation type") >= 0, error);

    auto bad = parseJSON(`{"package":"example","referenceImports":[],"referenceBody":"struct Setting\n{\n}\n",
        "members":[{"name":"value","symbol":"value",
        "reference":{"type":"Mode","offset":17,"array":true,"defaults":["Mode.MISSING"]}}]}`);
    annotation.decl.members[0].defaultValue = "{ Mode.MISSING }";
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.example", bad, error).length);
    assert(error.indexOf("unsupported enum constant in the pinned manifest") >= 0, error);
}

@("Java enum references preserve import precedence and reject ambiguity")
unittest
{
    import std.json : parseJSON;

    ApiType[] options;
    foreach (package_; ["example", "first", "second"])
    {
        ApiType option;
        option.decl.name = "Mode";
        option.decl.package_ = package_;
        option.decl.kind = TypeKind.enum_;
        option.decl.members = [Member(MemberKind.constant, "FAST")];
        options ~= option;
    }
    const wildcard = parseJSON(`[
        {"path":"first","static":false,"wildcard":true},
        {"path":"second","static":false,"wildcard":true},
        {"path":"first.Mode","static":true,"wildcard":true},
        {"path":"second.Mode","static":true,"wildcard":true}
    ]`);
    const local = JavaReferences(options, "example", wildcard.arrayNoRef);
    assert(local.typeId("Mode") == "example.Mode");
    assert(local.typeId("first.Mode") == "first.Mode");
    assert(local.constantName(options[1], "second.Mode.FAST") is null);
    assert(local.constantName(options[1], "FAST") is null);
    const ambiguous = JavaReferences(options, "elsewhere", wildcard.arrayNoRef);
    assert(!ambiguous.typeId("Mode").length);

    const explicit_ = parseJSON(`[
        {"path":"first.Mode","static":false,"wildcard":false},
        {"path":"first.Mode.FAST","static":true,"wildcard":false},
        {"path":"second","static":false,"wildcard":true},
        {"path":"second.Mode","static":true,"wildcard":true}
    ]`);
    const imported = JavaReferences(options, "example", explicit_.arrayNoRef);
    assert(imported.typeId("Mode") == "first.Mode");
    assert(imported.constantName(options[1], "FAST") == "FAST");

    const singleDemand = parseJSON(`[
        {"path":"first","static":false,"wildcard":true},
        {"path":"first.Mode","static":true,"wildcard":true}
    ]`);
    const demand = JavaReferences(options, "elsewhere", singleDemand.arrayNoRef);
    assert(demand.typeId("Mode") == "first.Mode");
    assert(demand.constantName(options[1], "FAST") == "FAST");
}

@("zero-argument nested defaults require an exact R2 mapping and defaulted attributes")
unittest
{
    import flint_tool.api.coverage : Mapping, parseMapping;
    import std.json : parseJSON;
    import std.string : indexOf;

    Manifest manifest;
    manifest.types.length = 1;
    auto nested = &manifest.types[0].decl;
    nested.name = "Nested";
    nested.package_ = "example";
    nested.kind = TypeKind.annotation;
    nested.members = [Member(MemberKind.attribute, "label")];
    nested.members[0].defaultValue = `"default"`;
    ApiType annotation;
    annotation.decl.members = [
        Member(MemberKind.attribute, "value"), Member(MemberKind.attribute, "items")
    ];
    annotation.decl.members[0].type = "Nested";
    annotation.decl.members[0].defaultValue = "@Nested";
    annotation.decl.members[1].type = "Nested[]";
    annotation.decl.members[1].defaultValue = "@Nested()";
    Mapping mapping;
    string error;
    assert(parseMapping(`{"elements":{
        "example.Nested":{"status":"adapted","rules":["R2"],"d":"flint.example.Mapped"}
    }}`, mapping, error), error);
    const classifier = Classifier(mapping);
    const candidate = parseJSON(`{"package":"example","referenceImports":[],"referenceBody":"struct Setting\n{\n}\n",
        "members":[{"name":"value","symbol":"value",
        "reference":{"type":"Nested","offset":17,"array":false,"defaults":["@Nested"]}},
        {"name":"items","symbol":"items",
        "reference":{"type":"Nested","offset":17,"array":true,"defaults":["@Nested()"]}}]}`);
    assert(resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate,
            error) == "struct Setting\n{\n    Mapped value = Mapped.init;\n    Mapped[] items = [Mapped.init];\n}\n",
            error);
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.other", candidate, error).length);
    assert(error.indexOf("outside destination module") >= 0, error);

    nested.members[0].defaultValue = null;
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate, error).length);
    assert(error.indexOf("required attribute label") >= 0, error);
}

@("nested enum arguments use distinct declaration and use-site scopes")
unittest
{
    import flint_tool.api.coverage : Mapping, parseMapping;
    import std.json : parseJSON;
    import std.string : indexOf;

    Manifest manifest;
    manifest.types.length = 3;
    foreach (index, package_; ["values", "example"])
    {
        auto option = &manifest.types[index].decl;
        option.name = "Mode";
        option.package_ = package_;
        option.kind = TypeKind.enum_;
        option.members = [Member(MemberKind.constant, "FAST")];
    }
    auto nested = &manifest.types[2].decl;
    nested.name = "Nested";
    nested.package_ = "example";
    nested.kind = TypeKind.annotation;
    nested.members = [Member(MemberKind.attribute, "value"), Member(MemberKind.attribute, "label")];
    nested.members[0].type = "Mode";
    nested.members[1].defaultValue = `"label"`;
    ApiType annotation;
    annotation.decl.members = [Member(MemberKind.attribute, "value")];
    annotation.decl.members[0].type = "Nested[]";
    annotation.decl.members[0].defaultValue = "{@Nested(value = FAST), @Nested(values.Mode.FAST)}";
    Mapping mapping;
    string error;
    assert(parseMapping(`{"elements":{
        "example.Nested":{"status":"adapted","rules":["R2"],"d":"flint.example.Mapped"},
        "example.Nested#value":{"status":"adapted","rules":["R2"],"d":"flint.example.Mapped.value"},
        "values.Mode":{"status":"ported","d":"flint.example.Imported"},
        "values.Mode#FAST":{"status":"adapted","rules":["R19"],"d":"flint.example.Imported.fast_"},
        "example.Mode":{"status":"ported","d":"flint.example.Other"},
        "example.Mode#FAST":{"status":"ported","d":"flint.example.Other.FAST"}
    }}`, mapping, error), error);
    const classifier = Classifier(mapping);
    bool load(const ref ApiType type, out JSONValue result, out string failure) @safe
    {
        assert(type.decl.id == "example.Nested");
        result = parseJSON(`{"package":"example","name":"Nested","referenceImports":[
            {"path":"values.Mode","static":false,"wildcard":false}]}`);
        return true;
    }

    auto candidate = parseJSON(`{"package":"example","referenceBody":"struct Setting\n{\n}\n",
        "referenceImports":[{"path":"values.Mode.FAST","static":true,"wildcard":false}],
        "members":[{"name":"value","symbol":"value","reference":{"type":"Nested","offset":17,
        "array":true,"defaults":[{"source":"@Nested( value=FAST )","annotation":"Nested",
        "constant":"FAST","named":true},{"source":"@Nested(values.Mode.FAST)","annotation":"Nested",
        "constant":"values.Mode.FAST","named":false}]}}]}`);
    assert(resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate, error,
            &load) == "struct Setting\n{\n    Mapped[] value = [Mapped(Imported.fast_), Mapped(Imported.fast_)];\n}\n",
            error);

    nested.members[1].defaultValue = null;
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate, error, &load).length);
    assert(error.indexOf("required attribute label") >= 0, error);
    nested.members[1].defaultValue = `"label"`;

    annotation.decl.members[0].defaultValue = "{@Nested(value = FAST), @Nested(Mode.FAST)}";
    auto second = &candidate["members"][0]["reference"]["defaults"][1];
    (*second)["source"] = JSONValue("@Nested(Mode.FAST)");
    (*second)["constant"] = JSONValue("Mode.FAST");
    assert(!resolveReferenceBody(manifest, annotation, classifier, "flint.example", candidate, error, &load).length);
    assert(error.indexOf("unsupported enum constant in the pinned manifest") >= 0, error);
}

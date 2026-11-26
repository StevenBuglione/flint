/// Complete annotation fields whose Java enum types and defaults need manifest and mapping lookup.
module flint_tool.api.enum_defaults;

import flint_tool.api.coverage : Classifier, Status, validSymbol;
import flint_tool.api.java : Member, MemberKind, TypeKind;
import flint_tool.api.manifest : ApiType, Manifest, memberId;
import std.json : JSONValue;

@safe:

/// Add the enum fields to the helper's draft body. An empty result reports a reference that cannot be ported.
string enumAnnotationBody(const ref Manifest manifest, const ref ApiType annotation,
        const ref Classifier classifier, string module_, const ref JSONValue candidate, out string error)
{
    const draft = candidate["enumBody"].str;
    const references = JavaReferences(manifest.types, candidate["package"].str, candidate["enumImports"].arrayNoRef);
    string rendered;
    size_t cursor;
    foreach (ref field; candidate["members"].arrayNoRef)
    {
        if ("enum" !in field)
            continue;
        const reference = field["enum"];
        const offset = reference["offset"].integer;
        if (offset < 0 || offset < cursor || offset >= draft.length)
        {
            error = "invalid helper offset for enum annotation field";
            return null;
        }
        const attribute = memberNamed(annotation.decl.members, field["name"].str, MemberKind.attribute);
        if (attribute is null)
        {
            error = "enum annotation field does not match the pinned manifest";
            return null;
        }
        const declaration = enumField(references, classifier, module_, *attribute, field, error);
        if (error.length)
            return null;
        rendered ~= draft[cursor .. cast(size_t) offset] ~ declaration;
        cursor = cast(size_t) offset;
    }
    return rendered ~ draft[cursor .. $];
}

private string enumField(const ref JavaReferences references, const ref Classifier classifier,
        string module_, const ref Member attribute, const ref JSONValue field, out string error)
{
    import std.algorithm.searching : canFind, startsWith;
    import std.string : indexOf;

    const reference = field["enum"];
    const javaType = reference["type"].str;
    const id = references.typeId(javaType);
    const array = reference["array"].boolean;
    const option = references.findType(id);
    if (option is null || option.decl.kind != TypeKind.enum_ || !matchesAttribute(attribute.type, javaType, array))
    {
        error = attribute.name ~ ": unsupported annotation type " ~ javaType ~ " in the pinned enum manifest";
        return null;
    }

    const typeSymbol = mappedSymbol(classifier, id);
    const modulePrefix = module_ ~ ".";
    if (!typeSymbol.startsWith(modulePrefix) || typeSymbol[modulePrefix.length .. $].indexOf('.') >= 0)
    {
        error = attribute.name ~ ": unsupported enum type outside destination module or without a mapping: " ~ id;
        return null;
    }
    if (classifier.classify(id).rules.canFind("R15"))
    {
        error = attribute.name ~ ": unsupported R15 enum annotation type: " ~ id;
        return null;
    }
    const defaults = reference["defaults"];
    string declaration = "    " ~ typeSymbol[modulePrefix.length .. $] ~ (array ? "[] " : " ") ~ field["symbol"].str;
    if (!defaults.isNull)
        declaration ~= enumInitializer(references, classifier, *option, attribute, typeSymbol,
                modulePrefix, defaults, array, error);
    else if (attribute.defaultValue.length)
        error = attribute.name ~ ": unsupported enum default does not match the pinned manifest";
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

private string enumInitializer(const ref JavaReferences references, const ref Classifier classifier,
        const ref ApiType option, const ref Member attribute, string typeSymbol, string modulePrefix,
        const ref JSONValue defaults, bool array, out string error)
{
    import std.algorithm.searching : startsWith;
    import std.array : join;
    import std.string : indexOf;

    const javaNames = manifestDefaults(attribute.defaultValue);
    const elements = defaults.arrayNoRef;
    if ((!array && elements.length != 1) || elements.length != javaNames.length || !attribute.defaultValue.length)
    {
        error = attribute.name ~ ": unsupported enum default does not match the pinned manifest";
        return null;
    }
    const prefix = typeSymbol ~ ".";
    string[] names;
    foreach (index, ref element; elements)
    {
        const name = references.constantName(option, element.str);
        const constant = memberNamed(option.decl.members, name, MemberKind.constant);
        if (constant is null || element.str != javaNames[index])
        {
            error = attribute.name ~ ": unsupported enum constant in the pinned manifest: " ~ element.str;
            return null;
        }
        const symbol = mappedSymbol(classifier, memberId(option.decl, *constant));
        if (!symbol.startsWith(prefix) || symbol[prefix.length .. $].indexOf('.') >= 0)
        {
            error = attribute.name ~ ": unsupported enum constant mapping: " ~ element.str;
            return null;
        }
        names ~= symbol[modulePrefix.length .. $];
    }

    return array ? " = [" ~ names.join(", ") ~ "]" : " = " ~ names[0];
}

private string[] manifestDefaults(string text)
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
    const candidate = parseJSON(`{"package":"example","enumImports":[],"enumBody":"struct Setting\n{\n}\n",
        "members":[{"name":"value","symbol":"value",
        "enum":{"type":"Mode","offset":17,"array":true,"defaults":["Mode.FAST"]}}]}`);
    assert(enumAnnotationBody(manifest, annotation, classifier, "flint.example", candidate,
            error) == "struct Setting\n{\n    Choice[] value = [Choice.fast_];\n}\n", error);

    Mapping structEnum;
    assert(parseMapping(`{"elements":{
        "example.Mode":{"status":"adapted","rules":["R15"],"d":"flint.example.Choice"}
    }}`, structEnum, error), error);
    const structClassifier = Classifier(structEnum);
    assert(!enumAnnotationBody(manifest, annotation, structClassifier, "flint.example", candidate, error).length);
    assert(error.indexOf("unsupported R15 enum annotation type") >= 0, error);

    auto bad = parseJSON(`{"package":"example","enumImports":[],"enumBody":"struct Setting\n{\n}\n",
        "members":[{"name":"value","symbol":"value",
        "enum":{"type":"Mode","offset":17,"array":true,"defaults":["Mode.MISSING"]}}]}`);
    annotation.decl.members[0].defaultValue = "{ Mode.MISSING }";
    assert(!enumAnnotationBody(manifest, annotation, classifier, "flint.example", bad, error).length);
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

/// API manifests: the public Java API of one upstream project at one tag, as `flint.api-manifest/1` JSON
/// (ADR-030, API manifests).
///
/// A manifest lists every visible type and member. Each element has an id: a type's canonical Java name
/// (`org.springframework.http.HttpStatus.Series`), and for a member the type id, `#`, and its signature
/// (`query(String,RowMapper)`, `<init>(DataSource)`, or a field, constant, attribute or component name). Ids erase
/// annotations and type arguments, as Java overload identity does, so the mapping and diffs key on them.
///
/// The file holds one type per line, so a manifest diffs line by line in git.
module flint_tool.api.manifest;

import std.json : JSONOptions, JSONValue;
import flint_tool.api.java : Member, MemberKind, TypeDecl, TypeKind;

@safe:

/// Schema of the manifest document.
enum manifestSchema = "flint.api-manifest/1";

/// One type with the module and file it was declared in.
struct ApiType
{
    /// Module: the directory above `src/main/java`, or the project for a flat source archive.
    string module_;
    /// Root-relative path of the declaring file.
    string file;
    /// The declaration.
    TypeDecl decl;
}

/// Element counts of one module.
struct ModuleCounts
{
    /// Module name.
    string name;
    /// Types.
    size_t types;
    /// Methods.
    size_t methods;
    /// Constructors.
    size_t constructors;
    /// Fields.
    size_t fields;
    /// Enum constants.
    size_t constants;
    /// Annotation attributes.
    size_t attributes;
    /// Record components.
    size_t components;

    /// Every element: types and members.
    size_t elements() const
    {
        return types + methods + constructors + fields + constants + attributes + components;
    }
}

/// A whole manifest.
struct Manifest
{
    /// Upstream project.
    string project;
    /// Upstream tag.
    string version_;
    /// Types, sorted by id.
    ApiType[] types;

    /// Per-module counts, sorted by module.
    ModuleCounts[] modules() const
    {
        import std.algorithm.sorting : sort;

        ModuleCounts[string] counts;
        foreach (ref type; types)
        {
            auto entry = type.module_ in counts;
            if (entry is null)
            {
                counts[type.module_] = ModuleCounts(type.module_);
                entry = type.module_ in counts;
            }
            entry.types++;
            foreach (ref member; type.decl.members) final switch (member.kind)
            {
            case MemberKind.method:
                entry.methods++;
                break;
            case MemberKind.constructor:
                entry.constructors++;
                break;
            case MemberKind.field:
                entry.fields++;
                break;
            case MemberKind.constant:
                entry.constants++;
                break;
            case MemberKind.attribute:
                entry.attributes++;
                break;
            case MemberKind.component:
                entry.components++;
                break;
            }
        }
        auto list = counts.values;
        sort!((a, b) => a.name < b.name)(list);
        return list;
    }
}

/// The id of a member of `type`.
string memberId(const ref TypeDecl type, const ref Member member)
{
    return type.id ~ "#" ~ member.signature;
}

/// Render a manifest as JSON, one type per line.
string renderManifest(const ref Manifest manifest)
{
    import std.array : appender;

    auto text = appender!string;
    text ~= `{"schema":` ~ quote(manifestSchema) ~ `,"project":` ~ quote(
            manifest.project) ~ `,"version":` ~ quote(manifest.version_) ~ ",\n" ~ `"modules":[` ~ "\n";
    const modules = manifest.modules;
    foreach (index, ref counts; modules)
    {
        text ~= `{"name":` ~ quote(counts.name) ~ `,"types":` ~ number(
                counts.types) ~ `,"methods":` ~ number(counts.methods) ~ `,"constructors":` ~ number(
                counts.constructors) ~ `,"fields":` ~ number(counts.fields) ~ `,"constants":` ~ number(
                counts.constants) ~ `,"attributes":` ~ number(counts.attributes) ~ `,"components":` ~ number(
                counts.components) ~ "}" ~ (index + 1 < modules.length ? "," : "") ~ "\n";
    }
    text ~= "],\n" ~ `"types":[` ~ "\n";
    foreach (index, ref type; manifest.types)
        text ~= typeJson(type) ~ (index + 1 < manifest.types.length ? "," : "") ~ "\n";
    text ~= "]}\n";
    return text[];
}

private string quote(string text)
{
    return JSONValue(text).toString(JSONOptions.doNotEscapeSlashes);
}

private string number(size_t value)
{
    import std.conv : to;

    return value.to!string;
}

/// A JSON object written in insertion order, so manifests are byte-for-byte reproducible.
private struct Ordered
{
    string text;

    void add(string key, string value)
    {
        text ~= (text.length ? "," : "") ~ quote(key) ~ ":" ~ quote(value);
    }

    void raw(string key, string json)
    {
        text ~= (text.length ? "," : "") ~ quote(key) ~ ":" ~ json;
    }

    void list(string key, const(string)[] values, bool always = false)
    {
        if (values.length == 0 && !always)
            return;
        string json = "[";
        foreach (index, value; values)
            json ~= (index ? "," : "") ~ quote(value);
        raw(key, json ~ "]");
    }

    string done() const
    {
        return "{" ~ text ~ "}";
    }
}

private string typeJson(const ref ApiType type)
{
    Ordered object;
    const decl = &type.decl;
    object.add("id", decl.id);
    object.add("package", decl.package_);
    object.add("module", type.module_);
    object.add("file", type.file);
    object.add("kind", cast(string) decl.kind);
    object.add("visibility", decl.visibility);
    object.list("modifiers", decl.modifiers);
    object.list("annotations", decl.annotations);
    object.list("typeParameters", decl.typeParameters);
    object.list("extends", decl.extends_);
    object.list("implements", decl.implements_);
    object.list("permits", decl.permits);
    string members = "[";
    foreach (index, ref member; decl.members)
        members ~= (index ? "," : "") ~ memberJson(member);
    object.raw("members", members ~ "]");
    return object.done;
}

private string memberJson(const ref Member member)
{
    Ordered object;
    object.add("kind", cast(string) member.kind);
    object.add("name", member.name);
    object.add("signature", member.signature);
    object.add("visibility", member.visibility);
    object.list("modifiers", member.modifiers);
    object.list("annotations", member.annotations);
    object.list("typeParameters", member.typeParameters);
    if (member.type.length)
        object.add("type", member.type);
    object.list("parameters", member.parameters, member.kind == MemberKind.method
            || member.kind == MemberKind.constructor);
    object.list("throws", member.throws_);
    if (member.defaultValue.length)
        object.add("default", member.defaultValue);
    if (member.implicit_)
        object.raw("implicit", "true");
    return object.done;
}

/// Parse a manifest document; false with `error` set when it is not one.
bool parseManifest(string text, out Manifest manifest, out string error)
{
    import std.json : JSONException, JSONType, parseJSON;

    JSONValue root;
    try
        root = parseJSON(text);
    catch (JSONException failure)
    {
        error = failure.msg;
        return false;
    }
    if (root.type != JSONType.object || "schema" !in root || root["schema"].type != JSONType.string
            || root["schema"].str != manifestSchema)
    {
        error = "not a " ~ manifestSchema ~ " document";
        return false;
    }
    try
    {
        manifest.project = root["project"].str;
        manifest.version_ = root["version"].str;
        foreach (ref item; root["types"].arrayNoRef)
            manifest.types ~= readType(item);
    }
    catch (JSONException failure)
    {
        error = "malformed manifest: " ~ failure.msg;
        return false;
    }
    return true;
}

/// Read a manifest file.
bool loadManifest(string path, out Manifest manifest, out string error)
{
    import std.file : FileException, readText;

    string text;
    try
        text = readText(path);
    catch (FileException failure)
    {
        error = failure.msg;
        return false;
    }
    if (!parseManifest(text, manifest, error))
    {
        error = path ~ ": " ~ error;
        return false;
    }
    return true;
}

private ApiType readType(ref const JSONValue item)
{
    import std.json : JSONException;

    ApiType type;
    type.module_ = item["module"].str;
    type.file = text(item, "file");
    const id = item["id"].str;
    type.decl.kind = typeKind(item["kind"].str);
    type.decl.visibility = text(item, "visibility");
    type.decl.modifiers = list(item, "modifiers");
    type.decl.annotations = list(item, "annotations");
    type.decl.typeParameters = list(item, "typeParameters");
    type.decl.extends_ = list(item, "extends");
    type.decl.implements_ = list(item, "implements");
    type.decl.permits = list(item, "permits");
    type.decl.package_ = text(item, "package");
    const prefix = type.decl.package_.length ? type.decl.package_.length + 1 : 0;
    if (id.length <= prefix)
        throw new JSONException("type id `" ~ id ~ "` is outside its package");
    type.decl.name = id[prefix .. $];
    if ("members" in item)
        foreach (ref value; item["members"].arrayNoRef)
            type.decl.members ~= readMember(value);
    return type;
}

private Member readMember(ref const JSONValue item)
{
    Member member;
    member.kind = memberKind(item["kind"].str);
    member.name = item["name"].str;
    member.visibility = text(item, "visibility");
    member.modifiers = list(item, "modifiers");
    member.annotations = list(item, "annotations");
    member.typeParameters = list(item, "typeParameters");
    member.type = text(item, "type");
    member.parameters = list(item, "parameters");
    member.throws_ = list(item, "throws");
    member.defaultValue = text(item, "default");
    member.implicit_ = "implicit" in item && item["implicit"].boolean;
    return member;
}

private string text(ref const JSONValue item, string key)
{
    return key in item ? item[key].str : null;
}

private string[] list(ref const JSONValue item, string key)
{
    string[] values;
    if (key in item)
        foreach (ref value; item[key].arrayNoRef)
            values ~= value.str;
    return values;
}

private TypeKind typeKind(string text)
{
    import std.json : JSONException;

    foreach (kind; [
        TypeKind.class_, TypeKind.interface_, TypeKind.enum_, TypeKind.record, TypeKind.annotation
    ])
    {
        if (kind == text)
            return kind;
    }
    throw new JSONException("unknown type kind `" ~ text ~ "`");
}

private MemberKind memberKind(string text)
{
    import std.json : JSONException;

    foreach (kind; [
        MemberKind.method, MemberKind.constructor, MemberKind.field, MemberKind.constant,
        MemberKind.attribute, MemberKind.component
    ])
    {
        if (kind == text)
            return kind;
    }
    throw new JSONException("unknown member kind `" ~ text ~ "`");
}

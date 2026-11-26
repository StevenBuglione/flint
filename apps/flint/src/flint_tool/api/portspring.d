/// Validate an optional native translator's candidate against Flint's pinned API and licence policy.
module flint_tool.api.portspring;

import flint_tool.api.coverage : Classifier, Mapping, MappingEntry, Status;
import flint_tool.api.headers : LicenceEntry;
import flint_tool.api.java : MemberKind, TypeDecl, TypeKind;
import flint_tool.api.manifest : ApiType, Manifest, memberId;
import flint_tool.api.upstreams : Upstream;
import std.json : JSONValue;

@safe:

/// One type requested from the pinned source cache.
struct SpringPortRequest
{
    /// Upstream project name.
    string project;
    /// Upstream tag or release.
    string tag;
    /// Canonical Java type id from flint api extract.
    string type;
    /// Destination D module name.
    string module_;
    /// Override the API reference cache root.
    string cache;
    /// Override the opt-in native helper executable.
    string helper;
    /// Allow proposed replacements for previously ported or adapted elements.
    bool replacePorted;
}

/// A checked source and corresponding replacement mapping.
struct SpringPort
{
    /// D source with its verified upstream header.
    string source;
    /// Rulebook-v2 mapping fragment for the translated declarations.
    string mapping;
    /// Java's Inherited metadata requires a separate AOT review.
    bool inherited;
}

/// Translate a single public annotation or constants-only enum.
bool portSpring(string root, const ref SpringPortRequest request, out SpringPort output, out string error)
{
    import flint_tool.api.upstreams : findUpstream, loadUpstreams;
    import std.file : FileException;
    import std.json : JSONException;

    if (!request.project.length || !request.tag.length || !request.type.length || !validModule(request.module_))
    {
        error = "port-spring requires --project, --tag, --type and a flint.* --module";
        return false;
    }
    try
    {
        auto pins = loadUpstreams(root, error);
        if (error.length)
            return false;
        const pin = findUpstream(pins, request.project, request.tag);
        if (pin is null)
        {
            error = request.project ~ "@" ~ request.tag ~ " is not pinned in api/upstreams.json";
            return false;
        }
        if (pin.signaturesOnly)
        {
            error = pin.key ~ " is pinned for signatures only";
            return false;
        }
        return portPinned(root, request, *pin, pins, output, error);
    }
    catch (FileException failure)
    {
        error = failure.msg;
    }
    catch (JSONException failure)
    {
        error = "malformed translator input or reply: " ~ failure.msg;
    }
    return false;
}

private bool portPinned(string root, const ref SpringPortRequest request, const ref Upstream pin,
        const(Upstream)[] pins, ref SpringPort output, out string error)
{
    import flint_tool.api.headers : parseLicenceMatrix;
    import flint_tool.api.manifest : loadManifest;
    import std.file : readText;
    import std.path : buildPath;

    LicenceEntry[] matrix;
    if (!parseLicenceMatrix(readText(buildPath(root, "policy", "upstream-licences.json")), matrix, error))
        return false;
    const licence = destinationLicence(pin, matrix, error);
    if (licence is null)
        return false;
    Manifest manifest;
    const path = buildPath(root, "api", "upstream", pin.key ~ ".json");
    if (!loadManifest(path, manifest, error))
        return false;
    const type = supportedType(manifest, pin, request.type, error);
    if (type is null)
        return false;
    const source = sourcePath(root, request, pin, type.file, error);
    if (!source.length)
        return false;
    JSONValue candidate;
    if (!runHelper(root, request.helper, source, candidate, error))
        return false;
    string body;
    const fragment = mappingFragment(root, pin, manifest, *type, request, candidate, body, error);
    if (!fragment.length)
        return false;
    const text = checkedSource(pin, pins, matrix, *licence, type.file, source, request.module_,
            candidate, body, error);
    if (!text.length)
        return false;
    output = SpringPort(text, fragment, candidate["inherited"].boolean);
    return true;
}

private const(LicenceEntry)* destinationLicence(const ref Upstream pin, const(LicenceEntry)[] matrix, out string error)
{
    import flint_tool.api.headers : licenceFor;

    const entry = licenceFor(pin, matrix, error);
    if (entry is null)
        return null;
    switch (entry.use)
    {
    case "port-source":
    case "port-source-bsd-option":
        return entry;
    case "epl-module":
        error = "EPL translations require a registered EPL-2.0 destination package";
        return null;
    default:
        error = entry.use ~ " translations require a supported dedicated destination package";
        return null;
    }
}

private const(ApiType)* supportedType(ref const Manifest manifest, const ref Upstream pin, string id, out string error)
{
    if (manifest.project != pin.project || manifest.version_ != pin.version_)
    {
        error = "manifest project or version does not match " ~ pin.key;
        return null;
    }
    foreach (ref type; manifest.types)
    {
        if (type.decl.id != id)
            continue;
        if (type.decl.visibility != "public")
            break;
        if (type.decl.kind == TypeKind.annotation)
            return &type;
        if (type.decl.kind == TypeKind.enum_)
        {
            if (constantsOnly(type.decl))
                return &type;
            error = id ~ ": unsupported enum shape in the pinned manifest";
            return null;
        }
        break;
    }
    error = id ~ " is not a supported public type in the pinned manifest";
    return null;
}

private bool constantsOnly(const ref TypeDecl decl)
{
    if (!decl.members.length || decl.implements_.length)
        return false;
    foreach (ref member; decl.members)
        if (member.kind != MemberKind.constant)
            return false;
    return true;
}

private string sourcePath(string root, const ref SpringPortRequest request, const ref Upstream pin,
        string file, out string error)
{
    import flint_tool.api.upstreams : referenceCache;
    import std.algorithm.iteration : splitter;
    import std.file : exists, readText;
    import std.path : buildPath, isAbsolute;
    import std.string : indexOf;

    if (!file.length || isAbsolute(file) || file.indexOf('\\') >= 0 || file.indexOf(':') >= 0)
    {
        error = "manifest source path must be relative to the pinned source tree";
        return null;
    }
    foreach (part; file.splitter('/'))
    {
        if (!part.length || part == "." || part == "..")
        {
            error = "manifest source path must be relative to the pinned source tree";
            return null;
        }
    }
    const cache = request.cache.length ? request.cache : referenceCache(root);
    const tree = buildPath(cache, pin.key);
    const stamp = buildPath(tree, ".flint-api-fetch");
    if (!exists(stamp) || readText(stamp) != pin.sha256 ~ "\n")
    {
        error = "source cache is missing the checksum stamp for " ~ pin.key ~ "; run flint api fetch " ~ pin.project;
        return null;
    }
    return buildPath(tree, file);
}

private bool runHelper(string root, string helper, string source, out JSONValue candidate,
        out string error, bool scopeOnly = false)
{
    import flint_tool.support.process : capture;
    import std.path : absolutePath, buildPath;
    import std.json : parseJSON;
    import std.string : strip;

    version (Windows)
        enum executable = "flint-port-spring.exe";
    else
        enum executable = "flint-port-spring";
    if (!helper.length)
        helper = buildPath(root, ".flint", "port-spring", executable);
    string[] arguments = [absolutePath(helper)];
    if (scopeOnly)
        arguments ~= "--annotation-scope";
    const result = capture(arguments ~ source);
    if (!result.ok)
    {
        error = result.errors.length ? result.errors.strip : "cannot run " ~ helper ~ ": " ~ result.failure;
        return false;
    }
    candidate = parseJSON(result.output);
    return true;
}

private string mappingFragment(string root, const ref Upstream pin, const ref Manifest manifest,
        const ref ApiType type, const ref SpringPortRequest request, const ref JSONValue candidate,
        out string body, out string error)
{
    import flint_tool.api.coverage : parseMapping;
    import flint_tool.api.annotation_references : resolveReferenceBody;
    import std.file : readText;
    import std.path : buildPath;

    if (candidate["package"].str != type.decl.package_ || candidate["name"].str != type.decl.name
            || candidate["kind"].str != cast(string) type.decl.kind)
    {
        error = "translator declaration does not match " ~ type.decl.id ~ " in the manifest";
        return null;
    }
    string[] referenceFields;
    foreach (ref field; candidate["members"].arrayNoRef)
        if ("reference" in field)
            referenceFields ~= field["name"].str;
    const shadow = shadowedAttributeType(manifest, type, referenceFields);
    if (shadow.length)
    {
        error = type.decl.id ~ ": unsupported annotation type: ambiguous same-package " ~ shadow;
        return null;
    }
    Mapping mapping;
    const path = buildPath(root, "api", pin.repo, "mapping.json");
    if (!parseMapping(readText(path), mapping, error))
        return null;
    if (mapping.rulebook != 2 || !mapping.covers(pin.project, pin.version_))
    {
        error = path ~ " has no matching rulebook v2 mapping for " ~ pin.key;
        return null;
    }
    if (referenceFields.length)
    {
        const classifier = Classifier(mapping);
        JSONValue[string] scopes;
        bool loadScope(const ref ApiType nested, out JSONValue result, out string failure) @safe
        {
            const id = nested.decl.id;
            if (const saved = id in scopes)
            {
                result = *saved;
                return true;
            }
            const source = sourcePath(root, request, pin, nested.file, failure);
            if (!source.length || !runHelper(root, request.helper, source, result, failure, true))
                return false;
            scopes[id] = result;
            return true;
        }

        body = resolveReferenceBody(manifest, type, classifier, request.module_, candidate, error, &loadScope);
    }
    else
        body = candidate["body"].str;
    if (error.length)
        return null;
    return classifiedFragment(pin, type, request.module_, candidate, mapping, error, request.replacePorted);
}

private string attributeBaseType(string type)
{
    import std.algorithm.searching : endsWith;
    import std.string : indexOf;

    const generic = type.indexOf('<');
    if (generic >= 0)
        return type[0 .. generic];
    return type.endsWith("[]") ? type[0 .. $ - 2] : type;
}

private string shadowedAttributeType(const ref Manifest manifest, const ref ApiType annotation,
        const(string)[] resolvedFields = null)
{
    import std.algorithm.searching : canFind;

    bool[string] names;
    foreach (ref field; annotation.decl.members)
    {
        const name = attributeBaseType(field.type);
        if (identifier(name) && !resolvedFields.canFind(field.name))
            names[name] = true;
    }
    foreach (ref type; manifest.types)
        if (type.decl.package_ == annotation.decl.package_ && type.decl.name in names)
            return type.decl.name;
    return null;
}

private string classifiedFragment(const ref Upstream pin, const ref ApiType type, string module_,
        const ref JSONValue candidate, const ref Mapping mapping, out string error, bool replacePorted = false)
{
    import std.algorithm.sorting : sort;
    import std.array : join;

    const dName = candidate["symbol"].str;
    string[string] fields;
    foreach (ref field; candidate["members"].arrayNoRef)
        fields[field["name"].str] = field["symbol"].str;
    if (!identifier(dName) || fields.length != type.decl.members.length)
    {
        error = "translator symbols do not match the manifest for " ~ type.decl.id;
        return null;
    }
    const dType = module_ ~ "." ~ dName;
    MappingEntry[string] entries;
    const annotation = type.decl.kind == TypeKind.annotation;
    const memberKind = annotation ? MemberKind.attribute : MemberKind.constant;
    entries[type.decl.id] = mappingEntry(dType, type.decl.name, dName, annotation);
    foreach (ref member; type.decl.members)
    {
        const field = member.name in fields;
        if (member.kind != memberKind || field is null || !identifier(*field))
        {
            error = "translator field does not match " ~ memberId(type.decl, member) ~ " in the manifest";
            return null;
        }
        entries[memberId(type.decl, member)] = mappingEntry(dType ~ "." ~ *field, member.name,
                *field, annotation, member.type);
    }
    const classifier = Classifier(mapping);
    string[] lines;
    foreach (key; entries.keys.sort)
    {
        const proposed = entries[key];
        const current = classifier.classify(key);
        const line = replacement(key, current, proposed, replacePorted, error);
        if (error.length)
            return null;
        if (line.length)
            lines ~= line;
    }
    return "{\"rulebook\":2,\n\"upstream\":[" ~ quote(
            pin.project ~ "@" ~ pin.version_) ~ "],\n\"elements\":{\n" ~ lines.join(",\n") ~ "\n}}\n";
}

private string replacement(string key, const MappingEntry* current, const ref MappingEntry proposed,
        bool replacePorted, out string error)
{
    if (current is null)
    {
        error = "no existing mapping classification for " ~ key;
        return null;
    }
    const line = quote(key) ~ ":" ~ renderEntry(proposed);
    if (current.status == Status.excluded && current.category == "deferred")
        return line;
    if (current.status == Status.ported || current.status == Status.adapted)
    {
        if (replacePorted)
            return line;
        if (current.status == proposed.status && current.symbol == proposed.symbol && current.rules == proposed.rules)
            return null;
    }
    error = key ~ ": mapping conflict at " ~ current.match ~ "; existing " ~ renderEntry(
            *current) ~ "; proposed " ~ renderEntry(proposed);
    return null;
}

private string quote(string text)
{
    return JSONValue(text).toString();
}

private MappingEntry mappingEntry(string symbol, string javaName, string dName, bool annotation, string javaType = "")
{
    import std.string : replace;

    const renamed = javaName.replace("Spring", "Flint");
    MappingEntry entry;
    entry.symbol = symbol;
    if (annotation)
        entry.rules = ["R2"];
    if (javaName != renamed)
        entry.rules ~= "R1";
    const baseType = attributeBaseType(javaType);
    if (baseType == "Class" || baseType == "java.lang.Class")
        entry.rules ~= "R4";
    if (renamed != dName)
        entry.rules ~= "R19";
    entry.status = entry.rules.length ? Status.adapted : Status.ported;
    return entry;
}

private string renderEntry(const ref MappingEntry entry)
{
    const status = "{\"status\":" ~ quote(cast(string) entry.status);
    if (entry.status == Status.excluded)
        return status ~ ",\"category\":" ~ quote(entry.category) ~ ",\"phase\":" ~ quote(entry.phase) ~ "}";
    const rules = entry.rules.length ? ",\"rules\":" ~ JSONValue(entry.rules).toString() : "";
    return status ~ rules ~ ",\"d\":" ~ quote(entry.symbol) ~ "}";
}

private string checkedSource(const ref Upstream pin, const(Upstream)[] pins,
        const(imported!"flint_tool.api.headers".LicenceEntry)[] matrix,
        const ref imported!"flint_tool.api.headers".LicenceEntry licence,
        string file, string source, string module_, const ref JSONValue candidate, string body, out string error)
{
    import flint_tool.api.headers : checkHeader, licenceLine, modifiedNotice, portedMarker;
    import std.file : readText;

    const header = originalHeader(readText(source));
    const imports = candidate["classRef"].boolean ? "import flint.java.classref : ClassRef;\n\n" : "";
    const text = header ~ "\n// " ~ portedMarker ~ pin.project ~ " " ~ pin.version_ ~ ": " ~ file
        ~ "\n// " ~ licenceLine(licence) ~ "\n// " ~ modifiedNotice ~ ".\n\nmodule " ~ module_ ~ ";\n\n"
        ~ imports ~ "@safe:\n\n" ~ body;
    const problems = checkHeader(file, text, pins, matrix, "");
    if (problems.length)
    {
        error = file ~ ": " ~ problems[0].message;
        return null;
    }
    return text;
}

private string originalHeader(string java)
{
    import std.algorithm.searching : startsWith;
    import std.string : indexOf, lineSplitter, stripLeft;

    java = java.stripLeft;
    if (java.startsWith("/*"))
    {
        const end = java.indexOf("*/");
        return end < 0 ? null : java[0 .. end + 2];
    }
    string header;
    foreach (line; java.lineSplitter)
    {
        if (!line.stripLeft.startsWith("//"))
            break;
        header ~= line ~ "\n";
    }
    return header;
}

private bool validModule(string name)
{
    import std.algorithm.iteration : splitter;
    import std.algorithm.searching : startsWith;

    if (!name.startsWith("flint."))
        return false;
    foreach (part; name.splitter('.'))
        if (!identifier(part))
            return false;
    return true;
}

private bool identifier(string name)
{
    if (!name.length || !letter(name[0]))
        return false;
    foreach (byte_; name[1 .. $])
        if (!letter(byte_) && !(byte_ >= '0' && byte_ <= '9'))
            return false;
    return true;
}

private bool letter(char byte_)
{
    return (byte_ >= 'a' && byte_ <= 'z') || (byte_ >= 'A' && byte_ <= 'Z') || byte_ == '_';
}

version (unittest)
{
    private ApiType annotationFixture()
    {
        import flint_tool.api.java : Member;

        ApiType annotation;
        annotation.decl.kind = TypeKind.annotation;
        annotation.decl.package_ = "org.springframework.example";
        annotation.decl.name = "SpringHint";
        annotation.decl.visibility = "public";
        Member field;
        field.kind = MemberKind.attribute;
        field.name = "version";
        field.type = "int";
        annotation.decl.members = [field];
        return annotation;
    }

    private enum candidateFixture = `{"symbol":"FlintHint","members":[{"name":"version","symbol":"version_"}]}`;
}

unittest
{
    import flint_tool.api.coverage : Mapping, parseMapping;
    import std.json : parseJSON;
    import std.string : indexOf;

    const annotation = annotationFixture();
    const candidate = parseJSON(candidateFixture);
    Upstream pin;
    pin.project = "spring-framework";
    pin.version_ = "v7.1.0";
    Mapping mapping;
    string error;
    assert(parseMapping(`{"elements":{
        "org.springframework.example.**":{"status":"excluded","category":"deferred","phase":"2"},
        "org.springframework.example.SpringHint":{"status":"adapted","rules":["R2"],"d":"flint.legacy.Hint"}
    }}`, mapping, error), error);
    const output = classifiedFragment(pin, annotation, "flint.example", candidate, mapping, error);
    assert(output.length == 0 && error.indexOf("mapping conflict") >= 0, error);
    assert(error.indexOf("flint.legacy.Hint") >= 0 && error.indexOf("flint.example.FlintHint") >= 0, error);
    assert(classifiedFragment(pin, annotation, "flint.example", candidate, mapping, error, true).length, error);
}

unittest
{
    import flint_tool.api.coverage : Mapping, parseMapping;
    import std.json : parseJSON;

    const annotation = annotationFixture();
    const candidate = parseJSON(candidateFixture);
    Upstream pin;
    pin.project = "spring-framework";
    pin.version_ = "v7.1.0";
    Mapping mapping;
    string error;
    assert(parseMapping(`{"elements":{
        "org.springframework.example.**":{"status":"excluded","category":"deferred","phase":"2"}
    }}`, mapping, error), error);
    const output = classifiedFragment(pin, annotation, "flint.example", candidate, mapping, error);
    assert(output.length, error);
    Mapping generated;
    assert(parseMapping(output, generated, error), error);
    assert(generated.entries.length == 2);
    assert(generated.entries[0].match == annotation.decl.id && generated.entries[0].rules == [
        "R2", "R1"
    ]);
    assert(generated.entries[1].match == annotation.decl.id ~ "#version");
    assert(generated.entries[1].rules == ["R2", "R19"]);
}

unittest
{
    import std.json : parseJSON;
    import std.string : indexOf;

    const annotation = annotationFixture();
    const candidate = parseJSON(`{"symbol":"FlintHint","members":[]}`);
    Upstream pin;
    Mapping mapping;
    string error;
    assert(!classifiedFragment(pin, annotation, "flint.example", candidate, mapping, error).length);
    assert(error.indexOf("symbols do not match the manifest") >= 0, error);
    const entry = mappingEntry("flint.example.FlintHint.version_", "version", "version_", true,
            "Class<? extends Number>[]");
    assert(entry.rules == ["R2", "R4", "R19"]);
}

unittest
{
    import std.string : indexOf;

    Manifest manifest;
    manifest.project = "example";
    manifest.version_ = "1";
    auto annotation = annotationFixture();
    auto other = annotation;
    other.decl.name = "String";
    other.decl.kind = TypeKind.class_;
    annotation.decl.members[0].type = "String[]";
    manifest.types = [annotation, other];
    Upstream pin;
    pin.project = manifest.project;
    pin.version_ = manifest.version_;
    string error;
    assert(supportedType(manifest, pin, other.decl.id, error) is null);
    assert(error.indexOf("not a supported public type") >= 0, error);
    assert(supportedType(manifest, pin, "org.springframework.example.Missing", error) is null);
    assert(shadowedAttributeType(manifest, annotation) == "String");
}

@("enum manifest excludes interfaces and non-constant members")
unittest
{
    import std.string : indexOf;

    Manifest manifest;
    manifest.project = "example";
    manifest.version_ = "1";
    auto option = annotationFixture();
    option.decl.kind = TypeKind.enum_;
    option.decl.members[0].kind = MemberKind.constant;
    manifest.types = [option];
    Upstream pin;
    pin.project = manifest.project;
    pin.version_ = manifest.version_;
    const id = option.decl.id;
    string error;
    assert(supportedType(manifest, pin, id, error) !is null, error);

    manifest.types[0].decl.implements_ = ["example.Option"];
    assert(supportedType(manifest, pin, id, error) is null);
    assert(error.indexOf("unsupported enum shape") >= 0, error);

    manifest.types[0].decl.implements_ = null;
    manifest.types[0].decl.members[0].kind = MemberKind.method;
    assert(supportedType(manifest, pin, id, error) is null);
    assert(error.indexOf("unsupported enum shape") >= 0, error);

    manifest.types[0].decl.members = null;
    assert(supportedType(manifest, pin, id, error) is null);
    assert(error.indexOf("unsupported enum shape") >= 0, error);
}

unittest
{
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.string : indexOf;
    import std.uuid : randomUUID;

    const root = buildPath(tempDir(), "flint-port-spring-" ~ randomUUID().toString());
    Upstream pin;
    pin.project = "example";
    pin.version_ = "1";
    pin.sha256 = "1111";
    const tree = buildPath(root, pin.key);
    mkdirRecurse(tree);
    scope (exit)
        rmdirRecurse(root);
    SpringPortRequest request;
    request.cache = root;
    string error;
    assert(!sourcePath(root, request, pin, "../Source.java", error).length);
    assert(error.indexOf("relative") >= 0, error);
    assert(!sourcePath(root, request, pin, "Source.java", error).length);
    assert(error.indexOf("checksum stamp") >= 0, error);
    const stamp = buildPath(tree, ".flint-api-fetch");
    write(stamp, "2222\n");
    assert(!sourcePath(root, request, pin, "Source.java", error).length);
    assert(error.indexOf("checksum stamp") >= 0, error);
    write(stamp, "1111\n");
    assert(sourcePath(root, request, pin, "Source.java", error) == buildPath(tree, "Source.java"), error);
}

unittest
{
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.string : indexOf;
    import std.uuid : randomUUID;

    const root = buildPath(tempDir(), "flint-port-licence-" ~ randomUUID().toString());
    mkdirRecurse(buildPath(root, "api"));
    scope (exit)
        rmdirRecurse(root);
    mkdirRecurse(buildPath(root, "policy"));
    write(buildPath(root, "api", "upstreams.json"), `{"schema":"flint.api-upstreams/1","upstreams":[
        {"project":"clean","version":"1","url":"unused","format":"jar",
        "sha256":"1111111111111111111111111111111111111111111111111111111111111111"},
        {"project":"epl","version":"1","url":"unused","format":"jar",
        "sha256":"2222222222222222222222222222222222222222222222222222222222222222"}
    ]}`);
    write(buildPath(root, "policy", "upstream-licences.json"), `{"projects":[
        {"name":"clean","tag":"1","use":"clean-room","licence":"GPL-2.0"},
        {"name":"epl","tag":"1","use":"epl-module","licence":"EPL-2.0"}
    ]}`);
    SpringPortRequest request;
    request.project = "clean";
    request.tag = "1";
    request.module_ = "flint.example";
    request.type = "example.Hint";
    SpringPort output;
    string error;
    assert(!portSpring(root, request, output, error));
    assert(error.indexOf("clean-room") >= 0, error);
    request.project = "epl";
    assert(!portSpring(root, request, output, error));
    assert(error.indexOf("registered EPL-2.0 destination package") >= 0, error);
    assert(!output.source.length && !output.mapping.length);
}

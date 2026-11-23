/// `flint api`: the API manifests that prove Flint's Spring port complete (ADR-030, API manifests).
///
/// - `flint api fetch` downloads the pinned upstream source archives into the reference cache.
/// - `flint api extract` writes the manifest of an upstream Java source tree.
/// - `flint api coverage` classifies manifest elements against `api/mapping.json` and fails on unclassified ones.
/// - `flint api diff` lists the elements added, removed or changed between two manifests.
module flint_tool.commands.api;

import flint.serde : JsonIgnore, JsonName;
import flint_tool.diagnostics.report : Diagnostic, Report;
import flint_tool.engine.session : Session;

@safe:

/// What `flint api extract` was asked.
struct ExtractCommand
{
    /// Source tree.
    string source;
    /// Project.
    string project;
    /// Tag.
    string tag;
    /// Output path; default `api/upstream/<project>-<tag>.json`.
    string output;
    /// Extra excluded prefixes.
    string[] excludes;
}

/// `flint api extract`.
int commandApiExtract(ref Session session, const ref ExtractCommand command)
{
    import std.file : exists, isDir;
    import std.path : buildPath;
    import flint_tool.api.extract : ExtractRequest, extract;
    import flint_tool.api.manifest : renderManifest;
    import flint_tool.api.upstreams : findUpstream, loadUpstreams;
    import flint_tool.commands.output : finish;
    import flint_tool.support.files : writeIfChanged;

    Report report;
    ExtractReport payload;
    if (command.source.length == 0 || command.project.length == 0 || command.tag.length == 0)
    {
        report.error("FLINT-E0002", "flint api extract needs --source, --project and --version",
                "flint api extract --source DIR --project spring-framework --version v7.1.0");
        return finish(session, report, payload);
    }
    if (!exists(command.source) || !isDir(command.source))
    {
        report.error("FLINT-E1004", "no source tree at " ~ command.source, "flint api fetch " ~ command.project);
        return finish(session, report, payload);
    }
    ExtractRequest request;
    request.source = command.source;
    request.project = command.project;
    request.version_ = command.tag;
    string ignored;
    if (auto pinned = findUpstream(loadUpstreams(session.home.root, ignored), command.project, command.tag))
        request.excludes = pinned.exclude.dup;
    request.excludes ~= command.excludes;
    auto extraction = extract(request);
    foreach (ref problem; extraction.problems)
    {
        import flint_tool.diagnostics.report : Severity, at, diagnostic;

        report.add(at(diagnostic("FLINT-E1001", Severity.error,
                "cannot parse the Java declarations: " ~ problem.message,
                "report the construct; the file's types are missing from the manifest"),
                buildPath(command.source, problem.file), problem.line, 1));
    }
    payload.output = command.output.length ? command.output : buildPath("api", "upstream",
            command.project ~ "-" ~ command.tag ~ ".json");
    payload.project = command.project;
    payload.version_ = command.tag;
    payload.files = extraction.files;
    payload.excludes = request.excludes;
    foreach (ref counts; extraction.manifest.modules)
        payload.modules ~= ModuleRow(counts.name, counts.types, counts.methods, counts.constructors,
                counts.fields, counts.constants, counts.attributes, counts.components);
    payload.types = extraction.manifest.types.length;
    foreach (ref row; payload.modules)
        payload.methods += row.methods;
    writeIfChanged(payload.output, renderManifest(extraction.manifest));
    if (!session.json)
    {
        session.say(moduleTable(payload.modules));
        session.progress("Wrote", payload.output ~ " (" ~ count(payload.types) ~ " types, " ~ count(
                payload.methods) ~ " methods from " ~ count(payload.files) ~ " files)");
    }
    return finish(session, report, payload);
}

/// `flint api fetch [PROJECT...]`.
int commandApiFetch(ref Session session, const(string)[] projects, string cacheOverride)
{
    import std.process : environment;
    import flint_tool.api.upstreams : Upstream, fetchUpstream, loadUpstreams, referenceCache;
    import flint_tool.commands.output : finish;

    Report report;
    FetchReport payload;
    string error;
    auto upstreams = loadUpstreams(session.home.root, error);
    if (error.length)
    {
        report.error("FLINT-E1004", error, "restore api/upstreams.json in the Flint home");
        return finish(session, report, payload);
    }
    payload.cache = cacheOverride.length ? cacheOverride : referenceCache(session.home.root);
    const offline = environment.get("FLINT_OFFLINE", "") == "1" || environment.get("FLINT_PROXY", "") == "off";
    foreach (project; projects)
    {
        if (!known(upstreams, project))
            report.error("FLINT-E0001", "`" ~ project ~ "` is not pinned in api/upstreams.json",
                    "flint api fetch without arguments fetches every pinned project");
    }
    if (!report.ok)
        return finish(session, report, payload);
    foreach (ref upstream; upstreams)
    {
        if (projects.length && !listed(projects, upstream.project))
            continue;
        const fetched = fetchUpstream(upstream, payload.cache, offline);
        if (fetched.failure.length)
        {
            report.error("FLINT-E1005", fetched.failure, "check the network, or the pin in api/upstreams.json");
            continue;
        }
        payload.fetched ~= FetchRow(fetched.project, fetched.version_, fetched.directory,
                fetched.cached, upstream.licence);
        session.progress(fetched.cached ? "Cached" : "Fetched", upstream.key ~ " → " ~ fetched.directory);
    }
    return finish(session, report, payload);
}

/// `flint api coverage --manifest FILE... [--mapping FILE]`.
int commandApiCoverage(ref Session session, const(string)[] manifests, string mappingPath, size_t shown)
{
    import std.conv : to;
    import std.file : exists, readText;
    import std.path : buildPath;
    import flint_tool.api.coverage : Mapping, parseMapping, rulebookVersion;
    import flint_tool.commands.output : finish;
    import flint_tool.support.files : readIfPresent;

    Report report;
    CoverageReport payload;
    if (manifests.length == 0)
    {
        report.error("FLINT-E0002", "flint api coverage needs at least one --manifest",
                "flint api coverage --manifest api/upstream/spring-framework-v7.1.0.json");
        return finish(session, report, payload);
    }
    Mapping mapping;
    string error;
    if (!exists(mappingPath))
    {
        report.error("FLINT-E1004", "no mapping at " ~ mappingPath,
                "create it in the shape docs/spring/api-mapping.md describes");
        return finish(session, report, payload);
    }
    if (!parseMapping(readText(mappingPath), mapping, error))
    {
        report.error("FLINT-E1003", mappingPath ~ ": " ~ error, "fix the entry; see docs/spring/api-mapping.md");
        return finish(session, report, payload);
    }
    const current = rulebookVersion(readIfPresent(buildPath(session.home.root, "docs", "spring", "api-mapping.md")));
    if (current && mapping.rulebook != current)
    {
        report.error("FLINT-E1003", mappingPath ~ " classifies against rulebook " ~ to!string(
                mapping.rulebook) ~ ", but docs/spring/api-mapping.md is rulebook " ~ to!string(current),
                "re-check the elements citing the changed rules, then set \"rulebook\": " ~ to!string(current));
        return finish(session, report, payload);
    }
    payload.mapping = mappingPath;
    payload.rulebook = mapping.rulebook;
    classifyManifests(session, report, payload, mapping, manifests, shown);
    if (payload.unclassified)
        report.error("FLINT-E1002", to!string(payload.unclassified) ~ " API elements are unclassified",
                "classify each as ported, adapted or excluded in " ~ mappingPath);
    // Unclassified ids can number tens of thousands, past flint.serde's array limit: they are written directly.
    string ids = "{";
    foreach (index, ref row; payload.manifests)
        ids ~= (index ? "," : "") ~ jsonString(row.project ~ "@" ~ row.version_) ~ ":" ~ jsonStrings(row.unclassified);
    return finishWith(session, report, payload, "unclassified_ids", ids ~ "}");
}

private void classifyManifests(ref Session session, ref Report report, ref CoverageReport payload,
        const ref imported!"flint_tool.api.coverage".Mapping mapping, const(string)[] manifests, size_t shown)
{
    import flint_tool.api.coverage : Classifier, coverage;
    import flint_tool.api.manifest : Manifest, loadManifest;

    const classifier = Classifier(mapping);
    foreach (path; manifests)
    {
        Manifest manifest;
        string error;
        if (!loadManifest(path, manifest, error))
        {
            report.error("FLINT-E1004", error, "regenerate it with flint api extract");
            continue;
        }
        if (!mapping.covers(manifest.project, manifest.version_))
        {
            const upstream = manifest.project ~ "@" ~ manifest.version_;
            report.error("FLINT-E1003", payload.mapping ~ " does not cover " ~ upstream,
                    "add it to \"upstream\" once its elements are classified");
            continue;
        }
        auto result = coverage(manifest, classifier);
        CoverageManifest row;
        row.manifest = path;
        row.project = result.project;
        row.version_ = result.version_;
        row.summary = tallyRow(result.summary);
        foreach (ref tally; result.modules)
            row.modules ~= tallyRow(tally);
        row.unclassified = result.unclassified;
        payload.unclassified += result.unclassified.length;
        payload.manifests ~= row;
        if (!session.json)
            session.say(coverageTable(row, shown));
    }
}

/// `flint api diff OLD NEW`.
int commandApiDiff(ref Session session, string older, string newer)
{
    import std.conv : to;
    import flint_tool.api.diff : Change, diffManifests;
    import flint_tool.api.manifest : Manifest, loadManifest;
    import flint_tool.commands.output : finish;

    Report report;
    DiffReport payload;
    Manifest before;
    Manifest after;
    string error;
    if (older.length == 0 || newer.length == 0)
    {
        report.error("FLINT-E0002", "flint api diff needs two manifests",
                "flint api diff api/upstream/spring-boot-v4.1.0.json api/upstream/spring-boot-v4.2.0.json");
        return finish(session, report, payload);
    }
    if (!loadManifest(older, before, error) || !loadManifest(newer, after, error))
    {
        report.error("FLINT-E1004", error, "regenerate it with flint api extract");
        return finish(session, report, payload);
    }
    payload.older = before.project ~ " " ~ before.version_;
    payload.newer = after.project ~ " " ~ after.version_;
    string text;
    foreach (ref difference; diffManifests(before, after))
    {
        payload.differences ~= DiffRow(cast(string) difference.change, difference.kind,
                difference.id, difference.details);
        final switch (difference.change)
        {
        case Change.added:
            payload.added++;
            text ~= "+ " ~ difference.kind ~ " " ~ difference.id ~ "\n";
            break;
        case Change.removed:
            payload.removed++;
            text ~= "- " ~ difference.kind ~ " " ~ difference.id ~ "\n";
            break;
        case Change.changed:
            payload.changed++;
            text ~= "~ " ~ difference.kind ~ " " ~ difference.id ~ "\n";
            foreach (detail; difference.details)
                text ~= "    " ~ detail ~ "\n";
            break;
        }
    }
    if (!session.json)
        session.say(text ~ payload.older ~ " → " ~ payload.newer ~ ": " ~ to!string(
                payload.added) ~ " added, " ~ to!string(payload.removed) ~ " removed, " ~ to!string(
                payload.changed) ~ " changed");
    string rows = "[";
    foreach (index, ref row; payload.differences)
        rows ~= (index ? "," : "") ~ `{"change":` ~ jsonString(row.change) ~ `,"kind":` ~ jsonString(
                row.kind) ~ `,"id":` ~ jsonString(row.id) ~ `,"details":` ~ jsonStrings(row.details) ~ "}";
    return finishWith(session, report, payload, "differences", rows ~ "]");
}

// ---------------------------------------------------------------------------------------------------------------
// Reports

/// Element counts of one module, as reported.
struct ModuleRow
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
}

private struct ExtractReport
{
    string schema = "flint.api-extract/1";
    bool ok;
    int exit_code;
    Diagnostic[] diagnostics;
    string project;
    @JsonName("version") string version_;
    string output;
    size_t files;
    size_t types;
    size_t methods;
    string[] excludes;
    ModuleRow[] modules;
}

private struct FetchRow
{
    string project;
    @JsonName("version") string version_;
    string directory;
    bool cached;
    string licence;
}

private struct FetchReport
{
    string schema = "flint.api-fetch/1";
    bool ok;
    int exit_code;
    Diagnostic[] diagnostics;
    string cache;
    FetchRow[] fetched;
}

private struct TallyRow
{
    string name;
    size_t total;
    size_t ported;
    size_t adapted;
    size_t excluded;
    size_t unclassified;
    double classified_percent;
}

private struct CoverageManifest
{
    string manifest;
    string project;
    @JsonName("version") string version_;
    TallyRow summary;
    TallyRow[] modules;
    @JsonIgnore string[] unclassified;
}

private struct CoverageReport
{
    string schema = "flint.api-coverage/1";
    bool ok;
    int exit_code;
    Diagnostic[] diagnostics;
    string mapping;
    uint rulebook;
    size_t unclassified;
    CoverageManifest[] manifests;
}

private struct DiffRow
{
    string change;
    string kind;
    string id;
    string[] details;
}

private struct DiffReport
{
    string schema = "flint.api-diff/1";
    bool ok;
    int exit_code;
    Diagnostic[] diagnostics;
    string older;
    string newer;
    size_t added;
    size_t removed;
    size_t changed;
    @JsonIgnore DiffRow[] differences;
}

/// `finish`, with one more member whose JSON is written directly: arrays that may exceed flint.serde's limit.
private int finishWith(T)(ref Session session, ref Report report, ref T payload, string key, string json)
{
    import flint.serde.owned : serialize;
    import flint_tool.commands.output : finish;
    import flint_tool.sys.posix : writeError, writeOutput;

    if (!session.json)
        return finish(session, report, payload);
    payload.ok = report.ok;
    payload.exit_code = cast(int) report.exitCode;
    payload.diagnostics = report.items.dup;
    auto text = serialize(payload);
    if (!text.ok)
    {
        writeError("flint: internal error: cannot encode the " ~ payload.schema ~ " report: " ~ text.error.message
                ~ "\n");
        return 1;
    }
    writeOutput(text.value[0 .. $ - 1] ~ "," ~ jsonString(key) ~ ":" ~ json ~ "}\n");
    return payload.exit_code;
}

private string jsonString(string text)
{
    import std.json : JSONOptions, JSONValue;

    return JSONValue(text).toString(JSONOptions.doNotEscapeSlashes);
}

private string jsonStrings(const(string)[] values)
{
    string json = "[";
    foreach (index, value; values)
        json ~= (index ? "," : "") ~ jsonString(value);
    return json ~ "]";
}

private TallyRow tallyRow(const ref imported!"flint_tool.api.coverage".Tally tally)
{
    return TallyRow(tally.name, tally.total, tally.ported, tally.adapted, tally.excluded,
            tally.unclassified, tally.classifiedPercent);
}

private bool known(const(imported!"flint_tool.api.upstreams".Upstream)[] upstreams, string project)
{
    foreach (ref upstream; upstreams)
    {
        if (upstream.project == project)
            return true;
    }
    return false;
}

private bool listed(const(string)[] projects, string project)
{
    foreach (item; projects)
    {
        if (item == project)
            return true;
    }
    return false;
}

private string count(size_t value)
{
    import std.conv : to;

    return value.to!string;
}

/// The per-module table `flint api extract` prints.
string moduleTable(const(ModuleRow)[] rows)
{
    import std.format : format;

    string text = format("%-48s %7s %8s %6s %7s\n", "module", "types", "methods", "ctors", "fields");
    ModuleRow total;
    foreach (ref row; rows)
    {
        text ~= format("%-48s %7d %8d %6d %7d\n", row.name, row.types, row.methods, row.constructors, row.fields);
        total.types += row.types;
        total.methods += row.methods;
        total.constructors += row.constructors;
        total.fields += row.fields;
    }
    return text ~ format("%-48s %7d %8d %6d %7d", "total", total.types, total.methods,
            total.constructors, total.fields);
}

private string coverageTable(const ref CoverageManifest row, size_t shown)
{
    import std.format : format;

    string text = row.project ~ " " ~ row.version_ ~ " (" ~ row.manifest ~ ")\n";
    text ~= format("%-48s %8s %7s %7s %8s %8s %8s\n", "module", "elements", "ported", "adapted",
            "excluded", "unclass.", "classif.");
    TallyRow total = row.summary;
    total.name = "total";
    foreach (ref tally; row.modules ~ total)
        text ~= format("%-48s %8d %7d %7d %8d %8d %7.1f%%\n", tally.name, tally.total, tally.ported,
                tally.adapted, tally.excluded, tally.unclassified, tally.classified_percent);
    foreach (index, id; row.unclassified)
    {
        if (index == shown)
        {
            text ~= format("  … and %d more unclassified (--json lists them all)\n", row.unclassified.length - shown);
            break;
        }
        text ~= "  unclassified: " ~ id ~ "\n";
    }
    return text[0 .. $ - 1];
}

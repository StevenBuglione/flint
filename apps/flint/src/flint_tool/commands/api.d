/// `flint api`: the API manifests that prove Flint's Spring port complete (ADR-030, API manifests).
///
/// - `flint api fetch` downloads the pinned upstream source archives into the reference cache.
/// - `flint api extract` writes the manifest of an upstream Java source tree.
/// - `flint api coverage` classifies manifest elements against `api/mapping.json` and fails on unclassified ones.
/// - `flint api diff` lists the elements added, removed or changed between two manifests.
/// - `flint api checklist` writes per-module checklists of a porting slice, with statuses from the mapping.
/// - `flint api headers` checks the header of every file ported from an upstream against the licence matrix.
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
int commandApiFetch(ref Session session, const(string)[] projects, string cacheOverride, bool tests = false)
{
    import std.process : environment;
    import flint_tool.api.upstreams : Upstream, fetchUpstream, loadUpstreamTests, loadUpstreams, referenceCache;
    import flint_tool.commands.output : finish;

    Report report;
    FetchReport payload;
    string error;
    auto upstreams = tests ? loadUpstreamTests(session.home.root, error) : loadUpstreams(session.home.root, error);
    if (error.length)
    {
        report.error("FLINT-E1004", error, "restore the pins in the Flint home's api/ directory");
        return finish(session, report, payload);
    }
    payload.cache = cacheOverride.length ? cacheOverride : referenceCache(session.home.root);
    const offline = environment.get("FLINT_OFFLINE", "") == "1" || environment.get("FLINT_PROXY", "") == "off";
    foreach (project; projects)
    {
        if (!known(upstreams, project))
            report.error("FLINT-E0001", "`" ~ project ~ "` is not pinned in api/" ~ (tests
                    ? "upstream-tests.json" : "upstreams.json"),
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

/// What `flint api coverage` was asked.
struct CoverageCommand
{
    /// Manifests named on the command line.
    const(string)[] manifests;
    /// Mapping named on the command line.
    string mapping;
    /// Repo whose manifests and mapping to use.
    string repo;
    /// Unclassified ids to print per manifest.
    size_t shown;
    /// Require every element classified, ignoring the baseline.
    bool release;
    /// Lower the baseline to the current counts.
    bool updateBaseline;
    /// Baseline path; default `coverage-baseline.json` beside the mapping.
    string baseline;
    /// Slice files whose `complete` checklists must be complete; default `docs/spring/*/slice.json`.
    const(string)[] slices;
}

/// The manifests and mapping to classify: as named, or the repo's (api/upstreams.json `repo`).
bool coverageInputs(ref Session session, const ref CoverageCommand command, ref Report report,
        out string[] manifests, out string mappingPath)
{
    import std.file : exists;
    import std.path : buildPath;
    import flint_tool.api.upstreams : loadUpstreams;

    manifests = command.manifests.dup;
    mappingPath = command.mapping;
    const repoMapping = buildPath("api", command.repo, "mapping.json");
    if (mappingPath.length == 0)
        mappingPath = command.repo.length && exists(repoMapping) ? repoMapping : buildPath("api", "mapping.json");
    if (manifests.length == 0 && command.repo.length)
    {
        string error;
        foreach (ref upstream; loadUpstreams(session.home.root, error))
        {
            const path = buildPath(session.home.root, "api", "upstream", upstream.key ~ ".json");
            if (upstream.repo == command.repo && upstream.api && exists(path))
                manifests ~= path;
        }
        if (manifests.length == 0)
            report.error("FLINT-E1004",
                    "api/upstreams.json assigns no extracted manifest to the `" ~ command.repo ~ "` repo",
                    "flint api fetch, then flint api extract, for the repo's upstreams");
        return manifests.length != 0;
    }
    if (manifests.length == 0)
        report.error("FLINT-E0002", "flint api coverage needs --repo or at least one --manifest",
                "flint api coverage --repo framework");
    return manifests.length != 0;
}

/// `flint api coverage [--repo R] [--manifest FILE...] [--mapping FILE]`.
int commandApiCoverage(ref Session session, const ref CoverageCommand command)
{
    import std.conv : to;
    import std.file : exists, readText;
    import std.path : buildPath;
    import flint_tool.api.coverage : Classifier, Mapping, parseMapping, rulebookVersion;
    import flint_tool.commands.output : finish;
    import flint_tool.support.files : readIfPresent;

    Report report;
    CoverageReport payload;
    string[] manifests;
    string mappingPath;
    if (!coverageInputs(session, command, report, manifests, mappingPath))
        return finish(session, report, payload);
    const shown = command.shown;
    payload.repo = command.repo;
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
    const classifier = Classifier(mapping);
    Classified classified;
    classifyManifests(session, report, payload, mapping, classifier, manifests, shown, classified);
    applyBaseline(session, report, payload, command, mappingPath, classified);
    checkComplete(session, report, payload, command.slices, classified, classifier);
    // Unclassified ids can number tens of thousands, past flint.serde's array limit: they are written directly.
    string ids = "{";
    foreach (index, ref row; payload.manifests)
        ids ~= (index ? "," : "") ~ jsonString(row.project ~ "@" ~ row.version_) ~ ":" ~ jsonStrings(row.unclassified);
    return finishWith(session, report, payload, "unclassified_ids", ids ~ "}");
}

/// The manifests a coverage run classified, and their results.
private struct Classified
{
    imported!"flint_tool.api.manifest".Manifest[] manifests;
    imported!"flint_tool.api.coverage".ManifestCoverage[] results;
}

private void classifyManifests(ref Session session, ref Report report, ref CoverageReport payload,
        const ref imported!"flint_tool.api.coverage".Mapping mapping,
        const ref imported!"flint_tool.api.coverage".Classifier classifier,
        const(string)[] manifests, size_t shown, ref Classified classified)
{
    import flint_tool.api.coverage : coverage;
    import flint_tool.api.manifest : Manifest, loadManifest;

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
        classified.manifests ~= manifest;
        classified.results ~= result;
        if (!session.json)
            session.say(coverageTable(row, shown));
    }
}

/// The ratchet: with a baseline, fail on any module whose unclassified count rose; `--update-baseline` lowers it;
/// `--release`, or no baseline, requires every element classified.
private void applyBaseline(ref Session session, ref Report report, ref CoverageReport payload,
        const ref CoverageCommand command, string mappingPath, const ref Classified classified)
{
    import std.conv : to;
    import std.file : exists, readText;
    import std.path : buildPath, dirName;
    import flint_tool.api.baseline : Baseline, baselineOf, compare, lowered, parseBaseline, renderBaseline;
    import flint_tool.support.files : writeIfChanged;

    const path = command.baseline.length ? command.baseline : buildPath(dirName(mappingPath), "coverage-baseline.json");
    const strict = command.release || (!exists(path) && !command.updateBaseline);
    payload.mode = command.updateBaseline ? "update-baseline" : strict ? "release" : "ratchet";
    if (strict)
    {
        if (payload.unclassified)
            report.error("FLINT-E1002", to!string(payload.unclassified) ~ " API elements are unclassified",
                    "classify each as ported, adapted or excluded in " ~ mappingPath);
        return;
    }
    payload.baseline = path;
    Baseline recorded;
    string error;
    if (exists(path) && !parseBaseline(readText(path), recorded, error))
    {
        report.error("FLINT-E1004", path ~ ": " ~ error, "restore it from git");
        return;
    }
    const current = baselineOf(classified.results);
    if (command.updateBaseline)
    {
        string[] raised;
        const next = lowered(recorded, current, raised);
        foreach (message; raised)
            report.error("FLINT-E1007", message, "the baseline only goes down: classify the elements instead");
        const verb = exists(path) ? "Lowered" : "Recorded";
        if (raised.length == 0 && writeIfChanged(path, renderBaseline(next)))
            session.progress(verb, path ~ " at " ~ to!string(next.total) ~ " unclassified");
        return;
    }
    const ratchet = compare(recorded, current);
    payload.regressions = ratchet.regressions.dup;
    payload.improvements = ratchet.improvements.dup;
    foreach (message; ratchet.regressions)
        report.error("FLINT-E1007", message, "classify the new elements in " ~ mappingPath);
    if (ratchet.improvements.length)
    {
        const improved = to!string(ratchet.improvements.length);
        session.progress("Improved", improved ~ " modules; lower the baseline with --update-baseline");
    }
}

/// Every checklist a slice marks `complete` must have every element classified and none deferred.
private void checkComplete(ref Session session, ref Report report, ref CoverageReport payload,
        const(string)[] slicePaths, const ref Classified classified,
        const ref imported!"flint_tool.api.coverage".Classifier classifier)
{
    import std.conv : to;
    import std.file : exists, readText;
    import std.path : buildPath;
    import flint_tool.api.checklist : Slice, parseSlice, unfinished;
    import flint_tool.support.files : findFiles;

    string[] paths = slicePaths.dup;
    if (paths.length == 0)
        foreach (relative; findFiles(buildPath("docs", "spring"), "*/slice.json"))
            paths ~= buildPath("docs", "spring", relative);
    foreach (path; paths)
    {
        Slice slice;
        string error;
        if (!exists(path) || !parseSlice(readText(path), slice, error))
        {
            report.error("FLINT-E1004", path ~ ": " ~ (error.length ? error : "missing"), "fix the slice file");
            continue;
        }
        foreach (ref entry; slice.checklists)
        {
            if (!entry.complete)
                continue;
            foreach (ref manifest; classified.manifests)
            {
                if (manifest.project ~ "@" ~ manifest.version_ != entry.upstream)
                    continue;
                payload.complete ~= entry.name;
                const open = unfinished(entry, manifest, classifier);
                if (open.length)
                    report.error("FLINT-E1008", entry.name ~ " is marked complete in " ~ path ~ ", but " ~ to!string(
                            open.length) ~ " elements are not ported, adapted or excluded for good, "
                            ~ "first " ~ open[0], "finish them, or remove \"complete\" from the slice");
            }
        }
    }
}

/// `flint api checklist --slice FILE --output DIR`.
int commandApiChecklist(ref Session session, string slicePath, string outputDirectory)
{
    import std.file : exists, mkdirRecurse, readText;
    import std.path : buildPath;
    import flint_tool.api.checklist : IndexRow, Slice, parseSlice, renderIndex;
    import flint_tool.commands.output : finish;
    import flint_tool.support.files : writeIfChanged;

    Report report;
    ChecklistReport payload;
    Slice slice;
    string error;
    if (slicePath.length == 0 || outputDirectory.length == 0)
    {
        report.error("FLINT-E0002", "flint api checklist needs --slice and --output",
                "flint api checklist --slice docs/spring/phase1/slice.json --output docs/spring/phase1/checklists");
        return finish(session, report, payload);
    }
    if (!exists(slicePath) || !parseSlice(readText(slicePath), slice, error))
    {
        report.error("FLINT-E1004", slicePath ~ ": " ~ (error.length ? error : "missing"),
                "write a flint.api-slice/1 file; see docs/flint-cli.md");
        return finish(session, report, payload);
    }
    ChecklistSources sources;
    IndexRow[] rows;
    foreach (ref entry; slice.checklists)
    {
        IndexRow row;
        if (!renderOne(session, sources, slice, entry, outputDirectory, row, report))
            continue;
        rows ~= row;
        payload.checklists ~= ChecklistRow(entry.name, buildPath(outputDirectory,
                entry.name ~ ".md"), row.counts.types, row.counts.elements, row.counts.open);
    }
    if (report.ok)
    {
        mkdirRecurse(outputDirectory);
        writeIfChanged(buildPath(outputDirectory, "README.md"), renderIndex(slice.title, slicePath, rows));
        const index = buildPath(outputDirectory, "README.md");
        session.progress("Wrote", index ~ " and " ~ count(rows.length) ~ " checklists");
    }
    return finish(session, report, payload);
}

/// Manifests and mappings loaded once for all the checklists of a slice.
private struct ChecklistSources
{
    imported!"flint_tool.api.manifest".Manifest[string] manifests;
    imported!"flint_tool.api.coverage".Mapping[string] mappings;
    imported!"flint_tool.api.upstreams".Upstream[] upstreams;
    bool loaded;
}

private bool renderOne(ref Session session, ref ChecklistSources sources,
        const ref imported!"flint_tool.api.checklist".Slice slice,
        const ref imported!"flint_tool.api.checklist".SliceEntry entry, string outputDirectory,
        out imported!"flint_tool.api.checklist".IndexRow row, ref Report report)
{
    import std.file : exists, mkdirRecurse, readText;
    import std.path : buildPath;
    import flint_tool.api.checklist : renderChecklist;
    import flint_tool.api.coverage : Classifier, Mapping, parseMapping;
    import flint_tool.api.manifest : Manifest, loadManifest;
    import flint_tool.api.upstreams : loadUpstreams;
    import flint_tool.support.files : writeIfChanged;

    string error;
    if (!sources.loaded)
    {
        sources.upstreams = loadUpstreams(session.home.root, error);
        sources.loaded = true;
    }
    const(imported!"flint_tool.api.upstreams".Upstream)* pin;
    foreach (ref upstream; sources.upstreams)
    {
        if (upstream.project ~ "@" ~ upstream.version_ == entry.upstream)
            pin = &upstream;
    }
    if (pin is null)
    {
        report.error("FLINT-E1004", entry.name ~ ": `" ~ entry.upstream ~ "` is not pinned in api/upstreams.json",
                "name an upstream as project@version");
        return false;
    }
    const manifestPath = buildPath("api", "upstream", pin.key ~ ".json");
    if (entry.upstream !in sources.manifests)
    {
        Manifest manifest;
        if (!loadManifest(buildPath(session.home.root, manifestPath), manifest, error))
        {
            report.error("FLINT-E1004", error, "flint api extract the upstream first");
            return false;
        }
        sources.manifests[entry.upstream] = manifest;
    }
    const repoMapping = buildPath("api", pin.repo, "mapping.json");
    const mappingPath = exists(repoMapping) ? repoMapping : buildPath("api", "mapping.json");
    if (mappingPath !in sources.mappings)
    {
        Mapping mapping;
        if (exists(mappingPath) && !parseMapping(readText(mappingPath), mapping, error))
        {
            report.error("FLINT-E1003", mappingPath ~ ": " ~ error, "fix the entry; see docs/spring/api-mapping.md");
            return false;
        }
        sources.mappings[mappingPath] = mapping;
    }
    const classifier = Classifier(sources.mappings[mappingPath]);
    row.name = entry.name;
    row.upstream = entry.upstream;
    row.module_ = entry.module_;
    const text = renderChecklist(entry, slice.title, sources.manifests[entry.upstream],
            manifestPath, classifier, mappingPath, row.counts);
    if (row.counts.types == 0)
    {
        report.error("FLINT-E1004",
                entry.name ~ ": no type of " ~ entry.upstream ~ " module `" ~ entry.module_ ~ "` matches the slice",
                "check the module and package patterns");
        return false;
    }
    mkdirRecurse(outputDirectory);
    writeIfChanged(buildPath(outputDirectory, entry.name ~ ".md"), text);
    return true;
}

/// `flint api headers [PATH...]`.
int commandApiHeaders(ref Session session, const(string)[] paths)
{
    import std.file : exists, isDir, readText;
    import std.path : buildPath;
    import flint_tool.api.headers : LicenceEntry, checkHeader, packageLicence, parseLicenceMatrix;
    import flint_tool.api.upstreams : loadUpstreams;
    import flint_tool.commands.output : finish;
    import flint_tool.diagnostics.report : Severity, at, diagnostic;
    import flint_tool.support.files : dSources;

    Report report;
    HeadersReport payload;
    string error;
    const upstreams = loadUpstreams(session.home.root, error);
    LicenceEntry[] matrix;
    const matrixPath = buildPath(session.home.root, "policy", "upstream-licences.json");
    if (error.length || !exists(matrixPath) || !parseLicenceMatrix(readText(matrixPath), matrix, error))
    {
        report.error("FLINT-E1004", error.length ? error : matrixPath ~ " is missing",
                "restore api/upstreams.json and policy/upstream-licences.json in the Flint home");
        return finish(session, report, payload);
    }
    foreach (root; paths.length ? paths : ["."])
    {
        if (!exists(root))
        {
            report.error("FLINT-E1004", "no such path: " ~ root, "name source directories or D files");
            continue;
        }
        const files = isDir(root) ? dSources(root, true) : [""];
        foreach (relative; files)
        {
            const file = relative.length ? buildPath(root, relative) : root;
            const source = readText(file);
            const problems = checkHeader(file, source, upstreams, matrix, packageLicence(file, root));
            payload.files++;
            if (hasMarker(source))
                payload.ported++;
            foreach (ref problem; problems)
                report.add(at(diagnostic("FLINT-E1006", Severity.error, problem.message,
                        "write the header ADR-030 section 7 requires; see docs/flint-cli.md"),
                        problem.file, problem.line, 1));
        }
    }
    payload.problems = report.items.length;
    session.progress("Checked", count(payload.files) ~ " D files, " ~ count(payload.ported) ~ " ported");
    return finish(session, report, payload);
}

private bool hasMarker(string source)
{
    import flint_tool.api.headers : headerOf;

    size_t line;
    headerOf(source, line);
    return line != 0;
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
    string repo;
    string mode;
    string baseline;
    uint rulebook;
    size_t unclassified;
    string[] regressions;
    string[] improvements;
    string[] complete;
    CoverageManifest[] manifests;
}

private struct ChecklistRow
{
    string name;
    string file;
    size_t types;
    size_t elements;
    size_t open;
}

private struct ChecklistReport
{
    string schema = "flint.api-checklist/1";
    bool ok;
    int exit_code;
    Diagnostic[] diagnostics;
    ChecklistRow[] checklists;
}

private struct HeadersReport
{
    string schema = "flint.api-headers/1";
    bool ok;
    int exit_code;
    Diagnostic[] diagnostics;
    size_t files;
    size_t ported;
    size_t problems;
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

/// Flint AOT's build step (docs/spring/aot-contract.md section 1): interface keys, the extraction cache, the
/// analysis and the generated files.
///
/// The edit loop's cost is lexing the modules and comparing keys. Only a changed interface runs the extraction
/// compile, and only then are the plan and the generated files recomputed; files whose text is unchanged are not
/// rewritten, so DUB recompiles nothing it need not.
module flint_tool.engine.aot.driver;

import flint_tool.engine.aot.plan : Diagnostic;

@safe:

/// Bumped whenever the generator's output for an unchanged model may change.
enum generatorVersion = "1";

/// Where generated modules go, relative to the project root.
enum aotDirectory = ".flint/generated/aot";
/// Where the extraction compile's root and describer go.
enum extractDirectory = ".flint/generated/aot-extract";
/// The cache: `state.json` holds the keys, `models/<module>.json` each module's model and `annotations.json` the
/// annotation types the models reach.
enum cacheDirectory = ".flint/cache/aot";
/// Where a package lists its auto-configuration classes, one per line, as Boot's
/// `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` does.
enum autoConfigurationImports = "META-INF/flint/flint.boot.autoconfigure.AutoConfiguration.imports";

/// One Flint AOT run.
struct AotRequest
{
    /// Project root (absolute).
    string root;
    /// The compiler that runs the extraction compile.
    string compiler;
    /// Import paths (`-I...`) of the closure, excluding `src/`.
    string[] importPaths;
    /// Semantic flags (`-preview=dip1000`, `-version=...`).
    string[] flags;
    /// Package directories whose auto-configuration imports file to read.
    string[] packageDirectories;
    /// Compiler identity, platform version and anything else that invalidates every key.
    string environmentKey;
}

/// What it did.
struct AotOutcome
{
    /// Whether the project has a `@FlintBootApplication`, so AOT ran.
    bool active;
    /// Whether it succeeded (no extraction failure, no error diagnostic).
    bool ok;
    /// The application class.
    string application;
    /// Modules considered, extracted this run, and generated files written.
    size_t modules;
    /// ditto
    size_t extracted;
    /// ditto
    size_t written;
    /// Generated modules in the current output.
    size_t generated;
    /// Timings in milliseconds: the extraction compile(s) and the whole step.
    long extractMilliseconds;
    /// ditto
    long totalMilliseconds;
    /// Generator diagnostics.
    Diagnostic[] diagnostics;
    /// The extraction compile's errors (FLINT-E1100).
    string extractionErrors;
    /// Definitions removed at build time.
    string[] removed;
}

private struct SourceModule
{
    string name;
    string path;
    bool packageModule;
    string hash;
    string[] imports;
    bool user;
    /// The interface mentions `FlintBootApplication`, which turns AOT on.
    bool marker;
}

private struct State
{
    string environmentKey;
    /// Extraction key of each module whose model is cached.
    string[string] keys;
    bool[string] present;
    string outputKey;
}

/// Run Flint AOT for a project.
AotOutcome runAot(const ref AotRequest request)
{
    import core.time : MonoTime;
    import std.file : exists, rmdirRecurse;
    import std.path : buildPath;

    const started = MonoTime.currTime;
    AotOutcome outcome;
    SourceModule[] sources = userModules(request.root);
    bool any;
    foreach (ref source; sources)
        any = any || source.marker;
    if (!any)
    {
        const generated = buildPath(request.root, aotDirectory);
        if (exists(generated))
            rmdirRecurse(generated);
        outcome.ok = true;
        return outcome;
    }
    outcome.active = true;
    const autoConfigurations = readAutoConfigurations(request.packageDirectories);
    sources ~= autoConfigurationModules(autoConfigurations, request.importPaths);
    outcome.modules = sources.length;
    const cache = buildPath(request.root, cacheDirectory);
    State state = loadState(cache, request.environmentKey);
    const keys = extractionKeys(sources, request.environmentKey);
    string[] stale = staleModules(sources, keys, state, cache);
    if (stale.length && !extractInto(request, stale, null, keys, state, outcome))
        return finish(outcome, started);
    const outputKey = outputKeyOf(sources, state);
    if (stale.length == 0 && state.outputKey == outputKey && exists(buildPath(request.root,
            aotDirectory, "flint_aot_registry.d")))
    {
        outcome.ok = true;
        return finish(outcome, started);
    }
    if (!generate(request, sources, autoConfigurations, keys, state, outcome))
    {
        saveState(cache, state);
        return finish(outcome, started);
    }
    state.outputKey = outputKey;
    saveState(cache, state);
    outcome.ok = true;
    return finish(outcome, started);
}

private AotOutcome finish(ref AotOutcome outcome, imported!"core.time".MonoTime started)
{
    import core.time : MonoTime;

    outcome.totalMilliseconds = (MonoTime.currTime - started).total!"msecs";
    return outcome;
}

private SourceModule[] userModules(string root)
{
    import std.file : readText;
    import std.path : baseName, buildPath;
    import std.string : indexOf;
    import flint_tool.engine.aot.iface : ModuleInterface, readInterface;
    import flint_tool.support.files : dSources;

    SourceModule[] result;
    foreach (relative; dSources(root))
    {
        if (relative.length < 4 || relative[0 .. 4] != "src/")
            continue;
        const path = buildPath(root, relative);
        ModuleInterface found;
        const text = readText(path);
        if (!readInterface(text, found) || found.name.length == 0)
            continue;
        result ~= SourceModule(found.name, path, baseName(relative) == "package.d", found.hash,
                found.imports, true, found.text.indexOf("FlintBootApplication") >= 0
                || found.text.indexOf("FlintApplication") >= 0);
    }
    return result;
}

/// Every auto-configuration class the closure's packages list, in order, without duplicates.
string[] readAutoConfigurations(scope const string[] directories)
{
    import std.algorithm.iteration : splitter;
    import std.algorithm.searching : canFind;
    import std.file : exists, readText;
    import std.path : buildPath;
    import std.string : strip;

    string[] result;
    foreach (directory; directories)
    {
        const path = buildPath(directory, autoConfigurationImports);
        if (!exists(path))
            continue;
        foreach (line; readText(path).splitter('\n'))
        {
            const name = line.strip;
            if (name.length && name[0] != '#' && !result.canFind(name))
                result ~= name;
        }
    }
    return result;
}

private SourceModule[] autoConfigurationModules(scope const string[] classes, scope const string[] importPaths)
{
    import std.algorithm.searching : canFind;
    import std.array : replace;
    import std.file : exists, readText;
    import std.path : buildPath;
    import flint_tool.engine.aot.iface : ModuleInterface, readInterface;
    import flint_tool.engine.aot.names : packageOf;

    SourceModule[] result;
    string[] seen;
    foreach (name; classes)
    {
        const moduleName = packageOf(name);
        if (moduleName.length == 0 || seen.canFind(moduleName))
            continue;
        seen ~= moduleName;
        foreach (flag; importPaths)
        {
            const directory = flag.length > 2 && flag[0 .. 2] == "-I" ? flag[2 .. $] : flag;
            const base = buildPath(directory, moduleName.replace(".", "/"));
            foreach (candidate; [base ~ ".d", buildPath(base, "package.d")])
            {
                if (!exists(candidate))
                    continue;
                ModuleInterface found;
                if (readInterface(readText(candidate), found))
                    result ~= SourceModule(moduleName, candidate,
                            candidate[$ - 9 .. $] == "package.d", found.hash, found.imports, false);
                break;
            }
        }
    }
    return result;
}

/// The extraction key of each module: its interface, the interfaces of the extracted modules it imports
/// (transitively), and the environment.
private string[string] extractionKeys(scope const SourceModule[] sources, string environment)
{
    import std.algorithm.sorting : sort;
    import flint_tool.support.files : sha256Hex;

    string[string] hashes;
    string[][string] importsOf;
    foreach (ref item; sources)
    {
        hashes[item.name] = item.hash;
        importsOf[item.name] = item.imports.dup;
    }
    string[string] keys;
    foreach (ref source; sources)
    {
        bool[string] reached;
        string[] pending = source.imports.dup;
        while (pending.length)
        {
            const next = pending[$ - 1];
            pending = pending[0 .. $ - 1];
            if (next in reached || next !in hashes)
                continue;
            reached[next] = true;
            pending ~= importsOf[next];
        }
        string[] parts = reached.keys;
        sort(parts);
        string text = generatorVersion ~ "\n" ~ environment ~ "\n" ~ source.hash;
        foreach (name; parts)
            text ~= "\n" ~ name ~ "=" ~ hashes[name];
        keys[source.name] = sha256Hex(cast(const(ubyte)[]) text);
    }
    return keys;
}

private string modelPath(string cache, string name)
{
    import std.path : buildPath;

    return buildPath(cache, "models", name ~ ".json");
}

private string[] staleModules(scope const SourceModule[] sources, const string[string] keys, ref State state,
        string cache)
{
    import std.file : exists;

    string[] stale;
    foreach (ref source; sources)
    {
        const cached = source.name in state.keys;
        if (cached is null || *cached != keys[source.name] || !exists(modelPath(cache, source.name)))
            stale ~= source.name;
    }
    return stale;
}

/// A key over every module's extraction key: the generated output can only change when this does.
private string outputKeyOf(scope const SourceModule[] sources, ref State state)
{
    import std.algorithm.sorting : sort;
    import flint_tool.support.files : sha256Hex;

    string[] parts;
    foreach (ref source; sources)
    {
        if (auto cached = source.name in state.keys)
            parts ~= source.name ~ "=" ~ *cached;
    }
    foreach (name, answer; state.present)
        parts ~= "?" ~ name ~ (answer ? "=1" : "=0");
    sort(parts);
    string text = generatorVersion;
    foreach (part; parts)
        text ~= "\n" ~ part;
    return sha256Hex(cast(const(ubyte)[]) text);
}

private bool extractInto(const ref AotRequest request, scope const string[] modules,
        scope const string[] classes, const string[string] keys, ref State state, ref AotOutcome outcome)
{
    import std.file : mkdirRecurse, write;
    import std.path : buildPath;
    import flint_tool.engine.aot.extract : ExtractionRequest, ExtractionResult, extract;

    ExtractionRequest extraction;
    extraction.compiler = request.compiler;
    extraction.flags = request.flags.dup ~ request.importPaths.dup ~ [
        "-I" ~ buildPath(request.root, "src")
    ];
    extraction.modules = modules.dup;
    extraction.classes = classes.dup;
    extraction.directory = buildPath(request.root, extractDirectory);
    extraction.workingDirectory = request.root;
    auto result = extract(extraction);
    outcome.extractMilliseconds += result.milliseconds;
    outcome.extracted += result.models.length;
    if (!result.ok)
    {
        outcome.extractionErrors = result.errors;
        return false;
    }
    const cache = buildPath(request.root, cacheDirectory);
    mkdirRecurse(buildPath(cache, "models"));
    foreach (index, ref model; result.models)
    {
        write(modelPath(cache, model.name), result.documents[index]);
        state.keys[model.name] = keys.get(model.name, null);
    }
    if (result.annotationDocuments.length)
    {
        auto annotations = loadAnnotations(cache);
        foreach (index, ref type; result.annotationTypes)
            annotations[type.name] = result.annotationDocuments[index];
        saveAnnotations(cache, annotations);
    }
    foreach (name, answer; result.present)
        state.present[name] = answer;
    return true;
}

private bool generate(const ref AotRequest request, scope const SourceModule[] sources,
        scope const string[] autoConfigurations, const string[string] keys, ref State state, ref AotOutcome outcome)
{
    import std.file : readText;
    import std.path : buildPath;
    import flint_tool.engine.aot.model : AnnotationType, Model, ModuleModel, parseAnnotationType, parseModule;
    import flint_tool.engine.aot.plan : AnalysisInput, Plan, analyze;

    const cache = buildPath(request.root, cacheDirectory);
    auto model = new Model;
    foreach (name, document; loadAnnotations(cache))
    {
        AnnotationType type;
        string error;
        if (parseAnnotationType(document, type, error))
            model.annotationTypes[name] = type;
    }
    AnalysisInput input;
    input.root = request.root;
    input.autoConfigurations = autoConfigurations.dup;
    foreach (ref source; sources)
    {
        ModuleModel item;
        string error;
        if (!parseModule(readText(modelPath(cache, source.name)), item, error))
            continue;
        model.add(item);
        if (source.user)
            input.userModules ~= source.name;
    }
    model.present = state.present.dup;
    Plan plan = analyze(model, input);
    if (plan.unknownClasses.length)
    {
        if (!extractInto(request, null, plan.unknownClasses, keys, state, outcome))
            return false;
        model.present = state.present.dup;
        plan = analyze(model, input);
    }
    outcome.application = plan.application;
    outcome.diagnostics = plan.diagnostics;
    outcome.removed = plan.removed;
    if (plan.failed)
        return false;
    writeOutput(request.root, plan, sources, outcome);
    return true;
}

private void writeOutput(string root, const ref imported!"flint_tool.engine.aot.plan".Plan plan,
        scope const SourceModule[] sources, ref AotOutcome outcome)
{
    import std.algorithm.searching : canFind;
    import std.algorithm.sorting : sort;
    import std.file : SpanMode, dirEntries, exists, isFile, mkdirRecurse, remove;
    import std.path : buildPath, dirName;
    import flint_tool.engine.aot.emit : generatedPath, renderModule, renderRegistry;
    import flint_tool.support.files : writeIfChanged;

    const directory = buildPath(root, aotDirectory);
    mkdirRecurse(directory);
    string[] written;
    string[] modules;
    uint[string] firstRank;
    foreach (ref item; plan.modules)
    {
        if (item.empty)
            continue;
        bool packageModule;
        foreach (ref source; sources)
            packageModule = packageModule || (source.name == item.name && source.packageModule);
        const path = buildPath(directory, generatedPath(item.name, packageModule));
        mkdirRecurse(dirName(path));
        if (writeIfChanged(path, renderModule(item)))
            ++outcome.written;
        written ~= path;
        modules ~= item.name;
        firstRank[item.name] = item.beans.length ? item.beans[0].rank : uint.max;
    }
    // The registry calls the modules in definition order; the runtime also sorts definitions by rank.
    sort!((a, b) => firstRank[a] < firstRank[b] || (firstRank[a] == firstRank[b] && a < b))(modules);
    const registry = buildPath(directory, "flint_aot_registry.d");
    if (writeIfChanged(registry, renderRegistry(plan, modules)))
        ++outcome.written;
    written ~= registry;
    outcome.generated = modules.length;
    foreach (entry; dirEntries(directory, "*.d", SpanMode.depth))
    {
        if (isFile(entry.name) && !written.canFind(entry.name))
            remove(entry.name);
    }
}

private State loadState(string cache, string environment)
{
    import std.file : exists, readText;
    import std.json : JSONException, JSONType, parseJSON;
    import std.path : buildPath;

    State state;
    state.environmentKey = environment;
    const path = buildPath(cache, "state.json");
    if (!exists(path))
        return state;
    try
    {
        const root = parseJSON(readText(path));
        if (root.type != JSONType.object || "environment" !in root.objectNoRef)
            return state;
        if (root["environment"].str != environment)
            return state;
        foreach (name, value; root["keys"].objectNoRef)
            state.keys[name] = value.str;
        foreach (name, value; root["present"].objectNoRef)
            state.present[name] = value.type == JSONType.true_;
        state.outputKey = root["output"].str;
    }
    catch (JSONException)
        return State(environment);
    return state;
}

private void saveState(string cache, const ref State state)
{
    import std.file : mkdirRecurse, write;
    import std.json : JSONValue;
    import std.path : buildPath;

    JSONValue[string] keys;
    foreach (name, key; state.keys)
        keys[name] = JSONValue(key);
    JSONValue[string] present;
    foreach (name, answer; state.present)
        present[name] = JSONValue(answer);
    JSONValue root = JSONValue([
        "schema": JSONValue("flint.aot.state/2"),
        "environment": JSONValue(state.environmentKey),
        "output": JSONValue(state.outputKey),
        "keys": JSONValue(keys),
        "present": JSONValue(present)
    ]);
    mkdirRecurse(cache);
    write(buildPath(cache, "state.json"), root.toString);
}

/// Annotation types by name, as their JSON documents.
private string[string] loadAnnotations(string cache)
{
    import std.file : exists, readText;
    import std.json : JSONException, JSONType, parseJSON;
    import std.path : buildPath;

    string[string] result;
    const path = buildPath(cache, "annotations.json");
    if (!exists(path))
        return result;
    try
    {
        const root = parseJSON(readText(path));
        if (root.type != JSONType.object)
            return result;
        foreach (name, value; root.objectNoRef)
        {
            if (value.type == JSONType.string)
                result[name] = value.str;
        }
    }
    catch (JSONException)
        return null;
    return result;
}

private void saveAnnotations(string cache, const string[string] annotations)
{
    import std.file : mkdirRecurse, write;
    import std.json : JSONValue;
    import std.path : buildPath;

    JSONValue[string] values;
    foreach (name, document; annotations)
        values[name] = JSONValue(document);
    mkdirRecurse(cache);
    write(buildPath(cache, "annotations.json"), JSONValue(values).toString);
}

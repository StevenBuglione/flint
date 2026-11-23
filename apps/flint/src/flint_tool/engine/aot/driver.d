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
/// It also carries the tool's build time: DUB recompiles flint_tool as a whole, so every rebuilt generator
/// re-extracts and regenerates once, and an edited generator never leaves stale output behind.
enum generatorVersion = "1 " ~ __TIMESTAMP__;

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
    /// A directory shared by projects (`<FLINT_CACHE>/aot`), or empty. The models of modules outside `src/` (Boot's
    /// auto-configurations, imported configurations) and class-presence answers are kept there by extraction key,
    /// so a cold build of any project with the same closure reuses them.
    string sharedCache;
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
    /// Models taken from the shared cache this run.
    size_t reused;
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
    /// Modules extracted because an `@Import` names their classes (security configurations).
    string[] importedModules;
    /// SHA-256 of each cached model and of the annotation types: the output key hashes these, so an extraction
    /// that reproduces the same models regenerates nothing (early cutoff).
    string[string] models;
    /// ditto
    string annotations;
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
    addModules(state.importedModules, request.importPaths, sources);
    auto keys = extractionKeys(sources, request.environmentKey);
    string[] stale = staleModules(sources, keys, state, cache);
    if (stale.length && !extractInto(request, sources, stale, null, keys, state, outcome))
        return finish(outcome, started);
    if (stale.length && !extractImports(request, cache, sources, keys, state, outcome))
        return finish(outcome, started);
    outcome.ok = produceOutput(request, sources, autoConfigurations, keys, stale.length > 0, state, outcome);
    if (!outcome.ok)
        saveState(cache, state);
    return finish(outcome, started);
}

/// The generated output for the current models: kept when its key is unchanged, restored from the shared cache
/// on a cached cold build, else generated (and stored there). False when generation failed.
private bool produceOutput(const ref AotRequest request, scope const SourceModule[] sources,
        scope const string[] autoConfigurations, const string[string] keys, bool extracted,
        ref State state, ref AotOutcome outcome)
{
    import std.file : exists;
    import std.path : buildPath;

    const cache = buildPath(request.root, cacheDirectory);
    const outputKey = outputKeyOf(sources, state, request.environmentKey, autoConfigurations);
    if (state.outputKey == outputKey && exists(buildPath(request.root, aotDirectory, "flint_aot_registry.d")))
    {
        // Nothing to regenerate, also when the re-extracted models came out the same.
        if (extracted)
            saveState(cache, state);
        return true;
    }
    // A cached cold build: the same generated output for these models and this project was generated before.
    if (request.sharedCache.length && restoreOutput(request, outputKey, outcome))
    {
        state.outputKey = outputKey;
        saveState(cache, state);
        return true;
    }
    if (!generate(request, sources, autoConfigurations, keys, state, outcome))
        return false;
    if (request.sharedCache.length)
        storeOutput(request, outputKey, outcome);
    // Generation may have answered presence probes, which the key covers.
    state.outputKey = outputKeyOf(sources, state, request.environmentKey, autoConfigurations);
    saveState(cache, state);
    return true;
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
    ModuleInterface[] interfaces;
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
        interfaces ~= found;
    }
    typeKeys(interfaces, result);
    return result;
}

/// Key each project module on its interface text without the constants, variables and functions nothing else in
/// the project names (`typeKeyText`): adding such a declaration, the build benchmark's incremental edit, neither
/// re-extracts nor regenerates anything.
private void typeKeys(const imported!"flint_tool.engine.aot.iface".ModuleInterface[] interfaces, SourceModule[] sources)
{
    import flint_tool.engine.aot.iface : countOccurrences, typeKeyText;
    import flint_tool.support.files : sha256Hex;

    string[] names;
    foreach (ref item; interfaces)
    {
        foreach (ref value; item.values)
            names ~= value.name;
    }
    if (names.length == 0)
        return;
    size_t[string] occurrences;
    foreach (ref item; interfaces)
        countOccurrences(item.text, names, occurrences);
    foreach (index, ref item; interfaces)
        sources[index].hash = sha256Hex(cast(const(ubyte)[]) typeKeyText(item, occurrences));
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
    import std.algorithm.searching : canFind, startsWith;
    import flint_tool.engine.aot.names : packageOf;

    SourceModule[] result;
    string[] seen;
    void add(string moduleName)
    {
        if (moduleName.length == 0 || seen.canFind(moduleName))
            return;
        seen ~= moduleName;
        SourceModule found;
        if (findModule(moduleName, importPaths, found))
            result ~= found;
    }

    foreach (name; classes)
        add(packageOf(name));
    // The Boot modules the auto-configurations import declare the types their bean methods return and the
    // @ConfigurationProperties classes they enable: the plan reads those types' supertypes and properties.
    const configurationModules = result.length;
    foreach (index; 0 .. configurationModules)
    {
        foreach (imported; result[index].imports)
        {
            if (imported.startsWith("flint.boot."))
                add(imported);
        }
    }
    return result;
}

private bool findModule(string moduleName, scope const string[] importPaths, out SourceModule module_)
{
    import std.array : replace;
    import std.file : exists, readText;
    import std.path : buildPath;
    import flint_tool.engine.aot.iface : ModuleInterface, readInterface;

    foreach (flag; importPaths)
    {
        const directory = flag.length > 2 && flag[0 .. 2] == "-I" ? flag[2 .. $] : flag;
        const base = buildPath(directory, moduleName.replace(".", "/"));
        foreach (candidate; [base ~ ".d", buildPath(base, "package.d")])
        {
            if (!exists(candidate))
                continue;
            ModuleInterface found;
            if (!readInterface(readText(candidate), found))
                return false;
            module_ = SourceModule(moduleName, candidate, candidate[$ - 9 .. $] == "package.d",
                    found.hash, found.imports, false);
            return true;
        }
    }
    return false;
}

/// Add the modules `names` that are not sources yet, found on the import paths; returns the ones added.
private string[] addModules(scope const string[] names, scope const string[] importPaths, ref SourceModule[] sources)
{
    string[] added;
    foreach (name; names)
    {
        bool known;
        foreach (ref source; sources)
            known = known || source.name == name;
        SourceModule found;
        if (!known && findModule(name, importPaths, found))
        {
            sources ~= found;
            added ~= name;
        }
    }
    return added;
}

/// Extract the modules whose classes an `@Import` names (directly or through meta-annotations such as
/// `@EnableMethodSecurity`), transitively, since imported configurations may import further ones.
private bool extractImports(const ref AotRequest request, string cache, ref SourceModule[] sources,
        ref string[string] keys, ref State state, ref AotOutcome outcome)
{
    foreach (round; 0 .. 8)
    {
        const added = addModules(importTargets(cache, sources), request.importPaths, sources);
        if (added.length == 0)
            return true;
        state.importedModules ~= added;
        keys = extractionKeys(sources, request.environmentKey);
        if (!extractInto(request, sources, added, null, keys, state, outcome))
            return false;
    }
    return true;
}

/// Modules declaring the classes that the cached models' `@Import`s name.
private string[] importTargets(string cache, scope const SourceModule[] sources)
{
    import std.algorithm.searching : canFind;
    import std.file : exists, readText;
    import flint_tool.engine.aot.model : AnnotationType, ModuleModel, parseAnnotationType, parseModule;
    import flint_tool.engine.aot.names : packageOf;
    import flint_tool.engine.aot.plan : importedClasses;

    AnnotationType[string] types;
    foreach (name, document; loadAnnotations(cache))
    {
        AnnotationType type;
        string error;
        if (parseAnnotationType(document, type, error))
            types[name] = type;
    }
    string[] modules;
    foreach (ref source; sources)
    {
        const path = modelPath(cache, source.name);
        ModuleModel model;
        string error;
        if (!exists(path) || !parseModule(readText(path), model, error))
            continue;
        foreach (ref decl; model.types)
        {
            foreach (name; importedClasses(decl.annotations, types))
            {
                const moduleName = packageOf(name);
                if (moduleName.length && !modules.canFind(moduleName))
                    modules ~= moduleName;
            }
        }
    }
    return modules;
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
private string outputKeyOf(scope const SourceModule[] sources, ref State state, string environment,
        scope const string[] autoConfigurations)
{
    import std.algorithm.sorting : sort;
    import std.array : join;
    import flint_tool.support.files : sha256Hex;

    // The generated code is a function of the models (by content), the annotation types, the presence answers,
    // which modules are the project's, the auto-configuration order and the environment.
    string[] parts;
    foreach (ref source; sources)
    {
        const model = source.name in state.models;
        const cached = source.name in state.keys;
        if (model !is null || cached !is null)
            parts ~= source.name ~ (source.user ? "+" : "-") ~ (source.packageModule
                    ? "p" : "m") ~ "=" ~ (model !is null ? *model : "key " ~ *cached);
    }
    foreach (name, answer; state.present)
        parts ~= "?" ~ name ~ (answer ? "=1" : "=0");
    sort(parts);
    string text = generatorVersion ~ "\n" ~ environment ~ "\n" ~ state.annotations ~ "\n" ~ autoConfigurations.join(
            ",");
    foreach (part; parts)
        text ~= "\n" ~ part;
    return sha256Hex(cast(const(ubyte)[]) text);
}

private bool extractInto(const ref AotRequest request, scope const SourceModule[] sources,
        scope const string[] requested, scope const string[] probes, const string[string] keys,
        ref State state, ref AotOutcome outcome)
{
    import std.file : mkdirRecurse, write;
    import std.path : buildPath;
    import flint_tool.engine.aot.extract : ExtractionRequest, ExtractionResult, extract;
    import flint_tool.support.files : sha256Hex;

    const cache = buildPath(request.root, cacheDirectory);
    // Shared-cache keys: a platform module's extraction key; a project module's with the project root too, since
    // its model records absolute source paths. A cached cold build (a clean .flint) then extracts nothing.
    string[string] shareable;
    foreach (ref source; sources)
    {
        if (request.sharedCache.length && source.name in keys)
        {
            const key = keys[source.name];
            shareable[source.name] = source.user ? sharedProjectKey(key, request.root) : key;
        }
    }
    string[] modules = reuseShared(request.sharedCache, requested, shareable, keys, cache, state, outcome);
    string[] classes = request.sharedCache.length ? sharedPresence(request, probes, state) : probes.dup;
    if (modules.length == 0 && classes.length == 0)
        return true;
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
    mkdirRecurse(buildPath(cache, "models"));
    string annotationSet;
    foreach (index, ref model; result.models)
    {
        write(modelPath(cache, model.name), result.documents[index]);
        state.models[model.name] = sha256Hex(cast(const(ubyte)[]) result.documents[index]);
        state.keys[model.name] = keys.get(model.name, null);
        if (const sharedKey = model.name in shareable)
        {
            if (annotationSet.length == 0)
                annotationSet = storeAnnotationSet(request.sharedCache, result);
            storeShared(request.sharedCache, *sharedKey, result.documents[index], annotationSet);
        }
    }
    if (request.sharedCache.length && result.present.length)
        storePresence(request, result.present);
    if (result.annotationDocuments.length)
    {
        auto annotations = loadAnnotations(cache);
        foreach (index, ref type; result.annotationTypes)
            annotations[type.name] = result.annotationDocuments[index];
        state.annotations = saveAnnotations(cache, annotations);
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
        if (!extractInto(request, sources, null, plan.unknownClasses, keys, state, outcome))
            return false;
        model.present = state.present.dup;
        plan = analyze(model, input);
    }
    outcome.application = plan.application;
    outcome.diagnostics = plan.diagnostics;
    outcome.removed = plan.removed;
    if (plan.failed)
        return false;
    return writeOutput(request.root, plan, sources, outcome);
}

private bool writeOutput(string root, const ref imported!"flint_tool.engine.aot.plan".Plan plan,
        scope const SourceModule[] sources, ref AotOutcome outcome)
{
    import std.algorithm.searching : canFind;
    import std.algorithm.sorting : sort;
    import std.file : SpanMode, dirEntries, exists, isFile, mkdirRecurse, remove;
    import std.path : buildNormalizedPath, buildPath, dirName;
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
        const text = renderModule(item, plan.canonicalNames);
        if (!separable(item.name, item.source, text, sources, outcome))
            return false;
        mkdirRecurse(dirName(path));
        if (writeIfChanged(path, text))
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
    string[] normalizedWritten;
    foreach (path; written)
        normalizedWritten ~= buildNormalizedPath(path);
    foreach (entry; dirEntries(directory, "*.d", SpanMode.depth))
    {
        // Normalized on both sides: on Windows a listing spells `\` where a joined path may keep `/`.
        if (isFile(entry.name) && !normalizedWritten.canFind(buildNormalizedPath(entry.name)))
            remove(entry.name);
    }
    return true;
}

/// `flint build` compiles the generated modules of modules outside `src/` as a separate library that DUB keeps
/// across edits (aot-contract.md section 3), so such a module must not import a project module. A compiled SpEL
/// `@bean` reference from a platform module to a project bean would; that is FLINT-E1116.
private bool separable(string name, string source, string text, scope const SourceModule[] sources,
        ref AotOutcome outcome)
{
    import std.algorithm.searching : canFind;
    import flint_tool.diagnostics.report : portablePath;
    import flint_tool.engine.aot.plan : Diagnostic;

    bool platform;
    foreach (ref item; sources)
        platform = platform || (item.name == name && !item.user);
    if (!platform)
        return true;
    foreach (ref item; sources)
    {
        if (item.user && text.canFind("static import " ~ item.name ~ ";"))
        {
            const message = "the generated code of " ~ name
                ~ ", which is outside src/, would import the project " ~ "module " ~ item.name;
            outcome.diagnostics ~= Diagnostic("FLINT-E1116", message, portablePath(source), 1);
            return false;
        }
    }
    return true;
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
        if (const models = "models" in root.objectNoRef)
        {
            foreach (name, value; models.objectNoRef)
                state.models[name] = value.str;
        }
        if (const annotations = "annotations" in root.objectNoRef)
            state.annotations = annotations.str;
        if (const imported = "imported" in root.objectNoRef)
        {
            foreach (ref item; imported.arrayNoRef)
                state.importedModules ~= item.str;
        }
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
    JSONValue[string] models;
    foreach (name, hash; state.models)
        models[name] = JSONValue(hash);
    JSONValue root = JSONValue([
        "models": JSONValue(models),
        "annotations": JSONValue(state.annotations),
        "schema": JSONValue("flint.aot.state/2"),
        "environment": JSONValue(state.environmentKey),
        "output": JSONValue(state.outputKey),
        "keys": JSONValue(keys),
        "present": JSONValue(present),
        "imported": JSONValue(state.importedModules)
    ]);
    mkdirRecurse(cache);
    write(buildPath(cache, "state.json"), root.toString);
}

/// The shared-cache key of a project module's model: its extraction key and the project root.
private string sharedProjectKey(string key, string root)
{
    import flint_tool.support.files : sha256Hex;

    return sha256Hex(cast(const(ubyte)[])(key ~ "\n" ~ root));
}

/// The shared cache's entry for the generated output of `outputKey` in this project.
private string outputEntry(const ref AotRequest request, string outputKey)
{
    import std.path : buildPath;

    return buildPath(request.sharedCache, "outputs", sharedProjectKey(outputKey, request.root) ~ ".json");
}

/// Keep the generated files, and what the step reports about them, for a later cold build of this project.
private void storeOutput(const ref AotRequest request, string outputKey, const ref AotOutcome outcome)
{
    import std.file : SpanMode, dirEntries, isFile, readText;
    import std.json : JSONValue;
    import std.path : buildPath, relativePath;
    import flint_tool.diagnostics.report : portablePath;

    const directory = buildPath(request.root, aotDirectory);
    JSONValue[string] files;
    foreach (entry; dirEntries(directory, "*.d", SpanMode.depth))
    {
        if (isFile(entry.name))
            files[portablePath(relativePath(entry.name, directory))] = JSONValue(readText(entry.name));
    }
    JSONValue[] diagnostics;
    foreach (ref item; outcome.diagnostics)
        diagnostics ~= JSONValue([
        "code": JSONValue(item.code),
        "message": JSONValue(item.message),
        "file": JSONValue(item.file),
        "line": JSONValue(item.line),
        "warning": JSONValue(item.warning)
    ]);
    JSONValue[string] root;
    root["files"] = JSONValue(files);
    root["application"] = JSONValue(outcome.application);
    root["generated"] = JSONValue(outcome.generated);
    root["removed"] = JSONValue(outcome.removed);
    root["diagnostics"] = JSONValue(diagnostics);
    writeAtomically(outputEntry(request, outputKey), JSONValue(root).toString);
}

/// Write a stored generated output (removing other generated files); false when there is none or it is unreadable.
private bool restoreOutput(const ref AotRequest request, string outputKey, ref AotOutcome outcome)
{
    import std.algorithm.searching : canFind;
    import std.file : SpanMode, dirEntries, exists, isFile, mkdirRecurse, readText, remove;
    import std.json : JSONType, parseJSON;
    import std.path : buildNormalizedPath, buildPath, dirName;
    import flint_tool.engine.aot.plan : Diagnostic;
    import flint_tool.support.files : writeIfChanged;

    const path = outputEntry(request, outputKey);
    if (!exists(path))
        return false;
    string[string] files;
    AotOutcome restored;
    try
    {
        const root = parseJSON(readText(path));
        foreach (name, value; root["files"].objectNoRef)
            files[name] = value.str;
        restored.application = root["application"].str;
        restored.generated = cast(size_t) root["generated"].integer;
        foreach (ref item; root["removed"].arrayNoRef)
            restored.removed ~= item.str;
        foreach (ref item; root["diagnostics"].arrayNoRef)
            restored.diagnostics ~= Diagnostic(item["code"].str, item["message"].str,
                    item["file"].str, item["line"].integer, item["warning"].type == JSONType.true_);
    }
    catch (Exception)
        return false; // unreadable or half-written: generate instead
    const directory = buildPath(request.root, aotDirectory);
    string[] written;
    foreach (name, text; files)
    {
        const target = buildPath(directory, name);
        mkdirRecurse(dirName(target));
        if (writeIfChanged(target, text))
            ++outcome.written;
        written ~= buildNormalizedPath(target);
    }
    if (exists(directory))
    {
        foreach (entry; dirEntries(directory, "*.d", SpanMode.depth))
        {
            if (isFile(entry.name) && !written.canFind(buildNormalizedPath(entry.name)))
                remove(entry.name);
        }
    }
    outcome.application = restored.application;
    outcome.generated = restored.generated;
    outcome.removed = restored.removed;
    outcome.diagnostics = restored.diagnostics;
    return true;
}

/// The shared cache's entry for a model key.
private string sharedEntry(string sharedCache, string key)
{
    import std.path : buildPath;

    return buildPath(sharedCache, "models", key ~ ".json");
}

/// Take the requested modules' models from the shared cache (`keyed`: their shared-cache keys); the modules
/// left to extract.
private string[] reuseShared(string sharedCache, scope const string[] requested,
        const string[string] keyed, const string[string] keys, string cache, ref State state, ref AotOutcome outcome)
{
    string[] modules;
    string[string] reusedAnnotations;
    bool[string] sets;
    foreach (name; requested)
    {
        const sharedKey = name in keyed;
        if (sharedKey is null || !reuseShared(sharedCache, name, *sharedKey, keys.get(name, null),
                cache, state, reusedAnnotations, sets))
            modules ~= name;
        else
            outcome.reused++;
    }
    if (reusedAnnotations.length)
    {
        auto merged = loadAnnotations(cache);
        foreach (type, value; reusedAnnotations)
            merged[type] = value;
        state.annotations = saveAnnotations(cache, merged);
    }
    return modules;
}

/// Take a module's model, and the annotation types its extraction announced, from the shared cache.
private bool reuseShared(string sharedCache, string name, string sharedKey, string key, string cache,
        ref State state, ref string[string] annotations, ref bool[string] sets)
{
    import std.file : exists, mkdirRecurse, readText, write;
    import std.json : JSONException, JSONType, parseJSON;
    import std.path : buildPath;

    const path = sharedEntry(sharedCache, sharedKey);
    if (sharedKey.length == 0 || key.length == 0 || !exists(path))
        return false;
    string document;
    string set;
    try
    {
        const root = parseJSON(readText(path));
        document = root["model"].str;
        set = root["annotationSet"].str;
    }
    catch (Exception)
        return false; // unreadable, half-written or an older entry: extract instead
    if (set !in sets)
    {
        string[string] found;
        try
        {
            foreach (type, value; parseJSON(readText(annotationSetPath(sharedCache, set))).objectNoRef)
                found[type] = value.str;
        }
        catch (Exception)
            return false;
        foreach (type, value; found)
            annotations[type] = value;
        sets[set] = true;
    }
    mkdirRecurse(buildPath(cache, "models"));
    write(modelPath(cache, name), document);
    state.keys[name] = key;
    state.models[name] = imported!"flint_tool.support.files".sha256Hex(cast(const(ubyte)[]) document);
    return true;
}

/// Keep a model, with the annotation types of its extraction compile, in the shared cache.
private void storeShared(string sharedCache, string key, string document, string annotationSet)
{
    import std.json : JSONValue;

    if (key.length == 0 || annotationSet.length == 0)
        return;
    JSONValue[string] root;
    root["model"] = JSONValue(document);
    root["annotationSet"] = JSONValue(annotationSet);
    writeAtomically(sharedEntry(sharedCache, key), JSONValue(root).toString);
}

/// Keep the annotation types one extraction compile announced, once, by content: the models of that compile
/// refer to the set by its hash, so a cold build parses each set once. Returns the hash.
private string storeAnnotationSet(string sharedCache,
        const ref imported!"flint_tool.engine.aot.extract".ExtractionResult result)
{
    import std.file : exists;
    import std.json : JSONValue;
    import flint_tool.support.files : sha256Hex;

    JSONValue[string] annotations;
    foreach (index, ref type; result.annotationTypes)
        annotations[type.name] = JSONValue(result.annotationDocuments[index]);
    const text = JSONValue(annotations).toString;
    const hash = sha256Hex(cast(const(ubyte)[]) text);
    if (!exists(annotationSetPath(sharedCache, hash)))
        writeAtomically(annotationSetPath(sharedCache, hash), text);
    return hash;
}

private string annotationSetPath(string sharedCache, string hash)
{
    import std.path : buildPath;

    return buildPath(sharedCache, "annotations", hash ~ ".json");
}

/// The shared class-presence answers of this environment.
private string presencePath(const ref AotRequest request)
{
    import std.path : buildPath;

    return buildPath(request.sharedCache, "presence", request.environmentKey ~ ".json");
}

private bool[string] loadPresence(const ref AotRequest request)
{
    import std.file : exists, readText;
    import std.json : JSONType, parseJSON;

    bool[string] answers;
    const path = presencePath(request);
    if (!exists(path))
        return answers;
    try
    {
        foreach (name, value; parseJSON(readText(path)).objectNoRef)
            answers[name] = value.type == JSONType.true_;
    }
    catch (Exception)
        return null;
    return answers;
}

/// The probes the shared answers do not settle; the settled ones go into `state`.
private string[] sharedPresence(const ref AotRequest request, scope const string[] probes, ref State state)
{
    const answers = loadPresence(request);
    string[] open;
    foreach (name; probes)
    {
        if (const answer = name in answers)
            state.present[name] = *answer;
        else
            open ~= name;
    }
    return open;
}

private void storePresence(const ref AotRequest request, const bool[string] found)
{
    import std.json : JSONValue;

    JSONValue[string] values;
    foreach (name, answer; loadPresence(request))
        values[name] = JSONValue(answer);
    foreach (name, answer; found)
        values[name] = JSONValue(answer);
    writeAtomically(presencePath(request), JSONValue(values).toString);
}

/// Write through a temporary file and a rename, so a concurrent build never reads half a file.
private void writeAtomically(string path, string text)
{
    import std.conv : to;
    import std.file : mkdirRecurse, rename, write;
    import std.path : dirName;
    import std.process : thisProcessID;

    mkdirRecurse(dirName(path));
    const temporary = path ~ "." ~ thisProcessID.to!string ~ ".tmp";
    write(temporary, text);
    rename(temporary, path);
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

/// Write the annotation types; their SHA-256.
private string saveAnnotations(string cache, const string[string] annotations)
{
    import std.file : mkdirRecurse, write;
    import std.json : JSONValue;
    import std.path : buildPath;
    import flint_tool.support.files : sha256Hex;

    JSONValue[string] values;
    foreach (name, document; annotations)
        values[name] = JSONValue(document);
    mkdirRecurse(cache);
    const text = JSONValue(values).toString;
    write(buildPath(cache, "annotations.json"), text);
    return sha256Hex(cast(const(ubyte)[]) text);
}

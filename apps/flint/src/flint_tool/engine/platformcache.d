/// The platform cache (ADR-030 section 5). The pinned platform modules (the core packages, framework modules and
/// Boot libraries) are compiled once per compiler, flags, platform version and target into archives, and app builds
/// link those archives instead of compiling the modules again. MVS modules (path, repository and DUB
/// dependencies) always compile from source.
///
/// A build describes the core packages through a synthetic root (`.flint/generated/platform-describe`), keys every
/// module, primes the missing ones with one DUB build, and stores their archives with normalized member headers
/// under `<cache>/platform/<key>/`. It then writes `.flint/generated/platform`: a `flint` recipe whose subpackages
/// are a module's import paths and settings without sources. The project's recipe depends on that recipe and links
/// the archives as one group.
///
/// A rebuild from the same source with the same toolchain and flags gives the same archive bytes
/// (tests/test_flint_platform_cache.py). The import interface is the pinned source itself: DMD 2.114's `-H`
/// interface files drop the function bodies that compile-time evaluation needs, and its `-inline` full output
/// loses the imports behind expanded UDA sequences, so `.di` files do not compile Flint's modules.
module flint_tool.engine.platformcache;

import flint_tool.engine.session : Session;
import flint_tool.diagnostics.report : Report;
import flint_tool.project.resolve : Resolution;
import flint.os : EnvVar;

@safe:

/// The synthetic root that describes and primes the core packages, relative to the project root.
enum describeDirectory = ".flint/generated/platform-describe";
/// The `flint` recipe that lists every core package at its own directory, relative to the project root.
enum sourceDirectory = ".flint/generated/platform-source";
/// The `flint` recipe of archive-backed subpackages the project links, relative to the project root.
enum platformDirectory = ".flint/generated/platform";
/// Part of every key: a change to the cache's layout or key changes every key.
enum cacheFormat = "flint.platform-cache/1";
/// Archives kept per module. A source edit re-keys the module and every module that imports it, so the cache keeps
/// the newest few and removes older ones after each priming build.
enum keptPerModule = 4;
/// The compile server's platform prelude, relative to the project root (`renderPrelude`).
enum preludeFile = ".flint/generated/platform/dmd-server-prelude.txt";

/// One platform module, as DUB describes it.
struct PlatformModule
{
    /// DUB name: `flint:web`.
    string name;
    /// DUB target type: `library`, or `none` for a starter that only gathers dependencies.
    string targetType;
    /// Package directory.
    string directory;
    /// Archive file name: `libflint_web.a`.
    string targetFileName;
    /// Where DUB writes the archive when the describe root is built.
    string artifact;
    /// Absolute import paths.
    string[] importPaths;
    /// Absolute string import paths.
    string[] stringImportPaths;
    /// Version identifiers.
    string[] versions;
    /// Compiler flags of the recipe.
    string[] dflags;
    /// Linker flags of the recipe: native archives and system libraries.
    string[] lflags;
    /// Libraries.
    string[] libs;
    /// Direct dependencies.
    string[] dependencies;
    /// Every file DUB lists for the package, sorted.
    string[] files;
    /// Cache key.
    string key;
    /// The cached archive.
    string archive;
    /// SHA-256 of the cached archive.
    string archiveSha256;
}

/// What a build links from the cache.
struct PlatformPlan
{
    /// The project links the platform recipe.
    bool active;
    /// Every platform module.
    PlatformModule[] modules;
    /// The cached archives, sorted.
    string[] archives;
    /// Modules compiled into the cache by this build.
    size_t primed;
    /// The compile server's prelude for the project's platform modules: FLINT_DMD_SERVER_PRELUDE.
    string prelude;
    /// The cache root.
    string cache;
    /// Hash of the tools, flags, target and every platform module's key: what an archive compiled against the
    /// platform depends on besides its own sources (`aotLibraryModule`).
    string platformKey;
    /// The inputs the plan was made with.
    PlatformInputs inputs;
}

/// What keys and builds the platform modules: the tools, flags and environment of the project's build.
struct PlatformInputs
{
    /// DUB executable.
    string dub;
    /// Compiler executable.
    string compiler;
    /// SHA-256 of the compiler executable.
    string compilerSha256;
    /// SHA-256 of the DUB executable.
    string dubSha256;
    /// Flint platform release.
    string release;
    /// Profile flags, as DFLAGS.
    string dflags;
    /// Target name.
    string target;
    /// The build's environment.
    EnvVar[] environment;
    /// The cache root: FLINT_CACHE or `<home>/.flint/cache`.
    string cache;
    /// Where DUB runs the compiler: the home. Debug information records the compiler's working directory, so a
    /// per-project directory would make every project's archives differ.
    string workingDirectory;
    /// The build links the platform as one shared object (`linkSharedPlatform`): the platform recipe then leaves
    /// the native libraries to that object.
    bool sharedLink;

    /// A copy that owns its environment.
    PlatformInputs copy() const
    {
        PlatformInputs result = {
            dub: dub, compiler: compiler, compilerSha256: compilerSha256, dubSha256: dubSha256, release: release,
            dflags: dflags, target: target, cache: cache, workingDirectory: workingDirectory, sharedLink: sharedLink
        };
        foreach (ref variable; environment)
            result.environment ~= EnvVar(variable.name, variable.value);
        return result;
    }
}

/// Whether a build may link the platform cache. `FLINT_PLATFORM_CACHE=0` turns it off. Sanitizer and cross builds
/// compile from source, and so do hosts whose archive format the cache does not normalize yet.
bool platformCacheAllowed(bool requested, bool sanitize, string target)
{
    import std.process : environment;

    if (!requested || sanitize || target.length || environment.get("FLINT_PLATFORM_CACHE", "") == "0")
        return false;
    version (linux)
        return true;
    else
        return false;
}

/// Prepare the platform recipe for a project: describe the core packages, prime and store the missing archives,
/// and write `.flint/generated/platform`. False, with FLINT-E0712 reported, when DUB cannot describe or build them.
bool planPlatform(ref Session session, string root, const ref Resolution resolution,
        const ref PlatformInputs inputs, out PlatformPlan plan, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.engine.recipe : joinsRepos, renderJoinedRoot;
    import flint_tool.support.files : writeIfChanged;

    const describeRoot = buildPath(root, describeDirectory);
    const joined = joinsRepos(session.home, resolution);
    if (joined)
        writeIfChanged(buildPath(root, sourceDirectory, "dub.sdl"), renderJoinedRoot(session.home,
                resolution, buildPath(root, sourceDirectory)));
    writeIfChanged(buildPath(describeRoot, "dub.sdl"), renderDescribeRoot(resolution, joined
            ? "../platform-source" : session.home.root));
    string failure;
    if (!describe(inputs, describeRoot, plan.modules, failure))
        return cacheFailed("DUB could not describe the platform modules", failure, report);
    assignKeys(plan.modules, inputs);
    size_t[] missing;
    foreach (position, ref item; plan.modules)
    {
        if (built(item) && !cachedArchive(item, inputs.cache))
            missing ~= position;
    }
    if (missing.length)
    {
        import std.conv : to;

        session.progress("Priming", missing.length.to!string ~ " platform module(s) into the cache");
        if (!prime(inputs, describeRoot, failure))
            return cacheFailed("the platform modules failed to build", failure, report);
        foreach (position; missing)
        {
            if (!storeArchive(plan.modules[position], inputs.cache, failure))
                return cacheFailed("a platform archive could not be stored", failure, report);
        }
        plan.primed = missing.length;
        prune(inputs.cache, keptPerModule);
    }
    foreach (ref item; plan.modules)
    {
        if (item.archive.length)
            plan.archives ~= item.archive;
    }
    writeIfChanged(buildPath(root, platformDirectory, "dub.sdl"), renderPlatformRoot(plan.modules, inputs.sharedLink));
    plan.prelude = buildPath(root, preludeFile);
    plan.cache = inputs.cache;
    plan.inputs = inputs.copy();
    plan.platformKey = platformKeyOf(plan.modules, inputs);
    writeIfChanged(plan.prelude, renderPrelude(plan.modules, resolution.direct, inputs.dflags));
    plan.active = true;
    return true;
}

private bool cacheFailed(string message, string output, ref Report report)
{
    import flint_tool.engine.builder : tail;

    report.error("FLINT-E0712", message,
            "flint build --no-platform-cache builds them from source; DUB said:\n" ~ tail(output));
    return false;
}

/// The synthetic root: every core package from `source`, the directory of the `flint` recipe that lists them (the
/// home, or the joined recipe of several checkouts). Test-only packages are included, because the project's
/// unittest configuration names them even when a build does not use it.
string renderDescribeRoot(const ref Resolution resolution, string source)
{
    import flint_tool.engine.recipe : quoted, recipePath;

    string text = "// Generated by flint: the platform modules this project links (ADR-030 section 5).\n"
        ~ "name \"flint-platform\"\ntargetType \"none\"\n";
    foreach (ref item; resolution.packages)
    {
        if (item.kind == "core")
            text ~= "dependency " ~ quoted(item.name) ~ " path=" ~ quoted(recipePath(source)) ~ "\n";
    }
    return text;
}

private string[] dubCommand(const ref PlatformInputs inputs, string verb, string describeRoot)
{
    return [
        inputs.dub, verb, "--root=" ~ describeRoot, "--compiler=" ~ inputs.compiler, "--build=plain",
        "--skip-registry=all"
    ];
}

private bool describe(const ref PlatformInputs inputs, string describeRoot,
        out PlatformModule[] modules, out string failure)
{
    import flint_tool.support.process : Launch, capture;

    Launch launch;
    launch.directory = inputs.workingDirectory;
    launch.environment = inputs.environment.dup;
    launch.inherit = false;
    const outcome = capture(dubCommand(inputs, "describe", describeRoot), launch);
    if (!outcome.ok)
    {
        failure = outcome.started ? outcome.combined : outcome.failure;
        return false;
    }
    return parseDescription(outcome.output, modules, failure);
}

/// The platform modules in `dub describe` output: every `flint:` package, with its target's archive path.
bool parseDescription(string text, out PlatformModule[] modules, out string failure)
{
    import std.algorithm.sorting : sort;
    import std.json : JSONException, JSONValue, parseJSON;

    try
    {
        auto document = parseJSON(text);
        string[string] artifacts;
        foreach (ref target; document["targets"].arrayNoRef)
            artifacts[target["rootPackage"].str] = target["cacheArtifactPath"].str;
        foreach (ref package_; document["packages"].arrayNoRef)
        {
            const name = package_["name"].str;
            if (name.length > 6 && name[0 .. 6] == "flint:")
                modules ~= moduleOf(package_, artifacts);
        }
    }
    catch (JSONException error)
    {
        failure = "unreadable dub describe output: " ~ error.msg;
        return false;
    }
    sort!((a, b) => a.name < b.name)(modules);
    return true;
}

private PlatformModule moduleOf(const ref imported!"std.json".JSONValue package_, const string[string] artifacts)
{
    import std.algorithm.sorting : sort;
    import std.path : buildNormalizedPath;

    PlatformModule item;
    item.name = package_["name"].str;
    item.targetType = package_["targetType"].str;
    item.directory = buildNormalizedPath(package_["path"].str);
    item.targetFileName = package_["targetFileName"].str;
    if (auto artifact = item.name in artifacts)
        item.artifact = *artifact;
    foreach (path; strings(package_, "importPaths"))
        item.importPaths ~= buildNormalizedPath(item.directory, path);
    foreach (path; strings(package_, "stringImportPaths"))
        item.stringImportPaths ~= buildNormalizedPath(item.directory, path);
    item.versions = strings(package_, "versions");
    item.dflags = strings(package_, "dflags");
    item.lflags = strings(package_, "lflags");
    item.libs = strings(package_, "libs");
    item.dependencies = strings(package_, "dependencies");
    foreach (ref file; package_["files"].arrayNoRef)
        item.files ~= buildNormalizedPath(item.directory, file["path"].str);
    sort(item.files);
    return item;
}

private string[] strings(const ref imported!"std.json".JSONValue value, string key)
{
    string[] values;
    if (auto list = key in value.objectNoRef)
    {
        foreach (ref entry; list.arrayNoRef)
            values ~= entry.str;
    }
    return values;
}

/// Key every module, dependencies first: the toolchain, flags and target, the module's settings, the content of
/// every file DUB lists for it, and its dependencies' keys. A change to a module's source therefore rebuilds it
/// and every module that imports it, as its inlined functions and template instances may change.
void assignKeys(PlatformModule[] modules, const ref PlatformInputs inputs)
{
    size_t[string] index;
    foreach (position, ref item; modules)
        index[item.name] = position;
    string[string] fileDigests;
    bool[string] visiting;
    void visit(size_t position)
    {
        auto item = &modules[position];
        if (item.key.length || item.name in visiting)
            return;
        visiting[item.name] = true;
        string[] dependencyKeys;
        foreach (dependency; item.dependencies)
        {
            if (auto found = dependency in index)
            {
                visit(*found);
                dependencyKeys ~= dependency ~ "=" ~ modules[*found].key;
            }
        }
        item.key = moduleKey(*item, inputs, dependencyKeys, fileDigests);
    }

    foreach (position; 0 .. modules.length)
        visit(position);
}

private string moduleKey(const ref PlatformModule item, const ref PlatformInputs inputs,
        scope const string[] dependencyKeys, ref string[string] fileDigests)
{
    import std.algorithm.sorting : sort;
    import flint_tool.support.files : cachedSha256File, sha256Hex;

    string text = cacheFormat ~ "\nworking-directory " ~ inputs.workingDirectory ~ "\nrelease " ~ inputs.release
        ~ "\ncompiler " ~ inputs.compilerSha256 ~ "\ndub " ~ inputs.dubSha256 ~ "\ndflags "
        ~ inputs.dflags ~ "\ntarget " ~ inputs.target ~ "\nmodule " ~ item.name ~ "\ndirectory "
        ~ item.directory ~ "\ntype " ~ item.targetType ~ "\n";
    text ~= listed("import", item.importPaths) ~ listed("string-import",
            item.stringImportPaths) ~ listed("version", item.versions) ~ listed("dflag",
            item.dflags) ~ listed("lflag", item.lflags) ~ listed("lib", item.libs);
    foreach (file; item.files)
    {
        if (file !in fileDigests)
            fileDigests[file] = cachedSha256File(file);
        text ~= "file " ~ file ~ " " ~ fileDigests[file] ~ "\n";
    }
    auto keys = dependencyKeys.dup;
    sort(keys);
    text ~= listed("dependency", keys);
    return sha256Hex(cast(const(ubyte)[]) text);
}

private string listed(string label, scope const string[] values)
{
    string text;
    foreach (value; values)
        text ~= label ~ " " ~ value ~ "\n";
    return text;
}

/// Whether the describe root builds a module. A package that only another package's unittest configuration names
/// (flint:framework-test) is described but never built; the platform recipe still lists it, without an archive.
private bool built(const ref PlatformModule item)
{
    return item.targetType == "library" && item.artifact.length;
}

/// The cache directory of a module.
string entryDirectory(string cache, const ref PlatformModule item)
{
    import std.path : buildPath;

    return buildPath(cache, "platform", item.key);
}

/// Whether a module's archive is in the cache; sets its path and digest when it is.
/// Whether `item`'s archive is in the cache; sets its `archive` and `archiveSha256` when it is.
bool cachedArchive(ref PlatformModule item, string cache)
{
    import std.file : exists;
    import std.json : JSONException, parseJSON;
    import std.path : buildPath;
    import flint_tool.support.files : readIfPresent;

    const directory = entryDirectory(cache, item);
    const archive = buildPath(directory, item.targetFileName);
    const record = readIfPresent(buildPath(directory, "module.json"));
    if (record.length == 0 || !exists(archive))
        return false;
    try
    {
        item.archiveSha256 = parseJSON(record)["sha256"].str;
    }
    catch (JSONException)
        return false;
    item.archive = archive;
    return true;
}

private bool prime(const ref PlatformInputs inputs, string describeRoot, out string failure)
{
    import flint_tool.support.process : Launch, capture;

    Launch launch;
    launch.directory = inputs.workingDirectory;
    launch.environment = inputs.environment.dup;
    launch.inherit = false;
    const outcome = capture(dubCommand(inputs, "build", describeRoot), launch);
    if (outcome.ok)
        return true;
    failure = outcome.started ? outcome.combined : outcome.failure;
    return false;
}

/// Copy a module's freshly built archive into the cache with normalized member headers, then record its digest.
/// The archive and its record are written under temporary names and renamed, so a reader never sees half of one.
bool storeArchive(ref PlatformModule item, string cache, out string failure)
{
    import std.file : exists, mkdirRecurse, read, rename, write;
    import std.path : buildPath;
    import flint_tool.support.files : sha256Hex;

    if (!exists(item.artifact))
    {
        failure = item.name ~ ": DUB built no " ~ item.artifact;
        return false;
    }
    auto bytes = (cast(const(ubyte)[]) read(item.artifact)).dup;
    normalizeArchive(bytes);
    const directory = entryDirectory(cache, item);
    mkdirRecurse(directory);
    const archive = buildPath(directory, item.targetFileName);
    write(archive ~ ".partial", bytes);
    rename(archive ~ ".partial", archive);
    item.archive = archive;
    item.archiveSha256 = sha256Hex(bytes);
    const record = buildPath(directory, "module.json");
    write(record ~ ".partial", "{\"format\": \"" ~ cacheFormat ~ "\", \"module\": \"" ~ item.name
            ~ "\", \"key\": \"" ~ item.key ~ "\", \"sha256\": \"" ~ item.archiveSha256 ~ "\"}\n");
    rename(record ~ ".partial", record);
    return true;
}

/// Remove all but the `kept` newest entries of each module from the cache, newest by their record's time.
void prune(string cache, size_t kept)
{
    import std.algorithm.sorting : sort;
    import std.datetime.systime : SysTime;
    import std.file : DirEntry, SpanMode, dirEntries, exists, isDir, rmdirRecurse, timeLastModified;
    import std.json : JSONException, parseJSON;
    import std.path : buildPath;
    import flint_tool.support.files : readIfPresent;

    struct Entry
    {
        string directory;
        SysTime time;
    }

    Entry[][string] byModule;
    const root = buildPath(cache, "platform");
    if (!exists(root) || !isDir(root))
        return;
    foreach (DirEntry entry; dirEntries(root, SpanMode.shallow, false))
    {
        const record = buildPath(entry.name, "module.json");
        const text = entry.isDir ? readIfPresent(record) : null;
        if (text.length == 0)
            continue;
        try
            byModule[parseJSON(text)["module"].str] ~= Entry(entry.name, timeLastModified(record));
        catch (JSONException)
            continue;
    }
    foreach (name, ref entries; byModule)
    {
        sort!((a, b) => a.time > b.time)(entries);
        foreach (ref entry; entries.length > kept ? entries[kept .. $] : null)
            rmdirRecurse(entry.directory);
    }
}

/// Zero the modification time, owner and group, and set mode 644, in every member header of an `ar` archive, as
/// `ar D` does. A rebuilt module then has the same bytes: only these fields differed between two builds of the
/// same source. Bytes that are not an archive are left alone.
void normalizeArchive(ubyte[] bytes)
{
    enum magic = "!<arch>\n";
    enum headerLength = 60;
    if (bytes.length < magic.length || cast(const(char)[]) bytes[0 .. magic.length] != magic)
        return;
    size_t offset = magic.length;
    while (offset + headerLength <= bytes.length)
    {
        auto header = bytes[offset .. offset + headerLength];
        const size = memberSize(header[48 .. 58]);
        if (size < 0)
            return;
        setField(header[16 .. 28], "0");
        setField(header[28 .. 34], "0");
        setField(header[34 .. 40], "0");
        setField(header[40 .. 48], "644");
        offset += headerLength + cast(size_t) size;
        offset += offset & 1;
    }
}

private long memberSize(scope const(ubyte)[] field)
{
    long size;
    bool digits;
    foreach (c; field)
    {
        if (c == ' ')
            break;
        if (c < '0' || c > '9')
            return -1;
        size = size * 10 + (c - '0');
        digits = true;
    }
    return digits ? size : -1;
}

private void setField(ubyte[] field, string value)
{
    field[] = ' ';
    field[0 .. value.length] = cast(const(ubyte)[]) value;
}

/// The `flint` recipe the project links: an archive-backed module is its import paths and settings without
/// sources, and a module without a target only gathers its dependencies. The archives themselves are linked by
/// the project's recipe, as one group (linkGroup).
string renderPlatformRoot(scope const PlatformModule[] modules, bool sharedLink = false)
{
    import flint_tool.engine.recipe : quoted;

    string text = "// Generated by flint: the platform modules, linked from the platform cache (ADR-030 section 5).\n"
        ~ "name \"flint\"\ntargetType \"none\"\n";
    foreach (ref item; modules)
    {
        text ~= "subPackage {\n    name " ~ quoted(item.name[6 .. $]) ~ "\n    targetType " ~ quoted(
                item.archive.length ? "sourceLibrary" : "none") ~ "\n";
        text ~= values("importPaths", item.importPaths, true) ~ values("stringImportPaths",
                item.stringImportPaths, true) ~ values("versions", item.versions) ~ values("dflags", item.dflags);
        if (!sharedLink) // the shared object carries the native libraries
            text ~= values("lflags", item.lflags) ~ values("libs", item.libs);
        foreach (dependency; item.dependencies)
            text ~= "    dependency " ~ quoted(dependency) ~ " version=\"*\"\n";
        text ~= "}\n";
    }
    return text;
}

private string values(string key, scope const string[] items, bool paths = false)
{
    import flint_tool.engine.recipe : quoted, recipePath;

    if (items.length == 0)
        return null;
    string text = "    " ~ key;
    foreach (item; items)
        text ~= " " ~ quoted(paths ? recipePath(item) : item.replaceDollars);
    return text ~ "\n";
}

/// DUB expands `$NAME` in recipe fields; `$$` is a literal dollar.
private string replaceDollars(string value)
{
    import std.array : replace;

    return value.replace("$", "$$");
}

private string platformKeyOf(scope const PlatformModule[] modules, const ref PlatformInputs inputs)
{
    import flint_tool.support.files : sha256Hex;

    string text = cacheFormat ~ "\nworking-directory " ~ inputs.workingDirectory ~ "\nrelease " ~ inputs.release
        ~ "\ncompiler " ~ inputs.compilerSha256 ~ "\ndub " ~ inputs.dubSha256 ~ "\ndflags "
        ~ inputs.dflags ~ "\ntarget " ~ inputs.target ~ "\n";
    foreach (ref item; modules) // sorted by name (parseDescription)
        text ~= "module " ~ item.name ~ " " ~ item.key ~ "\n";
    return sha256Hex(cast(const(ubyte)[]) text);
}

/// The AOT library (engine/recipe.d `renderAotLibraryRecipe`) as a cacheable archive. Its generated modules import no
/// project module (FLINT-E1116), so its archive depends only on their text, the diagnostic flags and what the
/// platform's archives depend on (`PlatformPlan.platformKey`). `files` are absolute paths below `aotDirectory`;
/// `artifact` is where DUB writes the library.
PlatformModule aotLibraryModule(const ref PlatformPlan plan, string aotDirectory,
        scope const string[] files, scope const string[] diagnosticFlags, string artifact)
{
    import std.array : replace;
    import std.path : baseName, dirSeparator, relativePath;
    import flint_tool.engine.recipe : aotLibraryName;
    import flint_tool.support.files : sha256File, sha256Hex;

    PlatformModule item;
    item.name = aotLibraryName;
    item.targetType = "library";
    item.targetFileName = baseName(artifact);
    item.artifact = artifact;
    string text = "flint.aot-library/1\nplatform " ~ plan.platformKey ~ "\n" ~ listed("diagnostic", diagnosticFlags);
    foreach (file; files)
        text ~= "file " ~ relativePath(file, aotDirectory).replace(dirSeparator, "/") ~ " " ~ sha256File(file) ~ "\n";
    item.files = files.dup;
    item.key = sha256Hex(cast(const(ubyte)[]) text);
    return item;
}

/// Shared-object dev linking (owner decision 2, 2026-11-23). The platform's archives, and the cached AOT library,
/// are linked once into `<cache>/platform/shared-<key>/libflint-platform.so` with the native libraries they use,
/// against druntime and Phobos as a shared library. A dev build then links only the project's objects against it,
/// so an edit relinks the project and not the platform. The key covers the platform key (tools, flags, target and
/// every module's key), the extra archives' keys and the native linker flags. Linux only, as the cache is.
bool linkSharedPlatform(const ref PlatformPlan plan, scope const string[] extraArchives,
        scope const string[] extraKeys, scope const string[] nativeFlags, out string sharedObject, out string failure)
{
    import std.conv : to;
    import std.file : exists, mkdirRecurse, rename, rmdirRecurse, write;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import flint_tool.support.files : sha256Hex;
    import std.array : join;
    import flint_tool.support.process : Launch, capture;

    string text = "flint.platform-shared/2\nplatform " ~ plan.platformKey ~ "\n" ~ listed("extra",
            extraKeys) ~ listed("native", nativeFlags);
    const key = sha256Hex(cast(const(ubyte)[]) text);
    const directory = buildPath(plan.cache, "platform", "shared-" ~ key);
    sharedObject = buildPath(directory, "libflint-platform.so");
    if (exists(sharedObject))
        return true;
    const partial = directory ~ "." ~ thisProcessID.to!string ~ ".partial";
    if (exists(partial))
        rmdirRecurse(partial);
    mkdirRecurse(partial);
    const stub = buildPath(partial, "flint_platform_shared.d");
    write(stub, "module flint_platform_shared;\n");
    // DMD moves a `-L` argument that names a file after its switches, outside --whole-archive, so each region
    // reaches the linker as one `-Wl` argument through the C compiler driver, in order.
    string[] command = [
        plan.inputs.compiler, "-shared", "-defaultlib=libphobos2.so",
        "-of=" ~ buildPath(partial, "libflint-platform.so"), "-od=" ~ partial, stub,
        "-L-rpath=" ~ phobosDirectory(plan.inputs.compiler),
        "-Xcc=-Wl,--whole-archive," ~ join(plan.archives ~ extraArchives, ",") ~ ",--no-whole-archive"
    ];
    if (nativeFlags.length)
        command ~= "-Xcc=-Wl,--start-group," ~ join(nativeFlags, ",") ~ ",--end-group";
    Launch launch;
    launch.directory = plan.inputs.workingDirectory;
    launch.environment = plan.inputs.environment.dup;
    launch.inherit = false;
    const linked = capture(command, launch);
    if (!linked.ok)
    {
        failure = linked.started ? linked.combined : linked.failure;
        rmdirRecurse(partial);
        return false;
    }
    import std.file : remove;
    import flint_tool.support.files : sha256File;

    remove(stub);
    if (exists(buildPath(partial, "flint_platform_shared.o")))
        remove(buildPath(partial, "flint_platform_shared.o"));
    // A record like an archive's, so `prune` keeps the newest shared objects and removes older ones.
    write(buildPath(partial, "module.json"),
            "{\"format\": \"" ~ cacheFormat ~ "\", \"module\": \"flint-platform-shared\", \"key\": \""
            ~ key ~ "\", \"sha256\": \"" ~ sha256File(buildPath(partial, "libflint-platform.so")) ~ "\"}\n");
    if (exists(directory))
        rmdirRecurse(partial); // another build stored it first
    else
        rename(partial, directory);
    prune(plan.cache, keptPerModule);
    return true;
}

/// The directory of the compiler's druntime and Phobos libraries (`dmd2/linux/lib64` beside `bin64`).
string phobosDirectory(string compiler)
{
    import std.path : buildNormalizedPath, dirName;

    return buildNormalizedPath(dirName(compiler), "..", "lib64");
}

/// The native linker inputs of the platform modules: the object files they list as sources (flint:term's C shim,
/// which DUB hands to the final link rather than to the archive), their linker flags and their libraries.
string[] platformNativeFlags(scope const PlatformModule[] modules)
{
    import std.path : extension;

    string[] flags;
    foreach (ref item; modules)
    {
        if (item.archive.length == 0)
            continue;
        foreach (file; item.files)
        {
            if (file.extension == ".o")
                flags ~= file;
        }
        flags ~= item.lflags;
        foreach (library; item.libs)
            flags ~= "-l" ~ library;
    }
    return flags;
}

/// The linker flags that link the cached archives: one group on ELF linkers, which resolve archives in one pass,
/// so the order of the modules does not matter.
string[] linkGroup(scope const string[] archives)
{
    if (archives.length == 0)
        return null;
    version (linux)
        return ["--start-group"] ~ archives.dup ~ ["--end-group"];
    else
        return archives.dup;
}

/// The compile server's platform prelude: what the DMD compile server preloads besides druntime and Phobos, so an
/// app compile does not analyse the platform modules again. Lines are the import paths (`-I<dir>`), version
/// identifiers (`-version=<id>`) and DFLAGS the modules compile with, then the names of the D modules of every
/// platform package the project depends on, directly or not. The file is a pure function of the platform's source,
/// settings and flags, so the server keys itself by its digest, and a request whose semantic switches differ from
/// the prelude's compiles in-process.
string renderPrelude(scope const PlatformModule[] modules, scope const string[] roots, string dflags)
{
    import std.algorithm.sorting : sort;
    import std.array : split;

    size_t[string] index;
    foreach (position, ref item; modules)
        index[item.name] = position;
    bool[string] reached;
    void visit(string name)
    {
        if (name in reached || name !in index)
            return;
        reached[name] = true;
        foreach (dependency; modules[index[name]].dependencies)
            visit(dependency);
    }

    foreach (root; roots)
        visit(root);
    string[] paths, versions, names;
    bool[string] seen;
    foreach (ref item; modules)
    {
        if (item.name !in reached)
            continue;
        foreach (path; item.importPaths)
            if (unseen(seen, "-I" ~ path))
                paths ~= "-I" ~ path;
        foreach (identifier; item.versions)
            if (unseen(seen, "-version=" ~ identifier))
                versions ~= "-version=" ~ identifier;
        foreach (file; item.files)
        {
            const name = moduleName(file, item.importPaths);
            if (name.length && unseen(seen, name))
                names ~= name;
        }
    }
    sort(versions);
    sort(names);
    string text;
    foreach (line; paths ~ versions ~ dflags.split ~ names)
        text ~= line ~ "\n";
    return text;
}

private bool unseen(ref bool[string] seen, string value)
{
    if (value in seen)
        return false;
    seen[value] = true;
    return true;
}

/// The D module a source file declares by its path under the innermost import path, or null: `flint.web` for
/// `<import>/flint/web/package.d`.
private string moduleName(string file, scope const string[] importPaths)
{
    import std.array : replace;
    import std.path : dirSeparator, extension, stripExtension;

    if (file.extension != ".d")
        return null;
    string best;
    foreach (path; importPaths)
    {
        const prefix = path ~ dirSeparator;
        if (file.length > prefix.length && file[0 .. prefix.length] == prefix && path.length > best.length)
            best = path;
    }
    if (best.length == 0)
        return null;
    string name = file[best.length + 1 .. $].stripExtension.replace(dirSeparator, ".");
    enum suffix = ".package";
    if (name.length > suffix.length && name[$ - suffix.length .. $] == suffix)
        name = name[0 .. $ - suffix.length];
    return name;
}

@safe unittest
{
    ubyte[] archive = cast(ubyte[])("!<arch>\n" ~ "a.o/            1763888000  1000  1000  100664  3         `\n"
            ~ "abc\n" ~ "b.o/            1763888001  1000  1000  100664  4         `\n" ~ "wxyz").dup;
    normalizeArchive(archive);
    const text = cast(const(char)[]) archive;
    assert(text == "!<arch>\n" ~ "a.o/            0           0     0     644     3         `\n"
            ~ "abc\n" ~ "b.o/            0           0     0     644     4         `\n" ~ "wxyz");
    ubyte[] other = cast(ubyte[]) "not an archive".dup;
    normalizeArchive(other);
    assert(cast(const(char)[]) other == "not an archive");
}

version (Posix) @safe unittest  // The cache is enabled on Linux only; the fixture spells POSIX paths.
{
    const text = `{"targets": [{"rootPackage": "flint:web", "cacheArtifactPath": "/c/libflint_web.a"},
        {"rootPackage": "flint-platform", "cacheArtifactPath": "/c/"}],
      "packages": [
        {"name": "flint-platform", "path": "/p/", "targetType": "none", "targetFileName": "",
         "dependencies": ["flint:web"], "files": []},
        {"name": "flint:web", "path": "/h/framework/web/", "targetType": "library",
         "targetFileName": "libflint_web.a", "importPaths": ["source"], "versions": ["V"], "dflags": [],
         "lflags": [], "libs": [], "stringImportPaths": [], "dependencies": ["flint:core"],
         "files": [{"role": "source", "path": "source/flint/web/b.d"}, {"role": "source", "path": "source/a.d"}]},
        {"name": "flint:boot-starter", "path": "/h/boot/starter/", "targetType": "none", "targetFileName": "",
         "dependencies": ["flint:web"], "files": []}]}`;
    PlatformModule[] modules;
    string failure;
    assert(parseDescription(text, modules, failure), failure);
    assert(modules.length == 2 && modules[0].name == "flint:boot-starter" && modules[1].name == "flint:web");
    assert(modules[1].artifact == "/c/libflint_web.a");
    assert(modules[1].importPaths == ["/h/framework/web/source"]);
    assert(modules[1].files == [
        "/h/framework/web/source/a.d", "/h/framework/web/source/flint/web/b.d"
    ]);

    PlatformInputs inputs;
    inputs.dflags = "-g";
    assignKeys(modules, inputs);
    const first = modules[1].key;
    assert(first.length == 64 && modules[0].key.length == 64 && modules[0].key != first);
    auto changed = modules.dup;
    foreach (ref item; changed)
        item.key = null;
    inputs.dflags = "-O";
    assignKeys(changed, inputs);
    assert(changed[1].key != first, "the flags are part of the key");
    assert(changed[0].key != modules[0].key, "a dependency's key is part of the key");

    modules[1].archive = "/cache/k/libflint_web.a";
    const recipe = renderPlatformRoot(modules);
    enum expected = "name \"flint\"\ntargetType \"none\"\n"
        ~ "subPackage {\n    name \"boot-starter\"\n    targetType \"none\"\n"
        ~ "    dependency \"flint:web\" version=\"*\"\n}\n" ~ "subPackage {\n    name \"web\"\n"
        ~ "    targetType \"sourceLibrary\"\n    importPaths \"/h/framework/web/source\"\n    versions \"V\"\n"
        ~ "    dependency \"flint:core\" version=\"*\"\n}\n";
    assert(recipe[$ - expected.length .. $] == expected, recipe);
}

version (Posix) @safe unittest  // The fixture spells POSIX paths.
{
    PlatformModule core, web, desktop;
    core.name = "flint:core";
    core.importPaths = ["/h/core/source"];
    core.versions = ["Z", "A"];
    core.files = [
        "/h/core/source/flint/core/package.d", "/h/core/source/flint/core/views/page.d",
        "/h/core/dub.sdl"
    ];
    web.name = "flint:web";
    web.importPaths = ["/h/web/source", "/h/web/source/extra"];
    web.versions = ["A"];
    web.dependencies = ["flint:core", "vibe-d"];
    web.files = ["/h/web/source/flint/web/http.d", "/h/web/source/extra/glue.d"];
    desktop.name = "flint:desktop";
    desktop.importPaths = ["/h/desktop/source"];
    desktop.files = ["/h/desktop/source/flint/desktop.d"];
    const prelude = renderPrelude([core, desktop, web], ["flint:web"], "-g -preview=dip1000");
    assert(prelude == "-I/h/core/source\n-I/h/web/source\n-I/h/web/source/extra\n-version=A\n-version=Z\n-g\n"
            ~ "-preview=dip1000\nflint.core\nflint.core.views.page\nflint.web.http\nglue\n", prelude);
    assert(renderPrelude([core, desktop, web], null, "-g") == "-g\n");
}

@safe unittest
{
    import core.time : seconds;
    import std.conv : to;
    import std.datetime.systime : Clock;
    import std.file : dirEntries, exists, mkdirRecurse, rmdirRecurse, setTimes, tempDir, write, SpanMode;
    import std.path : buildPath;
    import std.process : thisProcessID;

    const cache = buildPath(tempDir, "flint-prune-" ~ thisProcessID.to!string);
    scope (exit)
        if (exists(cache))
            rmdirRecurse(cache);
    const now = Clock.currTime;
    foreach (index; 0 .. 6)
    {
        const directory = buildPath(cache, "platform", "web" ~ index.to!string);
        mkdirRecurse(directory);
        const record = buildPath(directory, "module.json");
        write(record, `{"module": "flint:web", "sha256": "x"}`);
        setTimes(record, now - (10 - index).seconds, now - (10 - index).seconds);
    }
    mkdirRecurse(buildPath(cache, "platform", "core"));
    write(buildPath(cache, "platform", "core", "module.json"), `{"module": "flint:core", "sha256": "x"}`);
    prune(cache, 4);
    foreach (index; 0 .. 6)
        assert(exists(buildPath(cache, "platform", "web" ~ index.to!string)) == (index >= 2));
    assert(exists(buildPath(cache, "platform", "core")));
}

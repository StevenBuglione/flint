/// Direct dev builds: flint compiles and links a project itself, without starting DUB, when everything else it
/// links comes from the platform cache (the shared platform object and cached archives). DUB's plan, up-to-date
/// checks and process cost about 20-30 ms of an edit build; the build budget for gs-rest-service is about 0.1 s.
///
/// The root package's settings (flags, versions, import paths, sources, linker files) come from
/// `dub describe --data`, kept in `.flint/generated/dub/direct.txt` while its stamp holds: the recipes, the build
/// flags, the tools and the modification time of every source directory. The compile and link commands are the
/// ones DUB runs for the same recipe: one compile of every root source with `-oq`, then one link.
module flint_tool.engine.direct;

import flint.os : EnvVar;
import flint_tool.engine.session : Session;

@safe:

/// What a direct build needs.
struct DirectBuild
{
    /// The compiler.
    string compiler;
    /// SHA-256 of the compiler.
    string compilerSha256;
    /// The DUB executable, to describe the recipe.
    string dub;
    /// SHA-256 of DUB.
    string dubSha256;
    /// The project root, where DUB runs the compiler.
    string root;
    /// The generated root recipe's directory.
    string recipeDirectory;
    /// The DUB configuration (the profile).
    string configuration;
    /// The artifact to write.
    string artifact;
    /// The build environment; DFLAGS is passed as arguments instead.
    EnvVar[] environment;
    /// The profile's flags, as DUB receives them in DFLAGS.
    string dflags;
}

/// How a direct build ended.
enum DirectResult
{
    /// The project cannot be built directly: build it with DUB.
    unavailable,
    /// Built, or already up to date.
    built,
    /// The compiler or linker failed; `output` says why.
    failed
}

/// The root package's settings, as DUB describes them.
struct RootSettings
{
    /// Compiler flags of the recipe.
    string[] dflags;
    /// Version identifiers.
    string[] versions;
    /// Debug identifiers.
    string[] debugVersions;
    /// Import paths.
    string[] importPaths;
    /// String import paths.
    string[] stringImportPaths;
    /// Every D source DUB compiles for the root.
    string[] sources;
    /// Libraries and objects DUB links.
    string[] linkerFiles;
    /// Linker flags.
    string[] lflags;
    /// System libraries.
    string[] libs;
}

/// Part of the settings record: a change to its layout invalidates every record.
private enum directFormat = "flint.direct-build/1";
/// The settings `dub describe --data` reports, in this order.
private immutable string[] dataKinds = [
    "dflags", "versions", "debug-versions", "import-paths", "string-import-paths", "source-files",
    "linker-files", "lflags", "libs"
];

/// Build the project directly, or report that DUB must. When it builds, `phases` gets the compile and link wall
/// times (-1 when nothing ran) and no DUB time.
DirectResult directBuild(ref Session session, const ref DirectBuild build, out string output,
        ref imported!"flint_tool.engine.receipt".PhasesRecord phases)
{
    import core.time : MonoTime;
    import std.path : buildPath;

    RootSettings settings;
    string failure;
    const record = buildPath(build.recipeDirectory, "direct.txt");
    if (!rootSettings(build, record, settings, failure))
        return DirectResult.unavailable;
    phases.plan = 0;
    phases.compile = -1;
    phases.link = -1;
    if (upToDate(build.artifact, record, settings))
        return DirectResult.built;
    session.progress("Building", "directly, without DUB");
    const objects = buildPath(build.root, ".flint", "build", build.configuration ~ "-objects");
    const compileStart = MonoTime.currTime;
    if (!compile(build, settings, objects, output))
        return DirectResult.failed;
    phases.compile = (MonoTime.currTime - compileStart).total!"msecs";
    const linkStart = MonoTime.currTime;
    if (!link(build, settings, objects, output))
        return DirectResult.failed;
    phases.link = (MonoTime.currTime - linkStart).total!"msecs";
    return DirectResult.built;
}

private bool rootSettings(const ref DirectBuild build, string record, out RootSettings settings, out string failure)
{
    const stamp = settingsStamp(build);
    if (readSettings(record, stamp, settings))
        return true;
    if (!describeRoot(build, settings, failure))
        return false;
    writeSettings(record, stamp, settings);
    return true;
}

private string settingsStamp(const ref DirectBuild build)
{
    import std.algorithm.searching : startsWith;
    import std.path : buildPath;
    import flint_tool.support.files : readIfPresent, sha256Hex;

    string text = directFormat ~ "\n" ~ build.compiler ~ "\n" ~ build.compilerSha256 ~ "\n" ~ build.dub
        ~ "\n" ~ build.dubSha256 ~ "\n" ~ build.configuration ~ "\n" ~ build.dflags ~ "\n" ~ readIfPresent(
                buildPath(build.recipeDirectory, "dub.sdl")) ~ "\n";
    // The recipes the root recipe depends on: the platform's and the AOT library's.
    foreach (sibling; ["platform", "aot-library", "flint"])
        text ~= readIfPresent(buildPath(build.recipeDirectory, "..", sibling, "dub.sdl")) ~ "\n";
    foreach (ref variable; build.environment)
    {
        if (variable.name.startsWith("DUB") || variable.name == "DC" || variable.name == "PATH")
            text ~= variable.name ~ "=" ~ variable.value ~ "\n";
    }
    return sha256Hex(cast(const(ubyte)[]) text);
}

/// The directories holding the root's sources, with their modification times: adding or removing a source
/// changes its directory's time.
private string[] watched(scope const string[] sources)
{
    import std.algorithm.iteration : uniq;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.conv : to;
    import std.file : FileException, timeLastModified;
    import std.path : dirName;

    string[] directories;
    foreach (source; sources)
        directories ~= dirName(source);
    sort(directories);
    string[] lines;
    foreach (directory; directories.uniq.array)
    {
        long time = -1;
        try
            time = timeLastModified(directory).stdTime;
        catch (FileException)
        {
        }
        lines ~= "d " ~ directory ~ " " ~ time.to!string;
    }
    return lines;
}

private bool describeRoot(const ref DirectBuild build, out RootSettings settings, out string failure)
{
    import std.array : join;
    import flint_tool.support.process : Launch, capture;

    Launch launch;
    launch.directory = build.root;
    launch.inherit = false;
    foreach (ref variable; build.environment)
    {
        if (variable.name != "DFLAGS" && variable.name != "FLINT_DUB_TRACE")
            launch.environment ~= EnvVar(variable.name, variable.value);
    }
    const outcome = capture([
        build.dub, "describe", "--root=" ~ build.recipeDirectory, "--config=" ~ build.configuration,
        "--compiler=" ~ build.compiler, "--build=plain", "--skip-registry=all",
        "--data=" ~ dataKinds.join(","), "--data-list"
    ], launch);
    if (!outcome.ok)
    {
        failure = outcome.started ? outcome.combined : outcome.failure;
        return false;
    }
    return parseData(outcome.output, settings, failure);
}

/// `dub describe --data-list` output: each kind's values one per line, the kinds separated by an empty line, and
/// an empty kind written as one empty line.
bool parseData(string text, out RootSettings settings, out string failure)
{
    import std.string : lineSplitter;

    string[] lines;
    foreach (line; text.lineSplitter)
        lines ~= line;
    string[][] lists;
    size_t at;
    foreach (kind; 0 .. dataKinds.length)
    {
        if (kind)
        {
            if (at >= lines.length || lines[at].length)
                return unexpected(failure);
            ++at; // the separator
        }
        string[] list;
        if (at < lines.length && lines[at].length == 0)
            ++at; // an empty kind
        else
        {
            while (at < lines.length && lines[at].length)
                list ~= lines[at++];
        }
        lists ~= list;
    }
    if (at != lines.length)
        return unexpected(failure);
    settings.dflags = lists[0];
    settings.versions = lists[1];
    settings.debugVersions = lists[2];
    settings.importPaths = lists[3];
    settings.stringImportPaths = lists[4];
    settings.sources = lists[5];
    settings.linkerFiles = lists[6];
    settings.lflags = lists[7];
    settings.libs = lists[8];
    return settings.sources.length > 0;
}

private bool unexpected(out string failure)
{
    failure = "dub describe gave an unexpected shape";
    return false;
}

/// The settings in `dub describe --data-list` form.
private string dataText(const ref RootSettings settings)
{
    string text;
    foreach (index, list; [
        settings.dflags, settings.versions, settings.debugVersions, settings.importPaths,
        settings.stringImportPaths, settings.sources, settings.linkerFiles, settings.lflags,
        settings.libs
    ])
    {
        if (index)
            text ~= "\n";
        if (list.length == 0)
            text ~= "\n";
        foreach (value; list)
            text ~= value ~ "\n";
    }
    return text;
}

private bool readSettings(string record, string stamp, out RootSettings settings)
{
    import std.string : lineSplitter;
    import flint_tool.support.files : readIfPresent;

    const text = readIfPresent(record);
    string[] lines;
    foreach (line; text.lineSplitter)
        lines ~= line;
    if (lines.length < 3 || lines[0] != directFormat || lines[1] != stamp)
        return false;
    string data;
    string[] expected;
    foreach (line; lines[2 .. $])
    {
        if (line.length > 2 && line[0 .. 2] == "d ")
            expected ~= line;
        else
            data ~= line[1 .. $] ~ "\n"; // "|" guards empty lines
    }
    string failure;
    return parseData(data, settings, failure) && watched(settings.sources) == expected;
}

private void writeSettings(string record, string stamp, const ref RootSettings settings)
{
    import std.conv : to;
    import std.file : rename, write;
    import std.process : thisProcessID;
    import std.string : lineSplitter;

    string text = directFormat ~ "\n" ~ stamp ~ "\n";
    foreach (line; watched(settings.sources))
        text ~= line ~ "\n";
    foreach (line; dataText(settings).lineSplitter)
        text ~= "|" ~ line ~ "\n"; // "|" keeps empty lines apart from the watched ones
    const partial = record ~ "." ~ thisProcessID.to!string ~ ".partial";
    write(partial, text);
    rename(partial, record);
}

/// The artifact is newer than its settings record, every source, every linker file and every file the string
/// import paths hold (config/application.toml), as DUB checks.
private bool upToDate(string artifact, string record, const ref RootSettings settings)
{
    import std.file : FileException, SpanMode, dirEntries, exists, isDir, timeLastModified;

    if (!exists(artifact))
        return false;
    try
    {
        const built = timeLastModified(artifact);
        string[] inputs = settings.sources.dup ~ settings.linkerFiles.dup ~ record;
        foreach (path; settings.stringImportPaths)
        {
            if (!exists(path) || !isDir(path))
                continue;
            foreach (entry; dirEntries(path, SpanMode.depth))
            {
                if (entry.isFile)
                    inputs ~= entry.name;
            }
        }
        foreach (input; inputs)
        {
            if (timeLastModified(input) >= built)
                return false;
        }
    }
    catch (FileException)
        return false;
    return true;
}

private string[] profileFlags(string dflags)
{
    import std.array : split;

    return dflags.split;
}

private EnvVar[] compilerEnvironment(const ref DirectBuild build)
{
    EnvVar[] environment;
    foreach (ref variable; build.environment)
    {
        if (variable.name != "DFLAGS" && variable.name != "FLINT_DUB_TRACE")
            environment ~= EnvVar(variable.name, variable.value);
    }
    return environment;
}

/// One compile of every root source, as DUB runs it: the profile's flags, the recipe's, then versions, paths and
/// `-c -od<objects> -oq`.
private bool compile(const ref DirectBuild build, const ref RootSettings settings, string objects, ref string output)
{
    import std.file : exists, mkdirRecurse, rmdirRecurse;
    import flint_tool.support.process : Launch, capture;

    if (exists(objects))
        rmdirRecurse(objects);
    mkdirRecurse(objects);
    string[] command = [build.compiler] ~ profileFlags(build.dflags) ~ settings.dflags.dup;
    foreach (identifier; settings.versions)
        command ~= "-version=" ~ identifier;
    foreach (identifier; settings.debugVersions)
        command ~= "-debug=" ~ identifier;
    foreach (path; settings.importPaths)
        command ~= "-I" ~ path;
    foreach (path; settings.stringImportPaths)
        command ~= "-J" ~ path;
    command ~= ["-c", "-od" ~ objects, "-oq"] ~ settings.sources.dup;
    Launch launch;
    launch.directory = build.root;
    launch.environment = compilerEnvironment(build);
    launch.inherit = false;
    const outcome = capture(command, launch);
    output ~= outcome.combined;
    return outcome.ok;
}

/// Flags DUB passes to the link: linker flags and the ones the compiler driver uses when it links.
private bool linkFlag(string flag)
{
    import std.algorithm.searching : startsWith;

    return flag.startsWith("-L") || flag.startsWith("-defaultlib=")
        || flag.startsWith("-debuglib=") || flag.startsWith("-Xcc=") || flag == "-g" || flag == "-gc"
        || flag == "-gf" || flag == "-m64" || flag == "-m32";
}

/// The link, as DUB runs it, into a temporary file renamed over the artifact, so a running program keeps its
/// executable.
private bool link(const ref DirectBuild build, const ref RootSettings settings, string objects, ref string output)
{
    import std.algorithm.sorting : sort;
    import std.file : SpanMode, dirEntries, exists, mkdirRecurse, remove, rename;
    import std.path : dirName;
    import flint_tool.support.process : Launch, capture;

    string[] objectFiles;
    foreach (entry; dirEntries(objects, "*.o", SpanMode.shallow))
        objectFiles ~= entry.name;
    sort(objectFiles);
    const partial = build.artifact ~ ".partial";
    mkdirRecurse(dirName(build.artifact));
    string[] command = [build.compiler, "-of" ~ partial] ~ objectFiles ~ settings.linkerFiles.dup ~ "-L--no-as-needed";
    foreach (flag; settings.lflags)
        command ~= "-L" ~ flag;
    foreach (library; settings.libs)
        command ~= "-L-l" ~ library;
    foreach (flag; profileFlags(build.dflags) ~ settings.dflags.dup)
    {
        if (linkFlag(flag))
            command ~= flag;
    }
    Launch launch;
    launch.directory = build.root;
    launch.environment = compilerEnvironment(build);
    launch.inherit = false;
    const outcome = capture(command, launch);
    output ~= outcome.combined;
    if (!outcome.ok)
    {
        if (exists(partial))
            remove(partial);
        return false;
    }
    rename(partial, build.artifact);
    return true;
}

@safe unittest
{
    RootSettings written;
    written.dflags = ["-preview=dip1000"];
    written.versions = ["Have_app", "Have_flint_web"];
    written.importPaths = ["/p/src/", "/h/web/source/"];
    written.sources = ["/p/src/app.d"];
    written.lflags = ["/c/libflint-platform.so", "-rpath=/c"];
    // As DUB prints it: kinds separated by an empty line, an empty kind as one empty line.
    enum text = "-preview=dip1000\n\nHave_app\nHave_flint_web\n\n\n\n/p/src/\n/h/web/source/\n\n\n\n/p/src/app.d\n"
        ~ "\n\n\n/c/libflint-platform.so\n-rpath=/c\n\n\n";
    assert(dataText(written) == text);
    RootSettings settings;
    string failure;
    assert(parseData(text, settings, failure), failure);
    assert(settings.dflags == ["-preview=dip1000"] && settings.versions == [
        "Have_app", "Have_flint_web"
    ]);
    assert(settings.debugVersions.length == 0 && settings.importPaths == [
        "/p/src/", "/h/web/source/"
    ]);
    assert(settings.stringImportPaths.length == 0 && settings.sources == ["/p/src/app.d"]);
    assert(settings.linkerFiles.length == 0 && settings.lflags == [
        "/c/libflint-platform.so", "-rpath=/c"
    ]);
    assert(settings.libs.length == 0);
    assert(!parseData("-g\n\nV\n", settings, failure), "every kind must be present");
    assert(settings.sources.length == 0);
    assert(linkFlag("-L-z") && linkFlag("-defaultlib=libphobos2.so") && linkFlag("-g")
            && !linkFlag("-debug") && !linkFlag("-preview=dip1000") && !linkFlag("-vcolumns"));
}

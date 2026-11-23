/// The DUB recipe flint generates from flint.toml (ADR-021: DUB is an internal backend).
///
/// The recipe lives in `.flint/generated/dub/dub.sdl`, is never committed, and is rewritten only when its
/// content changes, so DUB's up-to-date checks keep working.
module flint_tool.engine.recipe;

import flint_tool.home.policy : Home, profileNames;
import flint_tool.project.manifest : Manifest;
import flint_tool.project.resolve : ResolvedPackage, Resolution;

@safe:

/// Directory of the generated root recipe, relative to the project root.
enum recipeDirectory = ".flint/generated/dub";

/// Inputs of the root recipe that a build computes rather than reads from flint.toml.
struct RecipeExtras
{
    /// Absolute paths of the embedded C objects (engine/cbuild.d).
    string[] objects;
    /// Linker hardening for executables that contain embedded C.
    string[] linkHardening;
    /// Native packages' linker flags: static archives, bundled libraries, system libraries.
    string[] nativeFlags;
    /// Compiler flags that only change how diagnostics read (`-verror-hide`, ADR-027 section 5).
    string[] diagnosticFlags;
    /// `.flint/generated/scan/flint_scan.d` exists: the project has an `@FlintApplication` (ADR-029 section 2).
    bool scanned;
    /// `.flint/generated/aot` holds Flint AOT's modules: the project has a `@FlintBootApplication` (ADR-030).
    bool aot;
    /// Flint AOT's modules for the project's own source and its registry, relative to the recipe, when the rest
    /// build as the AOT library (`aotLibraryDirectory`). Empty: the project compiles every generated module.
    string[] aotOwn;
    /// The core packages come from `.flint/generated/platform`, the platform cache's recipe (ADR-030 section 5).
    bool platform;
    /// The linker flags that link the platform cache's archives.
    string[] platformLflags;
}

/// Render the root recipe for a project.
string renderRecipe(const ref Home home, const ref Manifest manifest, const ref Resolution resolution,
        RecipeExtras extras = RecipeExtras.init)
{
    string text = header() ~ field("name", manifest.name);
    if (manifest.description.length)
        text ~= field("description", manifest.description);
    text ~= field("targetName", manifest.artifactName()) ~ field("targetType", manifest.type) ~ field("sourcePaths",
            "../../../src") ~ field("importPaths", "../../../src") ~ field("dflags", "-preview=dip1000");
    // `@ConditionalOnConfig` reads config/application.toml as a string import (ADR-028 section 1).
    if (hasApplicationConfig(manifest.root))
        text ~= field("stringImportPaths", "../../../config");
    if (extras.scanned)
        text ~= field("sourceFiles", "../scan/flint_scan.d");
    text ~= aotFields(extras);
    if (extras.objects.length)
        text ~= fields("sourceFiles", extras.objects);
    if (extras.objects.length && manifest.type == "executable")
        text ~= fields("lflags", extras.linkHardening);
    if (extras.nativeFlags.length)
        text ~= fields("lflags", dubEscaped(extras.nativeFlags));
    if (extras.diagnosticFlags.length)
        text ~= fields("dflags", dubEscaped(extras.diagnosticFlags));
    if (extras.platformLflags.length)
        text ~= fields("lflags", dubEscaped(extras.platformLflags));
    foreach (name; resolution.direct)
        text ~= dependencyLine(home, resolution, name, "", "../deps/", extras.platform);
    foreach (profile; profileNames)
    {
        if (profile == "test")
            continue;
        text ~= "configuration \"" ~ profile ~ "\" {\n" ~ field("targetPath", "../../build/" ~ profile, "    ") ~ "}\n";
    }
    text ~= "configuration \"unittest\" {\n" ~ field("targetType", "executable", "    ") ~ field("targetName",
            manifest.artifactName() ~ "-test", "    ") ~ field("targetPath", "../../build/test",
            "    ") ~ field("sourcePaths", "../../../test",
            "    ") ~ field("importPaths", "../../../test",
            "    ") ~ "    buildOptions \"unittests\" \"debugInfo\"\n" ~ (manifest.type == "library"
            ? "    dflags \"-main\"\n" : "");
    if (extras.objects.length && manifest.type == "library")
        text ~= fields("lflags", extras.linkHardening, "    ");
    foreach (name; resolution.directTest)
        text ~= dependencyLine(home, resolution, name, "    ", "../deps/", extras.platform);
    return text ~ "}\n";
}

/// Directory of the AOT library's recipe, relative to the project root.
enum aotLibraryDirectory = ".flint/generated/aot-library";
/// DUB name of the AOT library.
enum aotLibraryName = "flint-aot-library";
/// The project's module that imports every module of the AOT library, relative to the root recipe.
enum aotLibraryLink = "../aot-library/flint_aot_library.d";

/// The module that keeps the AOT library's modules in the link. The registry calls their registration functions,
/// but a library DMD archived with `-lib` holds each function in its own member, so only an import pulls a module's
/// `ModuleInfo`, and with it the static constructors of the platform modules it imports. `modules` are D module
/// names.
string renderAotLibraryLink(scope const string[] modules)
{
    string text = "// Generated by flint: keeps the AOT library's modules and their imports in the link.\n"
        ~ "module flint_aot_library;\n";
    foreach (name; modules)
        text ~= "static import " ~ name ~ ";\n";
    return text;
}

/// The AOT library: Flint AOT's modules for modules outside the project's source, such as Boot's auto-configuration.
/// They import no project module and change only when the platform or the closure does, so they build as a library
/// that DUB keeps across edits, and an edit recompiles only the project's own generated modules. `files` are
/// relative to the recipe.
string renderAotLibraryRecipe(const ref Home home, const ref Resolution resolution,
        scope const string[] files, scope const string[] diagnosticFlags, bool platform)
{
    string text = header() ~ field("name", aotLibraryName) ~ field("targetType",
            "library") ~ field("importPaths", "../aot") ~ fields("sourceFiles",
            files) ~ field("dflags", "-preview=dip1000");
    if (diagnosticFlags.length)
        text ~= fields("dflags", dubEscaped(diagnosticFlags));
    foreach (name; resolution.direct)
        text ~= dependencyLine(home, resolution, name, "", "../deps/", platform);
    return text;
}

/// Flint AOT's modules in the root recipe: all of them, or the project's own and the AOT library.
private string aotFields(const ref RecipeExtras extras)
{
    if (!extras.aot)
        return null;
    if (extras.aotOwn.length == 0)
        return field("sourcePaths", "../aot") ~ field("importPaths", "../aot");
    return field("importPaths", "../aot") ~ fields("sourceFiles", extras.aotOwn ~ aotLibraryLink)
        ~ "dependency " ~ quoted(aotLibraryName) ~ " path=" ~ quoted("../aot-library") ~ "\n";
}

/// Whether a project has config/application.toml, which DI's compile-time conditions read.
bool hasApplicationConfig(string root)
{
    import std.file : exists;
    import std.path : buildPath;

    return root.length && exists(buildPath(root, "config", "application.toml"));
}

/// Render the recipe of a path dependency that is a Flint project, with absolute source paths. `platform`: the core
/// packages come from the platform cache's recipe. `directory`, where the recipe is written, makes the source paths
/// relative on Windows (`dependencySourcePath`).
string renderDependencyRecipe(const ref Home home, const ref ResolvedPackage item,
        const ref Resolution resolution, bool platform = false, string directory = null)
{
    import std.path : buildPath;

    const source = dependencySourcePath(buildPath(item.directory, "src"), directory);
    string text = header() ~ field("name", dubName(item.name)) ~ field("targetType",
            "library") ~ field("sourcePaths", source) ~ field("importPaths",
            source) ~ field("dflags", "-preview=dip1000");
    foreach (name; item.dependencies)
        text ~= dependencyLine(home, resolution, name, "", "../", platform);
    return text;
}

/// A dependency's source directory as its recipe names it. DUB 1.43 on Windows asserts ("Cannot append absolute
/// path") on an absolute `sourcePaths` entry, so there the path is relative to the recipe when both are on one
/// drive. Elsewhere it stays absolute.
private string dependencySourcePath(string path, string directory)
{
    version (Windows)
    {
        import std.path : absolutePath, driveName, relativePath;
        import std.uni : sicmp;

        if (directory.length && sicmp(driveName(absolutePath(path)), driveName(absolutePath(directory))) == 0)
            return recipePath(relativePath(absolutePath(path), absolutePath(directory)));
    }
    return recipePath(path);
}

/// Where the joined `flint` recipe is written, relative to the project root (see renderJoinedRoot).
enum joinedRootDirectory = ".flint/generated/flint";

/// Whether the core packages come from more than one checkout: this home and a platform module's checkout
/// (`.flint/platform/<repo>-<commit>`, ADR-023 platform modules). Every repo's recipe is named `flint`, and DUB
/// takes one package of a name, so the build then joins them in one generated recipe.
bool joinsRepos(const ref Home home, const ref Resolution resolution)
{
    foreach (ref item; resolution.packages)
    {
        if (item.kind == "core" && item.repoRoot.length && item.repoRoot != home.root)
            return true;
    }
    return false;
}

/// The joined `flint` recipe: one subpackage per resolved core package, at its directory in its repo's checkout,
/// so `flint:engine-web` from flint-framework and `flint:arena` from this home resolve as one namespace.
/// `directory` is where the recipe is written; DUB takes subpackage paths relative to it. DUB also needs every
/// `flint:` package a listed recipe names in any configuration, such as `flint:framework-test` in a unittest
/// configuration that the build never selects, so those are added from their recipes too.
string renderJoinedRoot(const ref Home home, const ref Resolution resolution, string directory)
{
    import std.algorithm.sorting : sort;
    import std.path : absolutePath, relativePath;

    string[] directories;
    bool[string] listed;
    foreach (ref item; resolution.packages)
    {
        if (item.kind != "core")
            continue;
        listed[item.name] = true;
        directories ~= item.directory;
    }
    string[] extra;
    for (size_t next = 0; next < directories.length; ++next)
    {
        foreach (name; recipeFlintDependencies(directories[next]))
        {
            if ("flint:" ~ name in listed)
                continue;
            listed["flint:" ~ name] = true;
            const meta = knownPackage(home, name);
            if (meta is null)
                continue;
            const located = home.packagePath(meta.repo, meta.directory.length ? meta.directory : "packages/" ~ name);
            directories ~= located;
            extra ~= located;
        }
    }
    string text = header() ~ field("name", "flint") ~ field("targetType", "none");
    const resolved = directories[0 .. directories.length - extra.length];
    sort(extra);
    foreach (path; resolved ~ extra)
        text ~= field("subPackage", recipePath(relativePath(absolutePath(path), absolutePath(directory))));
    return text;
}

/// A core package, starter, Boot library or Spring-layer module by name, or null.
private const(imported!"flint_tool.home.policy".CorePackage)* knownPackage(const ref Home home, string name)
{
    auto found = home.find(name);
    if (found is null)
        found = home.findStarter(name);
    if (found is null)
        found = home.findBoot(name);
    if (found is null)
        found = home.findFramework(name);
    return found;
}

/// The `flint:` packages a package's dub.sdl names, in any configuration.
private string[] recipeFlintDependencies(string packageDirectory)
{
    import std.algorithm.searching : findSplitAfter, findSplitBefore;
    import std.path : buildPath;
    import std.string : lineSplitter, strip;
    import flint_tool.support.files : readIfPresent;

    string[] names;
    foreach (line; readIfPresent(buildPath(packageDirectory, "dub.sdl")).lineSplitter)
    {
        if (auto after = line.strip.findSplitAfter("dependency \"flint:"))
        {
            if (auto name = after[1].findSplitBefore("\""))
                names ~= name[0].idup;
        }
    }
    return names;
}

/// Directory of a path or remote dependency's generated recipe, relative to the project root.
string dependencyRecipeDirectory(string name)
{
    return ".flint/generated/deps/" ~ dubName(name);
}

/// The DUB package name of a dependency: repository paths become `github-com-acme-x` style names.
string dubName(string name)
{
    import std.array : replace;

    return name.replace("/", "-").replace(".", "-").replace("_", "-");
}

/// `dub.selections.json` for the generated root recipe: every DUB package pinned to its checked-out directory,
/// so DUB packages that depend on each other resolve to the compatibility index's versions. A project without DUB
/// packages gets an empty selection: DUB counts a missing file as a change and rebuilds the project every time.
string renderSelections(string root, const ref Resolution resolution)
{
    import std.path : buildPath;

    string versions;
    foreach (ref item; resolution.packages)
    {
        if (item.kind != "dub" && item.kind != "local")
            continue;
        const name = item.kind == "dub" ? item.name[4 .. $] : dubName(item.name);
        const directory = recipePath(buildPath(root, dubPackagesDirectory, workingName(item)));
        versions ~= (versions.length ? ",\n" : "") ~ "\t\t" ~ quoted(name) ~ ": {\"path\": " ~ quoted(directory) ~ "}";
    }
    return "{\n\t\"fileVersion\": 1,\n\t\"versions\": {" ~ (versions.length ? "\n" ~ versions ~ "\n\t" : "") ~ "}\n}\n";
}

/// Where DUB packages are built, relative to the project root. DUB writes build outputs into a package's own
/// directory, so it builds a disposable copy and never the verified cache or the user's checkout.
enum dubPackagesDirectory = ".flint/generated/dub-packages";

/// The working copy's directory name of a DUB package.
string workingName(const ref ResolvedPackage item)
{
    return item.kind == "dub" ? item.name[4 .. $] ~ "-" ~ item.version_ : dubName(item.name);
}

/// Whether a resolved package is built from a generated recipe (a Flint project at a path or a remote module).
bool generatedRecipe(string kind)
{
    return kind == "path" || kind == "remote";
}

/// Paths in generated recipes use `/` on every host. DUB accepts it on Windows, and the recipe text then does not
/// depend on the host's separator.
string recipePath(string path) pure
{
    version (Windows)
    {
        import std.array : replace;

        return path.replace("\\", "/");
    }
    else
        return path;
}

private string header()
{
    return "// Generated by flint from flint.toml. Do not edit: flint rewrites it on every build.\n";
}

/// A dependency line. `siblings` leads from the recipe's directory to the generated dependency recipes:
/// "../deps/" from .flint/generated/dub, "../" from .flint/generated/deps/<name>. `platform`: a core package comes
/// from the platform cache's recipe, `.flint/generated/platform`.
private string dependencyLine(const ref Home home, const ref Resolution resolution, string name,
        string indent, string siblings = "../deps/", bool platform = false)
{
    import std.path : buildPath;

    const item = resolution.find(name);
    if (item is null)
        return null;
    string path;
    if (item.kind == "core" && platform)
        path = siblings ~ "../platform";
    else if (item.kind == "core" && joinsRepos(home, resolution))
        path = siblings ~ "../flint";
    else if (item.kind == "core")
        path = recipePath(item.repoRoot.length ? item.repoRoot : home.root);
    else if (generatedRecipe(item.kind))
        path = siblings ~ dubName(name);
    else
        path = siblings ~ "../dub-packages/" ~ workingName(*item);
    const dependency = item.kind == "core" ? name : item.kind == "dub" ? name[4 .. $] : dubName(name);
    return indent ~ "dependency " ~ quoted(dependency) ~ " path=" ~ quoted(path) ~ "\n";
}

private string field(string key, string value, string indent = "")
{
    return indent ~ key ~ " " ~ quoted(value) ~ "\n";
}

/// DUB expands `$NAME` in recipe fields; `$$` is a literal dollar (the `$ORIGIN` of a run path).
private string[] dubEscaped(scope const(string)[] values)
{
    import std.array : replace;

    string[] escaped;
    foreach (value; values)
        escaped ~= value.replace("$", "$$");
    return escaped;
}

private string fields(string key, scope const(string)[] values, string indent = "")
{
    if (values.length == 0)
        return null;
    string text = indent ~ key;
    foreach (value; values)
        text ~= " " ~ quoted(value);
    return text ~ "\n";
}

/// An SDLang string literal.
string quoted(string value)
{
    string text = "\"";
    foreach (ch; value)
    {
        if (ch == '"' || ch == '\\')
            text ~= '\\';
        text ~= ch;
    }
    return text ~ "\"";
}

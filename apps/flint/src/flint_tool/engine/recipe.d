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
    if (extras.objects.length)
        text ~= fields("sourceFiles", extras.objects);
    if (extras.objects.length && manifest.type == "executable")
        text ~= fields("lflags", extras.linkHardening);
    if (extras.nativeFlags.length)
        text ~= fields("lflags", dubEscaped(extras.nativeFlags));
    if (extras.diagnosticFlags.length)
        text ~= fields("dflags", dubEscaped(extras.diagnosticFlags));
    foreach (name; resolution.direct)
        text ~= dependencyLine(home, resolution, name, "");
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
        text ~= dependencyLine(home, resolution, name, "    ");
    return text ~ "}\n";
}

/// Whether a project has config/application.toml, which DI's compile-time conditions read.
bool hasApplicationConfig(string root)
{
    import std.file : exists;
    import std.path : buildPath;

    return root.length && exists(buildPath(root, "config", "application.toml"));
}

/// Render the recipe of a path dependency that is a Flint project, with absolute source paths.
string renderDependencyRecipe(const ref Home home, const ref ResolvedPackage item, const ref Resolution resolution)
{
    import std.path : buildPath;

    string text = header() ~ field("name", dubName(item.name)) ~ field("targetType",
            "library") ~ field("sourcePaths", recipePath(buildPath(item.directory,
            "src"))) ~ field("importPaths", recipePath(buildPath(item.directory,
            "src"))) ~ field("dflags", "-preview=dip1000");
    foreach (name; item.dependencies)
        text ~= dependencyLine(home, resolution, name, "", "../");
    return text;
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
/// so DUB packages that depend on each other resolve to the compatibility index's versions. Null when there are
/// none.
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
    return versions.length ? "{\n\t\"fileVersion\": 1,\n\t\"versions\": {\n" ~ versions ~ "\n\t}\n}\n" : null;
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
/// "../deps/" from .flint/generated/dub, "../" from .flint/generated/deps/<name>.
private string dependencyLine(const ref Home home, const ref Resolution resolution, string name,
        string indent, string siblings = "../deps/")
{
    import std.path : buildPath;

    const item = resolution.find(name);
    if (item is null)
        return null;
    string path;
    if (item.kind == "core")
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

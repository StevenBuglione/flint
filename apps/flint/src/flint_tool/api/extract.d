/// `flint api extract`: turn an upstream Java source tree into an API manifest (ADR-030, API manifests).
///
/// Which files count:
/// - In a Gradle or Maven tree, only `<module>/src/main/java/**.java`, where the path above `src/main/java` holds
///   no other `src` directory. That leaves out `src/test`, `src/testFixtures`, `src/jmh` and the sample projects
///   that build plugins keep under `src/intTest`. The module is the directory above `src`, or the project for a
///   single-module tree.
/// - In an OpenJDK tree, only `src/<module>/share/classes/**.java`; the module is the JDK module (`java.base`).
///   Platform-specific trees (`unix/classes`), tests and build tools are left out.
/// - In a flat tree (a Maven `-sources.jar`), every `.java` file, all in one module named after the project.
/// - Never a package named `internal`, `module-info.java` or `package-info.java`, or a path under one of the
///   caller's excluded root-relative prefixes. When the caller names included prefixes, only paths under one of
///   them count (an OpenJDK pin lists its modules' exported package roots).
module flint_tool.api.extract;

import flint_tool.api.manifest : ApiType, Manifest;

@safe:

/// What to extract.
struct ExtractRequest
{
    /// Root of the upstream source tree.
    string source;
    /// Upstream project name.
    string project;
    /// Upstream tag.
    string version_;
    /// Root-relative path prefixes to leave out (`buildSrc`, `framework-docs`).
    string[] excludes;
    /// When not empty, only paths under one of these root-relative prefixes count.
    string[] includes;
}

/// How an upstream tree lays out its sources.
enum Layout
{
    /// A Maven `-sources.jar`: one module named after the project.
    flat,
    /// Gradle or Maven: `<module>/src/main/java`.
    gradle,
    /// OpenJDK: `src/<module>/share/classes`.
    jdk,
}

/// A file that did not parse.
struct ExtractProblem
{
    /// Root-relative path.
    string file;
    /// 1-based line.
    size_t line;
    /// What went wrong.
    string message;
}

/// The result of an extraction.
struct Extraction
{
    /// The manifest.
    Manifest manifest;
    /// Java files parsed.
    size_t files;
    /// Files that failed to parse; their types are missing from the manifest.
    ExtractProblem[] problems;
}

/// Extract the API of the tree at `request.source`.
Extraction extract(const ref ExtractRequest request)
{
    import std.algorithm.sorting : sort;
    import std.file : readText;
    import std.path : buildPath;
    import flint_tool.api.java : Unit, parseJava;
    import flint_tool.support.files : findFiles;

    Extraction extraction;
    extraction.manifest.project = request.project;
    extraction.manifest.version_ = request.version_;
    const files = findFiles(request.source, "**/*.java");
    const layout = layoutOf(files);
    foreach (relative; files)
    {
        string module_;
        if (!selected(relative, layout, request, module_))
            continue;
        extraction.files++;
        auto unit = parseJava(readText(buildPath(request.source, relative)));
        if (unit.error.length)
        {
            extraction.problems ~= ExtractProblem(relative, unit.errorLine, unit.error);
            continue;
        }
        foreach (decl; unit.types)
            extraction.manifest.types ~= ApiType(module_, relative, decl);
    }
    alias byId = (a, b) => a.decl.id < b.decl.id || (a.decl.id == b.decl.id && a.module_ < b.module_);
    sort!byId(extraction.manifest.types);
    return extraction;
}

/// The layout of a tree: Gradle when any file lies under `src/main/java`, else OpenJDK when any lies under
/// `src/<module>/share/classes`, else flat.
Layout layoutOf(scope const string[] files)
{
    bool jdk;
    foreach (relative; files)
    {
        string module_;
        if (mainJavaModule(relative, module_))
            return Layout.gradle;
        if (!jdk && jdkModule(relative, module_))
            jdk = true;
    }
    return jdk ? Layout.jdk : Layout.flat;
}

/// Whether `relative` belongs in the manifest, and its module.
bool selected(string relative, Layout layout, const ref ExtractRequest request, out string module_)
{
    import std.path : baseName;

    const name = baseName(relative);
    if (name == "module-info.java" || name == "package-info.java")
        return false;
    foreach (prefix; request.excludes)
    {
        if (under(relative, prefix))
            return false;
    }
    if (request.includes.length && !includedBy(relative, request.includes))
        return false;
    string packagePath;
    final switch (layout)
    {
    case Layout.gradle:
        if (!mainJavaModule(relative, module_))
            return false;
        if (module_.length == 0)
            module_ = request.project;
        packagePath = relative[relative.indexOfMainJava + "src/main/java/".length .. $];
        break;
    case Layout.jdk:
        if (!jdkModule(relative, module_))
            return false;
        packagePath = relative["src/".length + module_.length + "/share/classes/".length .. $];
        break;
    case Layout.flat:
        module_ = request.project;
        packagePath = relative;
        break;
    }
    return !hasComponent(packagePath, "internal");
}

/// The JDK module of a file under `src/<module>/share/classes/`.
bool jdkModule(string relative, out string module_)
{
    import std.algorithm.searching : startsWith;
    import std.string : indexOf;

    if (!relative.startsWith("src/"))
        return false;
    const rest = relative["src/".length .. $];
    const slash = rest.indexOf('/');
    if (slash <= 0 || !rest[slash .. $].startsWith("/share/classes/"))
        return false;
    module_ = rest[0 .. slash];
    return true;
}

private bool includedBy(string relative, scope const string[] includes)
{
    foreach (prefix; includes)
    {
        if (under(relative, prefix))
            return true;
    }
    return false;
}

/// Whether `relative` is `prefix` or lies under it (a trailing `/` on the prefix is ignored).
private bool under(string relative, string prefix)
{
    import std.algorithm.searching : endsWith, startsWith;

    const trimmed = prefix.endsWith("/") ? prefix[0 .. $ - 1] : prefix;
    return relative == trimmed || relative.startsWith(trimmed ~ "/");
}

/// The module of a file under `<module>/src/main/java/`, when no other `src` directory lies above it; empty for
/// the tree's own `src/main/java`.
bool mainJavaModule(string relative, out string module_)
{
    import std.path : baseName;

    const at = relative.indexOfMainJava;
    if (at == size_t.max)
        return false;
    const above = at ? relative[0 .. at - 1] : "";
    if (hasComponent(above, "src"))
        return false;
    module_ = above.length ? baseName(above) : "";
    return true;
}

private size_t indexOfMainJava(string relative)
{
    import std.string : indexOf;

    if (relative.length >= 14 && relative[0 .. 14] == "src/main/java/")
        return 0;
    const at = relative.indexOf("/src/main/java/");
    return at < 0 ? size_t.max : cast(size_t) at + 1;
}

private bool hasComponent(string path, string component)
{
    import std.algorithm.iteration : splitter;

    foreach (part; path.splitter('/'))
    {
        if (part == component)
            return true;
    }
    return false;
}

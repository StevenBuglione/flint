/// Project layout and source safety checks (ADR-021 sections 2 and 5).
///
/// `flint build` runs the fast subset (layout, module paths and safety rules); `flint check` adds the
/// repository rules and the formatter and linter.
module flint_tool.project.layout;

import flint_tool.check.rules : SourceScan, checkAnnotations, checkDefault, checkMixin,
    expectedModule, importLine, privateBoundary, scanSource;
import flint_tool.diagnostics.report : Diagnostic, Report, Severity, at, diagnostic;
import flint_tool.home.policy : Home, startsWithModule;
import flint_tool.project.manifest : Manifest, Waiver;
import flint_tool.project.resolve : Resolution;

@safe:

/// What the checks covered.
struct CheckSummary
{
    /// D sources checked.
    long files;
    /// Diagnostics suppressed by waivers.
    long waived;
    /// Active waivers, as "rule file: reason".
    string[] waivers;
    /// DUB packages used under an `[unchecked]` waiver, as "name version: reason (N findings)".
    string[] unchecked;
    /// REST handlers in src/ (the attributes-per-handler metric, ADR-028 section 3).
    long handlers;
    /// `nothrow`, `@nogc`, `scope`, `pure`, `return` and `@trusted` on those handlers.
    long handlerAttributes;
}

/// Directories allowed at the top of a project.
immutable string[] topLevelDirectories = [
    "src", "test", "config", "resources", "native", ".flint", ".git"
];

/// Run the layout and safety checks. With `full`, also the repository rules (.gitignore).
CheckSummary checkProject(const ref Home home, const ref Manifest manifest, const ref Resolution resolution,
        bool full, ref Report report)
{
    import std.file : exists, isDir, readText;
    import std.path : buildPath;
    import flint_tool.support.files : dSources;

    Report found;
    CheckSummary summary;
    const root = manifest.moduleRoot();
    if (!exists(buildPath(manifest.root, "src", root)) || !isDir(buildPath(manifest.root, "src", root)))
        found.add(at(diagnostic("FLINT-E0404", Severity.error, "src/" ~ root ~ "/ does not exist",
                "create src/" ~ root ~ "/app.d with `module " ~ root ~ ".app;`"), "src/" ~ root, 0));
    foreach (relative; dSources(manifest.root))
    {
        import std.algorithm.searching : startsWith;

        // Vendored modules are checked by hash, not as project sources.
        if (relative.startsWith("vendor/"))
            continue;
        ++summary.files;
        const text = readText(buildPath(manifest.root, relative));
        checkFile(home, manifest, resolution, relative, text, found);
    }
    checkConventions(manifest, summary, found);
    checkPackageDirectories(manifest, found);
    checkImportC(manifest, found);
    checkConfiguration(manifest, found);
    checkGenerated(manifest, found);
    if (full)
        checkIgnored(manifest, found);
    foreach (waiver; manifest.waivers)
        summary.waivers ~= waiver.rule ~ " " ~ waiver.file ~ ": " ~ waiver.reason;
    summary.unchecked = checkDubPackages(manifest, resolution, report);
    foreach (item; found.items)
    {
        if (waived(manifest.waivers, item))
            ++summary.waived;
        else
            report.add(item);
    }
    return summary;
}

/// FLINT-E0530 and FLINT-E0531 over src/, and the attributes-per-handler metric (ADR-028 sections 3 and 5). Class
/// names come from every project source, so a field typed by a class declared in another module is recognised.
private void checkConventions(const ref Manifest manifest, ref CheckSummary summary, ref Report report)
{
    import std.algorithm.searching : startsWith;
    import std.file : readText;
    import std.path : buildPath;
    import flint_tool.check.conventions : HandlerMetric, checkHandlerAttributes, checkNullableFields, declaredClasses;
    import flint_tool.check.lexer : LexFailure, Token, tokenize;
    import flint_tool.support.files : dSources;

    string[] files;
    string[] texts;
    Token[][] scanned;
    bool[string] classes;
    foreach (relative; dSources(manifest.root))
    {
        if (!relative.startsWith("src/"))
            continue;
        Token[] tokens;
        LexFailure failure;
        const text = readText(buildPath(manifest.root, relative));
        if (!tokenize(text, tokens, failure))
            continue;
        foreach (name; declaredClasses(tokens))
            classes[name] = true;
        files ~= relative;
        texts ~= text;
        scanned ~= tokens;
    }
    const starters = usesStarter(manifest);
    HandlerMetric metric;
    foreach (index, file; files)
    {
        checkNullableFields(file, texts[index], scanned[index], classes, report);
        Report attributes;
        checkHandlerAttributes(file, texts[index], scanned[index], metric, attributes);
        if (starters)
            foreach (item; attributes.items)
                report.add(item);
    }
    summary.handlers = metric.handlers;
    summary.handlerAttributes = metric.attributes;
}

private bool usesStarter(const ref Manifest manifest)
{
    import std.algorithm.searching : startsWith;

    // The pre-port starters, by either name (they are flint:legacy-starter-* after the repo split's cutover).
    foreach (ref dependency; manifest.dependencies)
    {
        if (dependency.name.startsWith("flint:starter-") || dependency.name.startsWith("flint:legacy-starter-"))
            return true;
    }
    return false;
}

/// A DUB package that fails Flint's safety rules builds only under an `[unchecked]` waiver naming it with a reason
/// (FLINT-E0316 otherwise). Returns the active waivers, which every build prints and records.
private string[] checkDubPackages(const ref Manifest manifest, const ref Resolution resolution, ref Report report)
{
    import std.array : join;
    import std.conv : to;

    string[] active;
    foreach (ref item; resolution.packages)
    {
        if ((item.kind != "dub" && item.kind != "local") || item.safetyFindings == 0)
            continue;
        const reason = uncheckedReason(manifest, item.name);
        const label = item.name ~ (item.version_.length ? " " ~ item.version_ : "");
        const findings = item.safetyFindings.to!string ~ (item.safetyFindings == 1 ? " finding" : " findings");
        if (reason.length)
        {
            active ~= label ~ ": " ~ reason ~ " (" ~ findings ~ ")";
            continue;
        }
        report.add(at(diagnostic("FLINT-E0316", Severity.error,
                label ~ " fails Flint's safety checks (" ~ findings ~ "; first: " ~ item.safetySample.join("; ") ~ ")",
                "[unchecked]\n\"" ~ item.name ~ "\" = \"<why it " ~ "is used anyway>\""), "flint.toml", 0));
    }
    return active;
}

private string uncheckedReason(const ref Manifest manifest, string name)
{
    foreach (ref waiver; manifest.unchecked)
    {
        if (waiver.name == name || "dub:" ~ waiver.name == name)
            return waiver.reason;
    }
    return null;
}

private bool waived(scope const Waiver[] waivers, const ref Diagnostic item)
{
    foreach (ref waiver; waivers)
    {
        if (waiver.rule == item.code && waiver.file == item.file)
            return true;
    }
    return false;
}

private void checkFile(const ref Home home, const ref Manifest manifest, const ref Resolution resolution,
        string relative, string text, ref Report report)
{
    import std.algorithm.searching : startsWith;

    const root = manifest.moduleRoot();
    const inSource = relative.startsWith("src/");
    const inTest = relative.startsWith("test/");
    if (!inSource && !inTest)
    {
        report.add(at(diagnostic("FLINT-E0404", Severity.error, relative ~ " is outside src/ and test/",
                "move it below src/" ~ root ~ "/ or test/" ~ root ~ "/"), relative, 0));
        return;
    }
    SourceScan scan;
    if (!scanSource(relative, text, scan, report))
        return;
    const below = relative[(inSource ? "src/" : "test/").length .. $];
    const expected = expectedModule(below);
    if (!startsWithModule(expected, root))
        report.add(at(diagnostic("FLINT-E0403", Severity.error,
                relative ~ " is outside " ~ (inSource ? "src/" : "test/") ~ root ~ "/",
                "move it below " ~ (inSource ? "src/" : "test/") ~ root ~ "/"), relative, 1, 0, text));
    else if (scan.moduleName != expected)
        report.add(at(diagnostic("FLINT-E0401", Severity.error,
                "declares `module " ~ scan.moduleName ~ ";` but its path names `" ~ expected ~ "`",
                "declare `module " ~ expected ~ ";` or move the file"), relative, scan.tokens[0].line, 0, text));
    const low = startsWithModule(scan.moduleName, root ~ ".sys") || startsWithModule(scan.moduleName, root ~ ".ffi");
    checkDefault(scan, low, report);
    checkForeign(scan, low, root, report);
    checkMixin(scan, [], report);
    checkAnnotations(scan, low, home.safety.maxTrustedLines, report);
    foreach (imported; scan.imports)
        checkImport(home, manifest, resolution, scan, imported, inTest, report);
}

private void checkImport(const ref Home home, const ref Manifest manifest, const ref Resolution resolution,
        const ref SourceScan scan, string imported, bool test, ref Report report)
{
    const line = importLine(scan, imported);
    if (startsWithModule(imported, "flint"))
    {
        auto owner = home.owner(imported);
        if (owner is null)
        {
            report.add(at(diagnostic("FLINT-E0510", Severity.error, "unknown Flint module " ~ imported,
                    "import a module a core package owns"), scan.file, line, 0, scan.text));
            return;
        }
        // Until the pre-port Boot retires, flint.boot has two owners (boot-core and the legacy boot library, as
        // tools/gates.py boot_owners): an import is declared through either.
        foreach (ref library; home.bootLibraries)
        {
            if ((imported == library.module_ || startsWithModule(imported, library.module_))
                    && declared(resolution, "flint:" ~ library.name, test))
            {
                owner = &library;
                break;
            }
        }
        const name = "flint:" ~ owner.name;
        if (!declared(resolution, name, test))
            report.add(at(diagnostic("FLINT-E0507", Severity.error,
                    "imports " ~ imported ~ " but `" ~ name ~ "` is not a direct " ~ (test
                    ? "build or test " : "") ~ "dependency",
                    "add `\"" ~ name ~ "\" = {}` under [" ~ (test ? "test-dependencies" : "dependencies") ~ "]"),
                    scan.file, line, 0, scan.text));
        else if (privateBoundary(owner.module_, imported))
            report.add(at(diagnostic("FLINT-E0508", Severity.error, "imports the private module " ~ imported,
                    "import " ~ owner.module_ ~ " instead"), scan.file, line, 0, scan.text));
        return;
    }
    foreach (ref item; resolution.packages)
    {
        if ((item.kind != "path" && item.kind != "remote") || item.moduleRoot.length == 0
                || !startsWithModule(imported, item.moduleRoot))
            continue;
        if (!declared(resolution, item.name, test))
            report.add(at(diagnostic("FLINT-E0507", Severity.error,
                    "imports " ~ imported ~ " but `" ~ item.name ~ "` is not a direct dependency", pathFix(item.name)),
                    scan.file, line, 0, scan.text));
        else if (privateBoundary(item.moduleRoot, imported))
            report.add(at(diagnostic("FLINT-E0508", Severity.error, "imports the private module " ~ imported,
                    "import " ~ item.moduleRoot ~ "'s public modules"), scan.file, line, 0, scan.text));
        return;
    }
}

/// C is reached only through `<root>.ffi` (and `<root>.sys`) modules: foreign linkage elsewhere is FLINT-E0513.
private void checkForeign(const ref SourceScan scan, bool low, string root, ref Report report)
{
    static immutable string[] foreign = ["C", "C++", "System", "Windows", "Objective"];
    if (low)
        return;
    const tokens = scan.tokens;
    foreach (i; 2 .. tokens.length)
    {
        if (tokens[i - 2].value != "extern" || tokens[i - 1].value != "(")
            continue;
        foreach (linkage; foreign)
        {
            if (tokens[i].value == linkage || (linkage == "C++" && tokens[i].value == "C"
                    && i + 1 < tokens.length && tokens[i + 1].value == "++"))
            {
                report.add(at(diagnostic("FLINT-E0513", Severity.error, "extern(" ~ linkage ~ ") outside an ffi module",
                        "declare C functions in " ~ root ~ ".ffi.<name> and give the rest of the program a safe D API"),
                        scan.file, tokens[i].line, 0, scan.text));
                return;
            }
        }
    }
}

/// ImportC files under src/ or test/ would let any module import C directly; C lives in native/.
private void checkImportC(const ref Manifest manifest, ref Report report)
{
    import std.path : extension;
    import flint_tool.support.files : findFiles;

    foreach (directory; ["src", "test"])
    {
        foreach (relative; findFiles(manifest.root, directory ~ "/**"))
        {
            const ext = extension(relative);
            if (ext == ".c" || ext == ".h" || ext == ".i")
                report.add(at(diagnostic("FLINT-E0513", Severity.error, relative ~ " puts C among the D sources",
                        "move it to native/ and declare its functions in " ~ manifest.moduleRoot() ~ ".ffi"),
                        relative, 0));
        }
    }
}

private string pathFix(string name)
{
    return "add `" ~ name ~ " = { path = \"...\" }` under [dependencies]";
}

/// Whether `name` is among the dependencies a direct starter brings, transitively through other starters: a
/// starter is a dependency bundle, so its packages are the application's to import (ADR-029 section 8).
private bool throughStarter(const ref Resolution resolution, string direct, string name)
{
    import std.algorithm.searching : startsWith;

    // Every starter is a bundle: the pre-port ones under either name, and Spring Boot's flint:boot-starter-*.
    if (!direct.startsWith("flint:starter") && !direct.startsWith("flint:legacy-starter")
            && !direct.startsWith("flint:boot-starter"))
        return false;
    foreach (ref item; resolution.packages)
    {
        if (item.name != direct)
            continue;
        foreach (dependency; item.dependencies)
        {
            if (dependency == name || throughStarter(resolution, dependency, name))
                return true;
        }
    }
    return false;
}

private bool declared(const ref Resolution resolution, string name, bool test)
{
    foreach (direct; resolution.direct)
    {
        if (direct == name || throughStarter(resolution, direct, name))
            return true;
    }
    if (test)
    {
        foreach (direct; resolution.directTest)
        {
            if (direct == name)
                return true;
        }
    }
    return false;
}

private void checkPackageDirectories(const ref Manifest manifest, ref Report report)
{
    import std.file : exists, isDir;
    import std.path : buildPath, stripExtension;
    import flint_tool.support.files : dSources;

    foreach (relative; dSources(manifest.root))
    {
        const directory = stripExtension(relative);
        if (exists(buildPath(manifest.root, directory)) && isDir(buildPath(manifest.root, directory)))
            report.add(at(diagnostic("FLINT-E0406", Severity.error, relative ~ " and " ~ directory ~ "/ both exist",
                    "move " ~ relative ~ " to " ~ directory ~ "/package.d"), relative, 0));
    }
}

private void checkConfiguration(const ref Manifest manifest, ref Report report)
{
    import std.file : exists, isDir;
    import std.path : buildPath;
    import std.regex : ctRegex, matchFirst;
    import flint.serde.owned : readTomlEntries;
    import flint_tool.diagnostics.report : positionOf;
    import flint_tool.support.files : findFiles, readIfPresent;

    const directory = buildPath(manifest.root, "config");
    if (!exists(directory) || !isDir(directory))
        return;
    enum pattern = ctRegex!`^application(-[a-z0-9_-]{1,32})?\.toml$`;
    foreach (relative; findFiles(directory, "**"))
    {
        const display = "config/" ~ relative;
        if (matchFirst(relative, pattern).empty)
        {
            report.add(at(diagnostic("FLINT-E0407", Severity.error, display ~ configurationProblem(relative),
                    "use config/application.toml and config/application-<profile>.toml"), display, 0));
            continue;
        }
        const text = readIfPresent(buildPath(directory, relative));
        const parsed = readTomlEntries(text);
        if (!parsed.ok)
        {
            const where = positionOf(text, parsed.error.offset);
            report.add(at(diagnostic("FLINT-E0407", Severity.error,
                    display ~ " is not valid TOML: " ~ parsed.error.message, "fix the TOML syntax"),
                    display, where.line, where.column, text));
        }
    }
}

private string configurationProblem(string relative)
{
    import std.algorithm.searching : endsWith;

    if (relative.endsWith(".yaml") || relative.endsWith(".yml"))
        return ": YAML configuration is not offered; its implicit typing is ambiguous";
    if (relative.endsWith(".json"))
        return ": Flint projects configure in TOML only";
    return " does not follow the configuration convention";
}

private void checkGenerated(const ref Manifest manifest, ref Report report)
{
    import std.file : exists, isDir;
    import std.path : buildPath;

    foreach (candidate; ["generated", "src/generated", "src/" ~ manifest.moduleRoot() ~ "/generated"])
    {
        const path = buildPath(manifest.root, candidate);
        if (exists(path) && isDir(path))
            report.add(at(diagnostic("FLINT-E0408", Severity.error,
                    candidate ~ "/ holds generated code outside .flint/generated",
                    "generate into .flint/generated/ and delete " ~ candidate ~ "/"), candidate, 0));
    }
}

private void checkIgnored(const ref Manifest manifest, ref Report report)
{
    import std.algorithm.searching : canFind;
    import std.path : buildPath;
    import std.string : lineSplitter, strip;
    import flint_tool.support.files : readIfPresent;

    const text = readIfPresent(buildPath(manifest.root, ".gitignore"));
    bool listed;
    foreach (line; text.lineSplitter)
    {
        const entry = line.strip;
        listed = listed || entry == ".flint" || entry == ".flint/" || entry == "/.flint" || entry == "/.flint/";
    }
    if (!listed)
        report.add(at(diagnostic("FLINT-E0409", Severity.error, ".gitignore does not list .flint/",
                "echo .flint/ >> .gitignore"), ".gitignore", 0));
}

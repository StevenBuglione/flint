/// The Flint workspace's structural gate, ported from tools/gates.py `--gate structural`.
///
/// Verdicts match tools/gates.py: the same rules, applied to the same files, in the same order. Unlike the
/// Python gate, flint reports every violation instead of stopping at the first.
module flint_tool.check.structural;

import flint_tool.check.lexer : DependencyEdge, LexFailure, Token, compilerDependencyEdges, importedModules, tokenize;
import flint_tool.check.rules : SourceScan, checkAnnotations, checkDefault, checkMixin,
    checkThreadLocals, checkWorkspaceImport, expectedModule, importLine, scanSource;
import flint_tool.diagnostics.report : Report, Severity, at, diagnostic;
import flint_tool.home.policy : Home, matchesAny;

@safe:

/// The gate's JSON result, identical in shape to tools/gates.py's.
struct StructuralSummary
{
    /// Packages whose sources were checked.
    long packages;
    /// Nodes of the policy graph.
    long graph_nodes;
    /// The compiler dependency audit.
    GeneratedSummary generated_dependencies;
    /// The repo the gate was restricted to, or empty (plan section 7).
    string repo;
    /// Cross-repo dependencies pending a decision in policy/repos.json.
    string[] pending_repo_edges;
}

/// Compiler dependency audit counts.
struct GeneratedSummary
{
    /// Packages with approved string mixins.
    long packages;
    /// Compiles audited (two profiles per package).
    long compiler_profiles;
}

/// Run the structural gate over `selected` packages (all when empty). With `fast`, skip the compiler
/// dependency audit: that is the subset `flint build` and `flint test` run before every workspace build.
StructuralSummary structuralGate(const ref Home home, scope const(string)[] selected, string dmd,
        ref Report report, bool fast = false)
{
    import std.path : buildPath;

    StructuralSummary summary;
    summary.graph_nodes = cast(long) home.packages.length;
    checkGraph(home, report);
    checkRootRecipe(home, report);
    checkBootLayers(home, report);
    imported!"flint_tool.check.registration".checkRegistration(home, report);
    summary.pending_repo_edges = checkRepoEdges(home, report);
    if (!fast)
        checkPlatformOutputs(home, report);
    string[] names;
    foreach (ref item; home.packages)
    {
        bool wanted = selected.length == 0;
        foreach (name; selected)
            wanted = wanted || name == item.name;
        if (wanted)
            names ~= item.name;
    }
    summary.packages = cast(long) names.length;
    string[] mixinPackages;
    foreach (name; names)
    {
        if (checkPackage(home, name, report))
            mixinPackages ~= name;
    }
    if (!fast)
        summary.generated_dependencies = generatedDependencies(home, mixinPackages, dmd, report);
    return summary;
}

private void checkGraph(const ref Home home, ref Report report)
{
    bool[string] visited;
    bool[string] active;
    bool[string] reported;
    void visit(string name)
    {
        if (name in active)
        {
            if (name !in reported)
                report.error("FLINT-E0521", "dependency cycle at " ~ name,
                        "remove one edge of the cycle in policy/packages.json");
            reported[name] = true;
            return;
        }
        if (name in visited)
            return;
        active[name] = true;
        const meta = home.find(name);
        foreach (dependency; meta.dependencies)
        {
            const target = home.find(dependency);
            if (target is null)
            {
                report.error("FLINT-E0525", "unknown dependency " ~ dependency,
                        "name a package from policy/packages.json");
                continue;
            }
            if (target.tier > meta.tier)
                report.error("FLINT-E0522", "higher-tier import " ~ name ~ " -> " ~ dependency,
                        "move the shared code down a tier");
            if (meta.tier == 4 && (target.tier == 2 || target.tier == 3))
                report.error("FLINT-E0523", "CLI/web-data isolation", name ~ " may not depend on " ~ dependency);
            visit(dependency);
        }
        active.remove(name);
        visited[name] = true;
    }

    foreach (ref item; home.packages)
        visit(item.name);
}

/// Plan section 7: a package depends only on its own repo and the repos policy/repos.json allows it
/// (FLINT-E0532). Returns the pending edges, which the policy lists with a reason and which do not fail.
private string[] checkRepoEdges(const ref Home home, ref Report report)
{
    if (home.repos.length == 0)
        return null;
    string[] pending;
    void check(const ref imported!"flint_tool.home.policy".CorePackage item)
    {
        const source = repoOf(home, item.repo);
        if (source is null)
        {
            report.add(at(diagnostic("FLINT-E0532", Severity.error,
                    item.name ~ ": repo `" ~ item.repo ~ "` is not in policy/repos.json",
                    "add the repo, or move the package to a listed one"), "policy/repos.json", 0));
            return;
        }
        foreach (name; item.dependencies)
        {
            auto target = home.find(name);
            if (target is null)
                target = home.findBoot(name);
            if (target is null)
                target = home.findStarter(name);
            if (target is null || target.repo == item.repo || allowed(*source, target.repo))
                continue;
            const message = item.name ~ " (" ~ item.repo ~ ") -> " ~ name ~ " (" ~ target.repo ~ "): "
                ~ item.repo ~ " may not depend on " ~ target.repo;
            if (isPending(home, item.name, name))
                pending ~= message;
            else
                report.add(at(diagnostic("FLINT-E0532", Severity.error, message,
                        "dependencies point portfolio -> boot -> framework -> flint; move the code down"),
                        "policy/repos.json", 0));
        }
    }

    foreach (ref item; home.packages)
        check(item);
    foreach (ref item; home.bootLibraries)
        check(item);
    foreach (ref item; home.starters)
        check(item);
    checkAppEdges(home, report);
    import std.algorithm.sorting : sort;

    sort(pending);
    return pending;
}

/// The bill of materials and the lock partitions are current (FLINT-E0534), as tools/gates.py platform_outputs.
private void checkPlatformOutputs(const ref Home home, ref Report report)
{
    import flint_tool.check.platform : platformOutputProblems;

    foreach (problem; platformOutputProblems(home))
        report.add(at(diagnostic("FLINT-E0534", Severity.error, problem,
                "python3 tools/platform_modules.py --write"), "platform.lock", 0));
}

/// An application's flint:* dependencies follow the same edges, from its repo in policy/apps.json.
private void checkAppEdges(const ref Home home, ref Report report)
{
    import std.algorithm.searching : startsWith;
    import std.file : exists;
    import std.path : buildPath;
    import flint_tool.project.manifest : Manifest, parseManifest;

    foreach (name, app; home.apps)
    {
        const directory = buildPath(home.root, app[1]);
        const source = repoOf(home, app[0]);
        Manifest manifest;
        Report ignored;
        if (source is null || !exists(buildPath(directory, "flint.toml"))
                || !parseManifest(directory, home, manifest, ignored))
            continue;
        foreach (ref dependency; manifest.dependencies ~ manifest.testDependencies)
        {
            if (!dependency.name.startsWith("flint:"))
                continue;
            const target = home.find(dependency.name[6 .. $]);
            if (target is null || target.repo == app[0] || allowed(*source, target.repo))
                continue;
            report.add(at(diagnostic("FLINT-E0532", Severity.error,
                    "app " ~ name ~ " (" ~ app[0] ~ ") -> " ~ dependency.name[6 .. $] ~ " ("
                    ~ target.repo ~ "): " ~ app[0] ~ " may not depend on " ~ target.repo,
                    "move the app to a repo that may depend on it in policy/apps.json"), "policy/apps.json", 0));
        }
    }
}

private const(imported!"flint_tool.home.policy".RepoPolicy)* repoOf(const ref Home home, string name)
{
    foreach (ref repo; home.repos)
    {
        if (repo.name == name)
            return &repo;
    }
    return null;
}

private bool allowed(const ref imported!"flint_tool.home.policy".RepoPolicy source, string target)
{
    foreach (name; source.mayDependOn)
    {
        if (name == target)
            return true;
    }
    return false;
}

private bool isPending(const ref Home home, string from, string to)
{
    foreach (ref edge; home.pendingEdges)
    {
        if (edge.from == from && edge.to == to)
            return true;
    }
    return false;
}

/// ADR-029 section 8: a starter holds no D source outside its example (FLINT-E0528), and a Flint Boot library
/// imports only the packages and Boot libraries policy/boot.json declares for it (FLINT-E0529).
private void checkBootLayers(const ref Home home, ref Report report)
{
    import std.algorithm.searching : startsWith;
    import std.path : buildPath;
    import flint_tool.check.rules : SourceScan, scanSource;
    import flint_tool.support.files : findFiles, readIfPresent, relativeTo;

    foreach (ref starter; home.starters)
    {
        const base = home.packagePath(starter.repo, starter.directory);
        foreach (file; findFiles(base, "**/*.d"))
        {
            if (file.startsWith("example/"))
                continue;
            report.add(at(diagnostic("FLINT-E0528", Severity.error, starter.name ~ ": a starter has no D source",
                    "move the code to a framework library or a Flint Boot library; a starter lists dependencies"),
                    relativeTo(buildPath(base, file), home.root), 0));
        }
    }
    foreach (ref library; home.bootLibraries)
    {
        const base = buildPath(home.packagePath(library.repo, library.directory), "source");
        foreach (file; findFiles(base, "**/*.d"))
        {
            SourceScan scan;
            Report ignored;
            const path = buildPath(base, file);
            if (!scanSource(relativeTo(path, home.root), readIfPresent(path), scan, ignored))
                continue;
            foreach (imported; scan.imports)
            {
                const owners = bootOwners(home, imported);
                bool declared = owners.length == 0;
                foreach (owner; owners)
                    declared = declared || owner == library.name || declaredIn(library, owner);
                if (declared)
                    continue;
                report.add(at(diagnostic("FLINT-E0529", Severity.error,
                        library.name ~ ": undeclared Boot-layer import " ~ imported, "declare flint:" ~ owners[0]
                        ~ " for it in policy/boot.json and its dub.sdl, keeping framework -> boot -> autoconfigure"),
                        scan.file, 0));
            }
        }
    }
}

/// The packages that own `module_`, as tools/gates.py boot_owners: every Boot library whose module root it is
/// under (until the pre-ADR-030 library retires, flint.boot has two, boot and boot-core), else the core owner.
private string[] bootOwners(const ref Home home, string module_)
{
    import std.algorithm.searching : startsWith;

    string[] found;
    foreach (ref library; home.bootLibraries)
    {
        if (module_ == library.module_ || module_.startsWith(library.module_ ~ "."))
            found ~= library.name;
    }
    if (found.length == 0)
        if (auto dependency = home.owner(module_))
            found ~= dependency.name;
    return found;
}

private bool declaredIn(const ref imported!"flint_tool.home.policy".CorePackage library, string name)
{
    foreach (dependency; library.dependencies)
    {
        if (dependency == name)
            return true;
    }
    return false;
}

private void checkRootRecipe(const ref Home home, ref Report report)
{
    import std.path : buildPath;
    import std.regex : matchAll, regex;
    import flint_tool.support.files : readIfPresent;

    const text = readIfPresent(buildPath(home.root, "dub.sdl"));
    bool[string] listed;
    foreach (match; matchAll(text, regex(`subPackage\s+"packages/([\w-]+)"`)))
        listed[match[1].idup] = true;
    // The packages of the repos that live in this home (all of them before the cutover, flint's after).
    size_t expected;
    bool same = true;
    foreach (ref item; home.packages)
    {
        if (!home.inHome(item.repo))
            continue;
        ++expected;
        same = same && (item.name in listed) !is null;
    }
    if (!same || listed.length != expected)
        report.add(at(diagnostic("FLINT-E0524", Severity.error, "root subpackage list differs",
                "list every package of policy/packages.json in this home's repos as subPackage \"packages/<name>\""),
                "dub.sdl", 0));
}

/// Check one package's recipe and sources. Returns true when it contains approved string mixins.
private bool checkPackage(const ref Home home, string name, ref Report report)
{
    import std.algorithm.sorting : sort;
    import std.path : buildPath;
    import std.regex : matchAll, regex;
    import flint_tool.support.files : findFiles, readIfPresent;

    const meta = home.find(name);
    const directory = home.packagePath(meta.repo, buildPath("packages", name));
    const recipePath = "packages/" ~ name ~ "/dub.sdl";
    const recipe = readIfPresent(buildPath(directory, "dub.sdl"));
    bool[string] declared;
    foreach (match; matchAll(recipe, regex(`dependency\s+"flint:([\w-]+)"\s+version="\*"`)))
        declared[match[1].idup] = true;
    bool same = declared.length == meta.dependencies.length;
    foreach (dependency; meta.dependencies)
        same = same && (dependency in declared) !is null;
    if (!same)
        report.add(at(diagnostic("FLINT-E0525", Severity.error, name ~ ": SDL dependencies differ from policy",
                "declare exactly the dependencies policy/packages.json lists"), recipePath, 0));
    size_t dependencyWords;
    foreach (match; matchAll(recipe, regex(`\bdependency\b`)))
        ++dependencyWords;
    if (dependencyWords != declared.length)
        report.add(at(diagnostic("FLINT-E0526", Severity.error, name ~ ": noncanonical dependency recipe",
                "declare Flint dependencies only, as dependency \"flint:<name>\" version=\"*\""), recipePath, 0));

    const sourceRoot = buildPath(directory, "source");
    const lowPrefixes = name in home.safety.unsafePrefixes ? home.safety.unsafePrefixes[name] : null;
    bool mixins;
    auto files = findFiles(sourceRoot, "**/*.d");
    sort(files);
    foreach (relative; files)
    {
        import std.file : readText;

        const display = "packages/" ~ name ~ "/source/" ~ relative;
        SourceScan scan;
        if (!scanSource(display, readText(buildPath(sourceRoot, relative)), scan, report))
            continue;
        if (scan.moduleName != expectedModule(relative))
            report.add(at(diagnostic("FLINT-E0401", Severity.error,
                    "module/path mismatch: declares " ~ scan.moduleName ~ ", path names " ~ expectedModule(relative),
                    "declare `module " ~ expectedModule(relative) ~ ";` or move the file"), display, 1, 0, scan.text));
        const owner = home.owner(scan.moduleName);
        if (owner is null || owner.name != name)
            report.add(at(diagnostic("FLINT-E0410", Severity.error, "source belongs to another package",
                    "modules of " ~ name ~ " live below " ~ meta.module_), display, 1, 0, scan.text));
        const low = matchesAny(scan.moduleName, lowPrefixes);
        checkDefault(scan, low, report);
        if (scan.stringMixin && matchesAny(scan.moduleName, home.safety.generatorPrefixes))
            mixins = true;
        checkMixin(scan, home.safety.generatorPrefixes, report);
        foreach (imported; scan.imports)
            checkWorkspaceImport(home, name, imported, display, display, importLine(scan,
                    imported), scan.text, report);
        checkAnnotations(scan, low, home.safety.maxTrustedLines, report);
        checkThreadLocals(scan, home.safety.threadLocalAllowlist, report);
    }
    return mixins;
}

/// Compile every approved generator package with DMD -deps and -mixin, then audit expansions and edges.
private GeneratedSummary generatedDependencies(const ref Home home, scope const(string)[] packages,
        string dmd, ref Report report)
{
    import std.algorithm.sorting : sort;
    import std.file : exists, mkdirRecurse, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import flint_tool.support.files : findFiles;

    GeneratedSummary summary;
    summary.packages = cast(long) packages.length;
    if (packages.length == 0)
        return summary;
    if (dmd.length == 0 || !exists(dmd))
    {
        report.error("FLINT-E0802", "approved string mixins require the pinned DMD for the compiler dependency audit",
                "flint toolchain install");
        return summary;
    }
    string[] imports;
    foreach (ref item; home.packages)
        imports ~= "-I" ~ buildPath(home.packagePath(item.repo, buildPath("packages", item.name)), "source");
    const temporary = buildPath(tempDir(), "flint-deps-" ~ randomUUID().toString());
    mkdirRecurse(temporary);
    scope (exit)
        rmdirRecurse(temporary);
    auto sorted = packages.dup;
    sort(sorted);
    foreach (name; sorted)
    {
        const sourceRoot = buildPath(home.packagePath(home.find(name).repo, buildPath("packages", name)), "source");
        auto files = findFiles(sourceRoot, "**/*.d");
        sort(files);
        string[] sources;
        foreach (relative; files)
            sources ~= buildPath(sourceRoot, relative);
        foreach (profile; ["debug", "release"])
        {
            if (auditProfile(home, name, profile, sources, imports, temporary, dmd, report))
                ++summary.compiler_profiles;
        }
    }
    return summary;
}

/// Compile one generator package in one profile and audit its expansion and compiler edges.
private bool auditProfile(const ref Home home, string name, string profile, scope const(string)[] sources,
        scope const(string)[] imports, string temporary, string dmd, ref Report report)
{
    import std.file : exists, getSize, readText;
    import std.path : buildPath;
    import flint_tool.support.process : Launch, capture;

    const destination = buildPath(temporary, name ~ "-" ~ profile ~ ".deps");
    const expansion = buildPath(temporary, name ~ "-" ~ profile ~ ".mixins.d");
    const command = [
        dmd, "-o-", "-unittest", "-preview=dip1000", "-" ~ profile, "-deps=" ~ destination,
        "-mixin=" ~ expansion
    ] ~ imports ~ sources;
    Launch launch;
    launch.directory = home.root;
    const outcome = capture(command, launch);
    const where = "packages/" ~ name;
    bool failed(string code, string message, string fix)
    {
        report.add(at(diagnostic(code, Severity.error, message, fix), where, 0));
        return false;
    }

    if (!outcome.ok)
        return failed("FLINT-E0527", "generated dependency compile failed: " ~ outcome.failure ~ outcome.combined(),
                "fix the compile errors above");
    if (!exists(destination))
        return failed("FLINT-E0527", "compiler did not produce a dependency receipt", "check the pinned DMD");
    if (!exists(expansion) || getSize(expansion) == 0)
        return failed("FLINT-E0527", "string mixin has no instantiated expansion; add a positive unittest fixture",
                "add a unittest that instantiates the generator");
    Token[] expanded;
    LexFailure failure;
    if (!projectMixinTokens(readText(expansion), dmd, home.root, expanded, failure))
        return failed("FLINT-E0511", failure.message, "generate checked code");
    if (expanded.length == 0)
        return failed("FLINT-E0527", "string mixin has no audited application expansion",
                "add a unittest that instantiates the generator");
    auditExpansion(expanded, where, report);
    DependencyEdge[] edges;
    if (!compilerDependencyEdges(readText(destination), edges, failure))
        return failed("FLINT-E0527", failure.message, "check the pinned DMD");
    foreach (edge; edges)
    {
        const owner = home.owner(edge.importing);
        if (owner !is null)
            checkWorkspaceImport(home, owner.name, edge.imported,
                    "compiler-generated " ~ edge.importing, where, 0, null, report);
    }
    return true;
}

/// Mixin expansions contain neither import declarations nor unsafe annotations.
private void auditExpansion(scope const Token[] expanded, string where, ref Report report)
{
    string[] generatedImports;
    LexFailure failure;
    if (!importedModules(expanded, generatedImports, failure) || generatedImports.length)
        report.add(at(diagnostic("FLINT-E0511", Severity.error,
                "generated import statements are prohibited", "generate data, not imports"), where, 0));
    foreach (i; 1 .. expanded.length)
    {
        if (expanded[i - 1].value == "@" && (expanded[i].value == "trusted" || expanded[i].value == "system"))
        {
            report.add(at(diagnostic("FLINT-E0511", Severity.error, "generated unsafe annotations are prohibited",
                    "keep @trusted code in handwritten sys/ modules"), where, 0));
            return;
        }
    }
}

/// Tokens of a -mixin dump, skipping expansions located in the bundled compiler's druntime and Phobos sources.
bool projectMixinTokens(string text, string compiler, string root, out Token[] tokens, out LexFailure failure)
{
    import std.algorithm.searching : any;
    import std.file : exists, isFile;
    import std.path : absolutePath, buildNormalizedPath, buildPath, dirName;
    import std.regex : matchAll, regex;

    const installation = dirName(dirName(dirName(realPath(compiler))));
    // DMD keeps druntime and Phobos under src/; LDC, whose ldmd2 fills the DMD role on arm64 (ADR-024), under import/.
    const standard = [
        buildPath(installation, "src", "phobos"), buildPath(installation, "src", "druntime",
                "import"), buildPath(dirName(dirName(realPath(compiler))), "import")
    ];
    size_t[] starts;
    size_t[] ends;
    string[] locations;
    foreach (match; matchAll(text, regex(`^// expansion at(?: (.+)\([0-9]+\))?$`, "m")))
    {
        starts ~= match.pre.length;
        ends ~= match.pre.length + match.hit.length;
        locations ~= match[1].idup;
    }
    if (starts.length == 0)
        return tokenize(text, tokens, failure);
    Token[] part;
    if (!tokenize(text[0 .. starts[0]], part, failure))
        return false;
    tokens ~= part;
    foreach (index, start; starts)
    {
        const finish = index + 1 < starts.length ? starts[index + 1] : text.length;
        const location = locations[index];
        if (location.length)
        {
            const source = realPath(buildPath(root, location));
            if (exists(source) && isFile(source) && standard.any!(directory => within(source, directory)))
                continue;
        }
        if (!tokenize(text[ends[index] .. finish], part, failure))
            return false;
        tokens ~= part;
    }
    return true;
}

private bool within(string path, string directory)
{
    version (Windows)
        const separator = path.length > directory.length && (path[directory.length] == '/'
                || path[directory.length] == '\\');
    else
        const separator = path.length > directory.length && path[directory.length] == '/';
    return separator && path[0 .. directory.length] == directory;
}

/// Canonical absolute path with symbolic links resolved, as Python's Path.resolve().
string realPath(string path)
{
    version (Windows)
    {
        import std.path : absolutePath, baseName, buildNormalizedPath, buildPath, dirName;
        import flint_tool.sys.windows : finalPath;

        // The longest existing prefix is resolved by the kernel; the rest is appended as written.
        string current = buildNormalizedPath(absolutePath(path));
        string rest;
        while (true)
        {
            const resolved = finalPath(current);
            if (resolved.length)
                return rest.length ? buildPath(resolved, rest) : resolved;
            const parent = dirName(current);
            if (parent == current)
                return buildNormalizedPath(absolutePath(path));
            rest = rest.length ? buildPath(baseName(current), rest) : baseName(current);
            current = parent;
        }
    }
    else
        return posixRealPath(path);
}

version (Posix) private string posixRealPath(string path)
{
    import std.algorithm.iteration : splitter;
    import std.file : exists, isSymlink, readLink;
    import std.path : absolutePath, buildNormalizedPath, dirName, isAbsolute;

    string current = buildNormalizedPath(absolutePath(path));
    // Resolve one link per pass, from the root down, until no component is a link.
    foreach (_; 0 .. 40)
    {
        string prefix = "/";
        bool changed;
        foreach (component; current.splitter('/'))
        {
            if (component.length == 0)
                continue;
            const candidate = buildNormalizedPath(prefix, component);
            if (!changed && exists(candidate) && isSymlink(candidate))
            {
                const target = readLink(candidate);
                prefix = isAbsolute(target) ? buildNormalizedPath(target) : buildNormalizedPath(dirName(candidate),
                        target);
                changed = true;
                continue;
            }
            prefix = candidate;
        }
        current = prefix;
        if (!changed)
            break;
    }
    return current;
}

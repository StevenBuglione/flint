/// Every DUB package under `framework/` and `boot/` is registered in `policy/framework.json` or `policy/boot.json`
/// (FLINT-E0535), so the gates check it and `tools/extract_repo.py` moves it. Ported from tools/gates.py
/// `layer_registration`, with the same verdicts.
///
/// `policy/unregistered-packages.json` lists the packages that were unregistered when the check landed, on
/// 2026-11-23. The list only shrinks: an entry that is registered or no longer a package fails until it is
/// removed, and no entry may be dated after that day.
module flint_tool.check.registration;

@safe:

/// The day the allowlist was frozen; entries dated later are refused.
enum registrationFrozen = "2026-11-23";

/// One registration problem.
struct RegistrationProblem
{
    /// Root-relative package directory.
    string path;
    /// What is wrong.
    string message;
    /// The file to edit.
    string fix;
}

/// The registration problems of the tree at `root`, for the top-level trees `tops` (`framework`, `boot`) whose repos
/// live in this checkout.
RegistrationProblem[] registrationProblems(string root, scope const string[] tops = [
    "framework", "boot"
])
{
    import std.path : buildPath;
    import flint_tool.support.files : readIfPresent;

    string[] registered = registeredDirectories(readIfPresent(buildPath(root, "policy", "framework.json")), [
        "modules"
    ]);
    registered ~= registeredDirectories(readIfPresent(buildPath(root, "policy", "boot.json")),
            ["libraries", "starters"]);
    const allowed = allowlist(readIfPresent(buildPath(root, "policy", "unregistered-packages.json")));
    RegistrationProblem[] problems;
    string[] found;
    foreach (top; tops)
    {
        const policyFile = top == "framework" ? "policy/framework.json" : "policy/boot.json";
        foreach (path; packageDirectories(root, top))
        {
            found ~= path;
            if (!contains(registered, path) && (path in allowed) is null)
                problems ~= RegistrationProblem(path,
                        path ~ " is a DUB package that no policy lists", "add it to " ~ policyFile);
        }
    }
    foreach (path; sortedKeys(allowed))
    {
        enum allowlistFile = "policy/unregistered-packages.json";
        if (!contains(tops, topOf(path)))
            continue;
        if (allowed[path] > registrationFrozen)
            problems ~= RegistrationProblem(path, path ~ ": " ~ allowlistFile ~ " only shrinks",
                    "register the package in its policy instead");
        else if (!contains(found, path))
            problems ~= RegistrationProblem(path, path ~ " is no longer a package", "remove it from " ~ allowlistFile);
        else if (contains(registered, path))
            problems ~= RegistrationProblem(path, path ~ " is registered now", "remove it from " ~ allowlistFile);
    }
    return problems;
}

/// The outermost directories under `root/top` holding a `dub.sdl` or `dub.json`, root-relative and sorted. A recipe
/// nested inside a package (a fixture) belongs to that package; hidden directories are skipped.
string[] packageDirectories(string root, string top)
{
    import std.algorithm.sorting : sort;
    import std.file : DirEntry, dirEntries, exists, isDir, SpanMode;
    import std.path : baseName, buildPath;

    string[] found;
    void walk(string directory, string relative)
    {
        if (exists(buildPath(directory, "dub.sdl")) || exists(buildPath(directory, "dub.json")))
        {
            found ~= relative;
            return;
        }
        string[] children;
        foreach (DirEntry entry; dirEntries(directory, SpanMode.shallow, false))
        {
            if (entry.isDir && baseName(entry.name)[0] != '.')
                children ~= baseName(entry.name);
        }
        sort(children);
        foreach (child; children)
            walk(buildPath(directory, child), relative ~ "/" ~ child);
    }

    const base = buildPath(root, top);
    if (exists(base) && isDir(base))
        walk(base, top);
    sort(found);
    return found;
}

/// The `directory` of every entry in the named groups of a policy document.
string[] registeredDirectories(string text, scope const string[] groups)
{
    import std.json : JSONException, JSONType, parseJSON;

    string[] directories;
    if (text.length == 0)
        return null;
    try
    {
        auto root = parseJSON(text);
        foreach (group; groups)
        {
            if (group !in root || root[group].type != JSONType.object)
                continue;
            foreach (name, ref meta; root[group].objectNoRef)
                if ("directory" in meta)
                    directories ~= meta["directory"].str;
        }
    }
    catch (JSONException)
        return null;
    return directories;
}

/// The allowlist: package directory -> the date it was listed.
string[string] allowlist(string text)
{
    import std.json : JSONException, parseJSON;

    string[string] paths;
    if (text.length == 0)
        return paths;
    try
    {
        auto root = parseJSON(text);
        if ("paths" in root)
            foreach (path, ref meta; root["paths"].objectNoRef)
                paths[path] = "since" in meta ? meta["since"].str : "";
    }
    catch (JSONException)
        return null;
    return paths;
}

private string topOf(string path)
{
    foreach (index, c; path)
    {
        if (c == '/')
            return path[0 .. index];
    }
    return path;
}

private bool contains(scope const string[] values, string value)
{
    foreach (item; values)
    {
        if (item == value)
            return true;
    }
    return false;
}

private string[] sortedKeys(const string[string] table)
{
    import std.algorithm.sorting : sort;

    string[] keys;
    foreach (key, _; table)
        keys ~= key;
    sort(keys);
    return keys;
}

/// Report every registration problem as FLINT-E0535, located at the package directory. Only this checkout's own
/// trees are scanned: a repo whose packages live elsewhere after the split (platform.lock) is skipped.
void checkRegistration(const ref imported!"flint_tool.home.policy".Home home,
        ref imported!"flint_tool.diagnostics.report".Report report)
{
    import std.file : exists, isDir;
    import std.path : buildPath;
    import flint_tool.diagnostics.report : Severity, at, diagnostic;

    string[] tops;
    foreach (top; ["framework", "boot"])
    {
        const tree = buildPath(home.root, top);
        if (home.inHome(top) && exists(tree) && isDir(tree))
            tops ~= top;
    }
    foreach (ref problem; registrationProblems(home.root, tops))
        report.add(at(diagnostic("FLINT-E0535", Severity.error, problem.message, problem.fix), problem.path, 0));
}

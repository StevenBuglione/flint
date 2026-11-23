module flint_tool.check.platform;

import flint_tool.home.policy : Home;
import std.json : JSONValue;

@safe:

/// How to bring the platform-module outputs current; tools/platform_modules.py prints the same text.
enum regenerate = "run python3 tools/platform_modules.py --write and commit the result with the policy edit; after "
    ~ "a rebase that touches policy, run it again (the outputs are deterministic, so regenerating settles any "
    ~ "conflict)";

/// The bill of materials and the lock partitions that tools/platform_modules.py generates are current (ADR-023
/// platform modules): the same rule as tools/gates.py platform_outputs. Returns the problems; none when the home
/// has no platform.lock.
string[] platformOutputProblems(const ref Home home)
{
    import std.file : exists;
    import std.path : buildPath;

    if (!exists(buildPath(home.root, "platform.lock")))
        return null;
    string[] problems;
    string[string] owners;
    if (!collectOwners(home.root, owners, problems))
        return problems;
    const bom = buildPath("boot", "dependencies", "flint-dependencies.json");
    if (!bomCurrent(home, owners, bom))
        problems ~= bom ~ " is stale: " ~ regenerate;
    if (exists(buildPath(home.root, "policy", "native-lock.json")))
    {
        string failure;
        const current = partitionsCurrent(home.root, owners, failure);
        if (failure.length)
            problems ~= failure;
        else if (!current)
            problems ~= "policy/lock-partitions.json is stale: " ~ regenerate;
    }
    return problems;
}

private JSONValue load(string root, string relative)
{
    import std.file : exists, readText;
    import std.json : parseJSON;
    import std.path : buildPath;

    const path = buildPath(root, relative);
    return exists(path) ? parseJSON(readText(path)) : JSONValue.init;
}

private string text(const JSONValue value, string key, string fallback = null)
{
    import std.json : JSONType;

    if (value.type != JSONType.object)
        return fallback;
    auto found = key in value.objectNoRef;
    return found && found.type == JSONType.string ? found.str : fallback;
}

private string[] strings(const JSONValue value)
{
    import std.json : JSONType;

    string[] result;
    if (value.type == JSONType.array)
        foreach (item; value.arrayNoRef)
            if (item.type == JSONType.string)
                result ~= item.str;
    return result;
}

private const(JSONValue) member(const JSONValue value, string key)
{
    import std.json : JSONType;

    if (value.type != JSONType.object)
        return JSONValue.init;
    auto found = key in value.objectNoRef;
    return found ? *found : JSONValue.init;
}

// Every package, Boot library, starter and framework module by name, with its repo (tools/workspace.py
// package_repos).
private bool collectOwners(string root, ref string[string] owners, ref string[] problems)
{
    import std.json : JSONType;

    const packages = member(load(root, "policy/packages.json"), "packages");
    if (packages.type != JSONType.object)
    {
        problems ~= "policy/packages.json has no packages";
        return false;
    }
    foreach (name, meta; packages.objectNoRef)
        owners[name] = text(meta, "repo", "flint");
    const boot = load(root, "policy/boot.json");
    foreach (group; ["libraries", "starters"])
    {
        const entries = member(boot, group);
        if (entries.type == JSONType.object)
            foreach (name, meta; entries.objectNoRef)
                owners[name] = text(meta, "repo", "boot");
    }
    const modules = member(load(root, "policy/framework.json"), "modules");
    if (modules.type == JSONType.object)
        foreach (name, meta; modules.objectNoRef)
            owners[name] = text(meta, "repo", "framework");
    return true;
}

private bool bomCurrent(const ref Home home, const ref string[string] owners, string relative)
{
    import std.json : JSONType;

    const repos = member(load(home.root, "platform.lock"), "repos");
    const bom = load(home.root, relative);
    const artifacts = member(bom, "artifacts");
    if (artifacts.type != JSONType.object || text(bom, "release") != home.platform.release
            || artifacts.objectNoRef.length != owners.length)
        return false;
    foreach (name, repo; owners)
    {
        const entry = member(repos, repo);
        const version_ = text(entry, "tag", text(entry, "commit", text(entry, "source")));
        auto artifact = ("flint:" ~ name) in artifacts.objectNoRef;
        if (artifact is null || text(*artifact, "repo") != repo || text(*artifact, "version") != version_)
            return false;
    }
    return true;
}

// The repo that carries a lock consumer's slice (tools/platform_modules.py consumer_repo).
private string consumerRepo(string consumer, const ref string[string] owners, const JSONValue tools)
{
    import std.algorithm.searching : startsWith;

    if (auto repo = consumer in owners)
        return *repo;
    const package_ = text(tools, consumer);
    if (package_.length)
        if (auto repo = package_ in owners)
            return *repo;
    if (consumer.startsWith("tools/") || consumer.startsWith("apps/flint/"))
        return "flint";
    return null;
}

private bool partitionsCurrent(string root, const ref string[string] owners, out string failure)
{
    import std.algorithm.sorting : sort;
    import std.json : JSONType;

    const inputs = member(member(load(root, "policy/repos.json"), "lock_partitions"), "tool_consumers");
    const providers = member(member(load(root, "policy/repos.json"), "lock_partitions"), "shim_providers");
    bool[string][string] native;
    string[][string] dependencies;
    const libraries = member(load(root, "policy/native-lock.json"), "libraries");
    foreach (row; libraries.type == JSONType.array ? libraries.arrayNoRef : null)
    {
        const name = text(row, "name");
        dependencies[name] = strings(member(row, "dependencies"));
        foreach (consumer; strings(member(row, "consumers")))
        {
            const repo = consumerRepo(consumer, owners, inputs);
            if (repo is null)
            {
                failure = "policy/native-lock.json: lock consumer " ~ consumer
                    ~ " is neither a package nor a known tool";
                return false;
            }
            native[repo][name] = true;
        }
    }
    if (providers.type == JSONType.object)
        foreach (repo, names; providers.objectNoRef)
            foreach (name; strings(names))
                native[repo][name] = true;
    foreach (repo, ref names; native)
    {
        string[] pending = names.keys;
        while (pending.length)
        {
            const next = pending[$ - 1];
            pending = pending[0 .. $ - 1];
            foreach (dependency; dependencies.get(next, null))
            {
                if (dependency !in names)
                {
                    names[dependency] = true;
                    pending ~= dependency;
                }
            }
        }
    }
    bool[string][string] peers;
    const lockedPeers = member(load(root, "policy/peer-lock.json"), "peers");
    if (lockedPeers.type == JSONType.object)
        foreach (name, row; lockedPeers.objectNoRef)
            foreach (consumer; strings(member(row, "consumers")))
            {
                const repo = consumerRepo(consumer, owners, inputs);
                if (repo is null)
                {
                    failure = "policy/peer-lock.json: lock consumer " ~ consumer
                        ~ " is neither a package nor a known tool";
                    return false;
                }
                peers[repo][name] = true;
            }
    const written = load(root, "policy/lock-partitions.json");
    return sameSlices(member(written, "native"), native) && sameSlices(member(written, "peers"), peers);
}

private bool sameSlices(const JSONValue written, const bool[string][string] expected)
{
    import std.algorithm.sorting : sort;
    import std.json : JSONType;

    if (written.type != JSONType.object || written.objectNoRef.length != expected.length)
        return false;
    foreach (repo, names; expected)
    {
        auto slice = repo in written.objectNoRef;
        if (slice is null)
            return false;
        auto have = strings(*slice);
        auto want = names.keys;
        sort(have);
        sort(want);
        if (have != want)
            return false;
    }
    return true;
}

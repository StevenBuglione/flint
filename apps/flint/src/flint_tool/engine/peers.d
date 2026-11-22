/// Fixture peers of the workspace test suites (ADR-018): policy/test-peers.toml.
///
/// A peer is a wrapper command that starts the peer, exports its address through FLINT_* variables and runs
/// the rest of the command line. `flint test` nests a package's wrappers around its test binary.
module flint_tool.engine.peers;

import flint_tool.diagnostics.report : Report;
import flint_tool.home.policy : Home;

@safe:

/// The peer policy file.
enum peerPolicy = "policy/test-peers.toml";

/// A pinned binary a peer needs.
struct PeerBinary
{
    /// Binary name.
    string name;
    /// What it is.
    string description;
    /// Path template ({toolchain} or relative to the checkout).
    string path;
    /// Receipt that must exist, when the binary is built by Flint.
    string receipt;
    /// Command that installs it.
    string install;
    /// Why it cannot be installed yet, when it has no pinned release.
    string unpinned;
}

/// One peer wrapper.
struct PeerSpec
{
    /// Peer name.
    string name;
    /// What it is.
    string description;
    /// Wrapper command template.
    string[] command;
}

/// The whole peer policy.
struct PeerTable
{
    /// Binaries by name.
    PeerBinary[string] binaries;
    /// Peers by name.
    PeerSpec[string] peers;
    /// Peer names per package, outermost first.
    string[][string] packages;
}

/// A peer that cannot start, and why.
struct MissingPeer
{
    /// Peer name.
    string peer;
    /// The binary it lacks.
    string binary;
    /// Explanation.
    string detail;
    /// How to install it, when it can be installed.
    string install;
}

/// The resolved wrappers for one package.
struct PeerPlan
{
    /// Wrapper argv prefix for the peers that can start.
    string[] prefix;
    /// Peers that start.
    string[] started;
    /// Peers that cannot.
    MissingPeer[] missing;
}

/// Parse policy/test-peers.toml.
bool loadPeers(const ref Home home, out PeerTable table, ref Report report)
{
    import std.path : buildPath;
    import flint.serde.owned : readTomlEntries;
    import flint_tool.support.files : readIfPresent;

    const text = readIfPresent(buildPath(home.root, peerPolicy));
    if (text is null)
        return true;
    const entries = readTomlEntries(text);
    if (!entries.ok)
    {
        report.error("FLINT-E0809", peerPolicy ~ ": " ~ entries.error.message, "git checkout -- " ~ peerPolicy);
        return false;
    }
    foreach (ref entry; entries.value)
    {
        const problem = readEntry(table, entry.path, entry.json);
        if (problem.length)
            return invalid(report, problem);
    }
    foreach (name, list; table.packages)
    {
        foreach (peerName; list)
        {
            if (peerName !in table.peers)
                return invalid(report, "package " ~ name ~ " names unknown peer " ~ peerName);
        }
    }
    return true;
}

/// Apply one TOML entry; returns a problem description, or null.
private string readEntry(ref PeerTable table, scope const(string)[] path, string json)
{
    import flint.serde.owned : deserialize;

    if (path.length == 2 && path[0] == "packages")
    {
        const list = deserialize!(string[])(json);
        if (!list.ok)
            return "[packages] " ~ path[1] ~ " must list peer names";
        table.packages[path[1]] = list.value.dup;
        return null;
    }
    if (path.length != 3 || (path[0] != "binary" && path[0] != "peer"))
        return "unknown key " ~ joinPath(path);
    if (path[0] == "peer" && path[2] == "command")
    {
        const command = deserialize!(string[])(json);
        if (!command.ok || command.value.length == 0)
            return "peer." ~ path[1] ~ ".command must be a nonempty array";
        peer(table, path[1]).command = command.value.dup;
        return null;
    }
    const value = deserialize!string(json);
    if (!value.ok || !assign(table, path, value.value))
        return "unknown or invalid key " ~ joinPath(path);
    return null;
}

private ref PeerSpec peer(ref PeerTable table, string name)
{
    if (name !in table.peers)
        table.peers[name] = PeerSpec(name);
    return table.peers[name];
}

private bool assign(ref PeerTable table, scope const(string)[] path, string value)
{
    if (path[0] == "peer")
    {
        if (path[2] != "description")
            return false;
        peer(table, path[1]).description = value;
        return true;
    }
    if (path[1]!in table.binaries)
        table.binaries[path[1]] = PeerBinary(path[1]);
    auto binary = &table.binaries[path[1]];
    switch (path[2])
    {
    case "description":
        binary.description = value;
        return true;
    case "path":
        binary.path = value;
        return true;
    case "receipt":
        binary.receipt = value;
        return true;
    case "install":
        binary.install = value;
        return true;
    case "unpinned":
        binary.unpinned = value;
        return true;
    default:
        return false;
    }
}

private bool invalid(ref Report report, string message)
{
    report.error("FLINT-E0809", peerPolicy ~ ": " ~ message, "git checkout -- " ~ peerPolicy);
    return false;
}

private string joinPath(scope const(string)[] path)
{
    import std.array : join;

    return path.join(".");
}

/// Absolute path of a binary, or null with a MissingPeer reason when it is unavailable.
string binaryPath(const ref Home home, string toolchainDirectory, const ref PeerBinary binary, out string why)
{
    import std.array : replace;
    import std.file : exists;
    import std.path : absolutePath, buildNormalizedPath;

    if (binary.unpinned.length)
    {
        why = binary.unpinned;
        return null;
    }
    const path = buildNormalizedPath(absolutePath(binary.path.replace("{toolchain}", toolchainDirectory), home.root));
    if (!exists(path))
    {
        why = binary.description ~ " is not installed at " ~ path;
        return null;
    }
    if (binary.receipt.length && !exists(buildNormalizedPath(absolutePath(binary.receipt, home.root))))
    {
        why = binary.description ~ " has no install receipt";
        return null;
    }
    return path;
}

/// Resolve a package's peers: build Go fixture servers, substitute binaries, record what is missing.
PeerPlan planPeers(const ref Home home, const ref PeerTable table, string toolchainDirectory,
        string packageName, ref Report report)
{
    PeerPlan plan;
    if (packageName !in table.packages)
        return plan;
    foreach (peerName; table.packages[packageName])
    {
        const spec = table.peers[peerName];
        string[] command;
        MissingPeer missing;
        foreach (argument; spec.command)
        {
            string resolved;
            if (!resolveArgument(home, table, toolchainDirectory, argument, resolved, missing, report))
                break;
            command ~= resolved;
        }
        if (missing.binary.length)
        {
            missing.peer = peerName;
            plan.missing ~= missing;
            continue;
        }
        plan.prefix ~= command;
        plan.started ~= peerName;
    }
    return plan;
}

private bool resolveArgument(const ref Home home, const ref PeerTable table, string toolchainDirectory,
        string argument, out string resolved, ref MissingPeer missing, ref Report report)
{
    import std.algorithm.searching : endsWith, startsWith;

    if (!argument.startsWith("{") || !argument.endsWith("}"))
    {
        resolved = argument;
        return true;
    }
    const inner = argument[1 .. $ - 1];
    const goBuild = inner.startsWith("go-build:");
    const name = goBuild ? "go" : inner.startsWith("bin:") ? inner["bin:".length .. $] : null;
    if (name is null || name !in table.binaries)
    {
        report.error("FLINT-E0809", peerPolicy ~ ": unknown placeholder " ~ argument, "git checkout -- " ~ peerPolicy);
        missing.binary = inner;
        return false;
    }
    string why;
    const path = binaryPath(home, toolchainDirectory, table.binaries[name], why);
    if (path is null)
    {
        missing.binary = name;
        missing.detail = why;
        missing.install = table.binaries[name].install;
        return false;
    }
    if (!goBuild)
    {
        resolved = path;
        return true;
    }
    const fixture = inner["go-build:".length .. $];
    return buildGoFixture(home, path, fixture, resolved, missing);
}

/// Build a Go fixture server with the pinned Go, offline, into .flint/peers/bin.
private bool buildGoFixture(const ref Home home, string go, string dir, out string output, ref MissingPeer missing)
{
    import std.algorithm.searching : endsWith;
    import std.algorithm.sorting : sort;
    import std.array : replace;
    import std.path : buildPath;
    import flint.os : EnvVar;
    import flint_tool.support.files : findFiles;
    import flint_tool.support.process : Launch, capture;

    const source = buildPath(home.root, dir);
    string[] files;
    foreach (relative; findFiles(source, "*.go"))
    {
        if (!relative.endsWith("_test.go"))
            files ~= relative;
    }
    sort(files);
    const peers = buildPath(home.root, ".flint", "peers");
    output = buildPath(peers, "bin", dir.replace("/", "-"));
    Launch launch;
    launch.directory = source;
    launch.environment = [
        EnvVar("CGO_ENABLED", "0"), EnvVar("GOTOOLCHAIN", "local"), EnvVar("GOPROXY", "off"),
        EnvVar("GOCACHE", buildPath(peers, "gocache")), EnvVar("GOPATH", buildPath(peers, "gopath"))
    ];
    const built = capture([go, "build", "-trimpath", "-o", output] ~ files, launch);
    if (built.ok)
        return true;
    missing.binary = "go";
    missing.detail = "building " ~ dir ~ " failed: " ~ built.failure ~ built.combined();
    return false;
}

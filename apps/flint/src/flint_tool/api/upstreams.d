/// The pinned upstream source archives behind the API manifests: `api/upstreams.json` in the Flint home, and
/// `flint api fetch`, which downloads them into the reference cache and verifies them by SHA-256
/// (ADR-030, API manifests).
///
/// The cache holds sources for reading only. Nothing in it is ever compiled or run.
module flint_tool.api.upstreams;

@safe:

/// Schema of `api/upstreams.json`.
enum upstreamsSchema = "flint.api-upstreams/1";

/// One pinned archive.
struct Upstream
{
    /// Project name, as in manifests.
    string project;
    /// Tag or release.
    string version_;
    /// Download URL.
    string url;
    /// Lower-case hexadecimal SHA-256 of the archive.
    string sha256;
    /// `tar.gz` (a GitHub tag archive) or `jar` (a Maven `-sources.jar`).
    string format;
    /// SPDX licence expression, for the report.
    string licence;
    /// Root-relative prefixes `flint api extract` leaves out.
    string[] exclude;

    /// Directory name in the cache: `<project>-<version>`.
    string key() const
    {
        return project ~ "-" ~ version_;
    }
}

/// Parse `api/upstreams.json`.
bool parseUpstreams(string text, out Upstream[] upstreams, out string error)
{
    import std.json : JSONException, JSONType, JSONValue, parseJSON;

    try
    {
        auto root = parseJSON(text);
        if (root.type != JSONType.object || "schema" !in root || root["schema"].str != upstreamsSchema)
        {
            error = "not a " ~ upstreamsSchema ~ " document";
            return false;
        }
        foreach (ref item; root["upstreams"].arrayNoRef)
        {
            Upstream upstream;
            upstream.project = item["project"].str;
            upstream.version_ = item["version"].str;
            upstream.url = item["url"].str;
            upstream.sha256 = item["sha256"].str;
            upstream.format = item["format"].str;
            upstream.licence = "licence" in item ? item["licence"].str : null;
            if ("exclude" in item)
                foreach (ref value; item["exclude"].arrayNoRef)
                    upstream.exclude ~= value.str;
            if (upstream.format != "tar.gz" && upstream.format != "jar")
            {
                error = upstream.key ~ ": format must be tar.gz or jar";
                return false;
            }
            if (upstream.sha256.length != 64)
            {
                error = upstream.key ~ ": sha256 must be 64 hexadecimal digits";
                return false;
            }
            upstreams ~= upstream;
        }
    }
    catch (JSONException failure)
    {
        error = "malformed upstreams: " ~ failure.msg;
        return false;
    }
    return true;
}

/// Read the pins from the Flint home; empty with `error` when they cannot be read.
Upstream[] loadUpstreams(string homeRoot, out string error)
{
    import std.file : exists, readText;
    import std.path : buildPath;

    const path = upstreamsPath(homeRoot);
    if (!exists(path))
    {
        error = path ~ " is missing";
        return null;
    }
    Upstream[] upstreams;
    if (!parseUpstreams(readText(path), upstreams, error))
        error = path ~ ": " ~ error;
    return upstreams;
}

/// `<home>/api/upstreams.json`.
string upstreamsPath(string homeRoot)
{
    import std.path : buildPath;

    return buildPath(homeRoot, "api", "upstreams.json");
}

/// The pin for `project` at `version_`, or null.
const(Upstream)* findUpstream(const(Upstream)[] upstreams, string project, string version_)
{
    foreach (ref upstream; upstreams)
    {
        if (upstream.project == project && upstream.version_ == version_)
            return &upstream;
    }
    return null;
}

/// The reference cache: `<cache>/api`, where the cache is FLINT_CACHE or `<home>/.flint/cache`.
string referenceCache(string homeRoot)
{
    import std.path : buildPath;
    import flint_tool.project.remote : Fetcher;

    return buildPath(Fetcher.forProject(homeRoot, null).cache(), "api");
}

/// The outcome of fetching one archive.
struct Fetched
{
    /// Project.
    string project;
    /// Version.
    string version_;
    /// Extracted source tree.
    string directory;
    /// Already present and verified.
    bool cached;
    /// Why it failed, or empty.
    string failure;
}

/// Download, verify and unpack one archive into `cache`, unless it is already there with the same digest.
Fetched fetchUpstream(const ref Upstream upstream, string cache, bool offline)
{
    import std.file : exists, mkdirRecurse, readText, remove, rename, rmdirRecurse, write;
    import std.path : buildPath;
    import flint_tool.support.files : sha256File;
    import flint_tool.support.process : capture;

    Fetched result = Fetched(upstream.project, upstream.version_, buildPath(cache, upstream.key));
    const stamp = buildPath(result.directory, ".flint-api-fetch");
    if (exists(stamp) && readText(stamp) == upstream.sha256 ~ "\n")
    {
        result.cached = true;
        return result;
    }
    if (offline)
    {
        result.failure = upstream.key ~ " is not in the reference cache and flint is offline";
        return result;
    }
    mkdirRecurse(cache);
    const archive = buildPath(cache, ".download-" ~ upstream.key);
    const staging = buildPath(cache, ".staging-" ~ upstream.key);
    scope (exit)
    {
        if (exists(archive))
            remove(archive);
        if (exists(staging))
            rmdirRecurse(staging);
    }
    const downloaded = capture(["curl", "-sSfL", "--retry", "3", "-o", archive, upstream.url]);
    if (!downloaded.ok)
    {
        result.failure = "cannot download " ~ upstream.url ~ ": " ~ downloaded.failure ~ downloaded.errors;
        return result;
    }
    const digest = sha256File(archive);
    if (digest != upstream.sha256)
    {
        result.failure = upstream.url ~ " has SHA-256 " ~ digest ~ ", but api/upstreams.json pins " ~ upstream.sha256;
        return result;
    }
    if (exists(staging))
        rmdirRecurse(staging);
    mkdirRecurse(staging);
    const unpacked = upstream.format == "tar.gz" ? capture([
        "tar", "-xzf", archive, "-C", staging, "--strip-components=1"
    ]) : capture(["unzip", "-q", "-o", archive, "-d", staging]);
    if (!unpacked.ok)
    {
        result.failure = "cannot unpack " ~ upstream.key ~ ": " ~ unpacked.failure ~ unpacked.errors;
        return result;
    }
    write(buildPath(staging, ".flint-api-fetch"), upstream.sha256 ~ "\n");
    if (exists(result.directory))
        rmdirRecurse(result.directory);
    rename(staging, result.directory);
    return result;
}

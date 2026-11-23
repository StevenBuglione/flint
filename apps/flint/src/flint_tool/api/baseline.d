/// The API coverage ratchet: a repo's `coverage-baseline.json`, beside its mapping, records the unclassified count of
/// every module of every manifest it classifies (ADR-030 section 8).
///
/// `flint api coverage` fails when a module's count rises above its baseline, so CI stays green while progress
/// becomes permanent and regressions show. `--update-baseline` rewrites the baseline from the current counts and
/// refuses to raise any number. The release gate (`--release`) still requires every element classified.
module flint_tool.api.baseline;

import flint_tool.api.coverage : ManifestCoverage;

@safe:

/// Schema of a baseline document.
enum baselineSchema = "flint.api-coverage-baseline/1";

/// The baseline of one manifest.
struct BaselineUpstream
{
    /// `project@version`.
    string key;
    /// Unclassified elements per module.
    size_t[string] modules;

    /// Unclassified elements of the manifest.
    size_t total() const
    {
        size_t sum;
        foreach (count; modules)
            sum += count;
        return sum;
    }
}

/// A whole baseline.
struct Baseline
{
    /// Manifests, sorted by key.
    BaselineUpstream[] upstreams;

    /// The upstream with `key`, or null.
    inout(BaselineUpstream)* find(string key) inout return
    {
        foreach (ref upstream; upstreams)
        {
            if (upstream.key == key)
                return &upstream;
        }
        return null;
    }

    /// Unclassified elements of every manifest.
    size_t total() const
    {
        size_t sum;
        foreach (ref upstream; upstreams)
            sum += upstream.total;
        return sum;
    }
}

/// How the current counts compare with a baseline.
struct Ratchet
{
    /// Counts above the baseline, or missing from it: each fails.
    string[] regressions;
    /// Counts below the baseline: the baseline can be lowered.
    string[] improvements;
}

/// The baseline of the current coverage.
Baseline baselineOf(const(ManifestCoverage)[] coverages)
{
    import std.algorithm.sorting : sort;

    Baseline baseline;
    foreach (ref result; coverages)
    {
        BaselineUpstream upstream;
        upstream.key = result.project ~ "@" ~ result.version_;
        foreach (ref tally; result.modules)
            upstream.modules[tally.name] = tally.unclassified;
        baseline.upstreams ~= upstream;
    }
    sort!((a, b) => a.key < b.key)(baseline.upstreams);
    return baseline;
}

/// Compare the current counts with the baseline.
Ratchet compare(const ref Baseline baseline, const ref Baseline current)
{
    import std.algorithm.sorting : sort;
    import std.format : format;

    Ratchet ratchet;
    foreach (ref upstream; current.upstreams)
    {
        const recorded = baseline.find(upstream.key);
        if (recorded is null)
        {
            ratchet.regressions ~= upstream.key ~ " is not in the baseline; record it with --update-baseline";
            continue;
        }
        foreach (name; sortedKeys(upstream.modules))
        {
            const count = upstream.modules[name];
            const before = name in recorded.modules;
            if (before is null && count)
                ratchet.regressions ~= format("%s %s: %d unclassified, and the module is not in the baseline",
                        upstream.key, name, count);
            else if (before !is null && count > *before)
                ratchet.regressions ~= format("%s %s: %d unclassified, above the baseline's %d",
                        upstream.key, name, count, *before);
            else if (before !is null && count < *before)
                ratchet.improvements ~= format("%s %s: %d unclassified, below the baseline's %d",
                        upstream.key, name, count, *before);
        }
    }
    return ratchet;
}

/// The new baseline after `current`, keeping recorded upstreams that were not measured; `raised` lists every count
/// that would rise, in which case the old baseline must stay.
Baseline lowered(const ref Baseline baseline, const ref Baseline current, out string[] raised)
{
    import std.algorithm.sorting : sort;

    foreach (message; compare(baseline, current).regressions)
    {
        // A manifest the baseline has never seen is recorded as it is; every other regression is a raise.
        if (!isNewUpstream(message))
            raised ~= message;
    }
    Baseline next;
    foreach (ref upstream; current.upstreams)
        next.upstreams ~= dupUpstream(upstream);
    foreach (ref upstream; baseline.upstreams)
    {
        if (current.find(upstream.key) is null)
            next.upstreams ~= dupUpstream(upstream);
    }
    sort!((a, b) => a.key < b.key)(next.upstreams);
    return next;
}

private bool isNewUpstream(string message)
{
    import std.algorithm.searching : endsWith;

    return message.endsWith(" is not in the baseline; record it with --update-baseline");
}

private BaselineUpstream dupUpstream(const ref BaselineUpstream upstream)
{
    BaselineUpstream copy;
    copy.key = upstream.key;
    foreach (name, count; upstream.modules)
        copy.modules[name] = count;
    return copy;
}

private string[] sortedKeys(const size_t[string] table)
{
    import std.algorithm.sorting : sort;

    string[] keys;
    foreach (key, _; table)
        keys ~= key;
    sort(keys);
    return keys;
}

/// Render a baseline: one module per line, sorted, so a lowered count diffs as one line.
string renderBaseline(const ref Baseline baseline)
{
    import std.algorithm.sorting : sort;
    import std.conv : to;
    import std.json : JSONValue;

    string text = `{"schema":"` ~ baselineSchema ~ `",` ~ "\n" ~ `"unclassified":`
        ~ baseline.total.to!string ~ ",\n" ~ `"upstreams":{` ~ "\n";
    string[] keys;
    foreach (ref upstream; baseline.upstreams)
        keys ~= upstream.key;
    sort(keys);
    foreach (index, key; keys)
    {
        const upstream = baseline.find(key);
        text ~= JSONValue(upstream.key).toString ~ `:{"unclassified":` ~ upstream.total.to!string
            ~ `,"modules":{` ~ "\n";
        const names = sortedKeys(upstream.modules);
        foreach (position, name; names)
            text ~= JSONValue(name).toString ~ ":" ~ upstream.modules[name].to!string ~ (position + 1 < names.length
                    ? "," : "") ~ "\n";
        text ~= "}}" ~ (index + 1 < keys.length ? "," : "") ~ "\n";
    }
    return text ~ "}}\n";
}

/// Parse a baseline document.
bool parseBaseline(string text, out Baseline baseline, out string error)
{
    import std.algorithm.sorting : sort;
    import std.json : JSONException, JSONType, parseJSON;

    try
    {
        auto root = parseJSON(text);
        if (root.type != JSONType.object || "schema" !in root || root["schema"].str != baselineSchema)
        {
            error = "not a " ~ baselineSchema ~ " document";
            return false;
        }
        foreach (key, ref value; root["upstreams"].objectNoRef)
        {
            BaselineUpstream upstream;
            upstream.key = key;
            foreach (name, ref count; value["modules"].objectNoRef)
                upstream.modules[name] = cast(size_t) count.integer;
            baseline.upstreams ~= upstream;
        }
    }
    catch (JSONException failure)
    {
        error = "malformed baseline: " ~ failure.msg;
        return false;
    }
    sort!((a, b) => a.key < b.key)(baseline.upstreams);
    return true;
}

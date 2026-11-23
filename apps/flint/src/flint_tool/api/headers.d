/// `flint api headers`: every D file ported from an upstream carries the header ADR-030 section 7 requires, for an
/// upstream whose entry in `policy/upstream-licences.json` allows porting its source.
///
/// A file is ported when the header before its `module` declaration has a line
///
/// ---
/// // Ported from spring-framework v7.1.0: spring-core/src/main/java/org/springframework/util/StringUtils.java
/// // Copyright 2002-present the original author or authors.
/// // Licensed under the Apache License, Version 2.0.
/// // Modified by the Flint authors.
/// ---
///
/// The checks:
/// - `<project> <version>` must be pinned in `api/upstreams.json`.
/// - The pin's licence entry (`matrix`) must allow porting (`port-source`, `port-source-bsd-option` or
///   `epl-module`), at the same tag.
/// - The header must carry the entry's copyright line, or a `Copyright` line when the entry names none.
/// - It must carry the licence line for the licence and use: Apache License 2.0, MIT, the BSD 3-Clause option, or
///   the Eclipse Public License 2.0.
/// - It must say "Modified by the Flint authors", as Apache-2.0 §4(b) requires.
/// - An `epl-module` port must live in a package whose `dub.sdl` declares `license "EPL-2.0"`.
module flint_tool.api.headers;

import flint_tool.api.upstreams : Upstream;

@safe:

/// The marker of a ported file.
enum portedMarker = "Ported from ";

/// The modification notice.
enum modifiedNotice = "Modified by the Flint authors";

/// One project of the licence matrix.
struct LicenceEntry
{
    /// Matrix name.
    string name;
    /// SPDX expression.
    string licence;
    /// How Flint may use it.
    string use;
    /// Pinned tag, or a note while unpinned.
    string tag;
    /// The upstream's copyright line, when the matrix records it.
    string header;
}

/// One problem with a ported file's header.
struct HeaderProblem
{
    /// File.
    string file;
    /// 1-based line of the marker, or 1.
    size_t line;
    /// What is wrong.
    string message;
}

/// Parse `policy/upstream-licences.json`.
bool parseLicenceMatrix(string text, out LicenceEntry[] entries, out string error)
{
    import std.json : JSONException, parseJSON;

    try
    {
        auto root = parseJSON(text);
        foreach (ref item; root["projects"].arrayNoRef)
        {
            LicenceEntry entry;
            entry.name = item["name"].str;
            entry.licence = item["licence"].str;
            entry.use = item["use"].str;
            entry.tag = "tag" in item && !item["tag"].isNull ? item["tag"].str : null;
            entry.header = "header" in item ? item["header"].str : null;
            entries ~= entry;
        }
    }
    catch (JSONException failure)
    {
        error = "malformed licence matrix: " ~ failure.msg;
        return false;
    }
    return true;
}

/// The header of a D source: every line before its `module` declaration.
string headerOf(string source, out size_t markerLine)
{
    import std.algorithm.searching : startsWith;
    import std.string : indexOf, lineSplitter, stripLeft;

    size_t length;
    size_t number;
    foreach (line; source.lineSplitter!(imported!"std.typecons".Yes.keepTerminator))
    {
        number++;
        const stripped = line.stripLeft;
        if (stripped.startsWith("module ") || stripped.startsWith("@safe") || stripped.startsWith("import "))
            break;
        if (markerLine == 0 && opensWithMarker(stripped))
            markerLine = number;
        length += line.length;
    }
    return source[0 .. length];
}

/// Whether a comment line starts with the marker: `// Ported from`, ` * Ported from`, `/++ Ported from`.
bool opensWithMarker(string line)
{
    import std.algorithm.searching : startsWith;
    import std.string : stripLeft;

    size_t index;
    while (index < line.length && (line[index] == '/' || line[index] == '*' || line[index] == '+'))
        index++;
    return index > 0 && line[index .. $].stripLeft.startsWith(portedMarker);
}

/// The licence line a ported file must carry for `entry`, or empty when its source may not be ported.
string licenceLine(const ref LicenceEntry entry)
{
    switch (entry.use)
    {
    case "port-source":
        if (entry.licence == "Apache-2.0")
            return "Licensed under the Apache License, Version 2.0";
        if (entry.licence == "MIT")
            return "Licensed under the MIT License";
        if (entry.licence.length >= 4 && entry.licence[0 .. 4] == "BSD-")
            return "Licensed under the BSD";
        return null;
    case "port-source-bsd-option":
        return "Licensed under the BSD 3-Clause License";
    case "epl-module":
        return "Licensed under the Eclipse Public License 2.0";
    default:
        return null;
    }
}

/// Check one file's text; `packageLicence` is the `license` its nearest `dub.sdl` declares.
HeaderProblem[] checkHeader(string file, string source, const(Upstream)[] upstreams,
        const(LicenceEntry)[] matrix, string packageLicence)
{
    size_t markerLine;
    const header = headerOf(source, markerLine);
    if (markerLine == 0)
        return null;
    string project, version_, path, failure;
    const(LicenceEntry)* entry;
    if (!parseMarker(header, project, version_, path))
        failure = "the marker must read `Ported from <project> <version>: <upstream path>`";
    else
        entry = licenceFor(project, version_, upstreams, matrix, failure);
    if (entry is null)
        return [HeaderProblem(file, markerLine, failure)];
    HeaderProblem[] problems;
    foreach (message; contentProblems(header, *entry, version_, packageLicence))
        problems ~= HeaderProblem(file, markerLine, message);
    return problems;
}

/// The licence entry of a pinned upstream whose source may be ported, or null with `failure` set.
const(LicenceEntry)* licenceFor(string project, string version_, const(Upstream)[] upstreams,
        const(LicenceEntry)[] matrix, out string failure)
{
    const(Upstream)* pin;
    foreach (ref upstream; upstreams)
    {
        if (upstream.project == project && upstream.version_ == version_)
            pin = &upstream;
    }
    if (pin is null)
    {
        failure = project ~ " " ~ version_ ~ " is not pinned in api/upstreams.json";
        return null;
    }
    foreach (ref candidate; matrix)
    {
        if (candidate.name != pin.matrix)
            continue;
        if (licenceLine(candidate).length)
            return &candidate;
        failure = candidate.name ~ " is `" ~ candidate.use ~ "` (" ~ candidate.licence
            ~ ") in policy/upstream-licences.json: its source may not be ported";
        return null;
    }
    failure = pin.matrix ~ " has no entry in policy/upstream-licences.json";
    return null;
}

private string[] contentProblems(string header, const ref LicenceEntry entry, string version_, string packageLicence)
{
    import std.string : indexOf;

    string[] problems;
    const line = licenceLine(entry);
    if (entry.tag != version_)
        problems ~= "policy/upstream-licences.json pins " ~ entry.name ~ " at `" ~ entry.tag ~ "`, not " ~ version_;
    const copyright = entry.header.length ? entry.header : "Copyright";
    if (header.indexOf(copyright) < 0)
        problems ~= "the header lacks the upstream copyright line" ~ (entry.header.length ? ": " ~ entry.header : "");
    if (header.indexOf(line) < 0)
        problems ~= "the header lacks the licence line: " ~ line;
    if (header.indexOf(modifiedNotice) < 0)
        problems ~= "the header lacks \"" ~ modifiedNotice ~ "\" (Apache-2.0 §4(b))";
    if (entry.use == "epl-module" && packageLicence != "EPL-2.0")
        problems ~= entry.name ~ " is ported only into EPL-2.0 packages, but the package declares `" ~ (
                packageLicence.length ? packageLicence : "no licence") ~ "`";
    return problems;
}

/// Parse `Ported from <project> <version>: <path>` out of a header.
bool parseMarker(string header, out string project, out string version_, out string path)
{
    import std.string : indexOf, strip;

    import std.string : lineSplitter, stripLeft;

    string rest;
    foreach (line; header.lineSplitter)
    {
        if (opensWithMarker(line.stripLeft))
        {
            rest = line[line.indexOf(portedMarker) + portedMarker.length .. $].strip;
            break;
        }
    }
    if (rest.length == 0)
        return false;
    const space = rest.indexOf(' ');
    const colon = rest.indexOf(": ");
    if (space <= 0 || colon <= space + 1)
        return false;
    project = rest[0 .. space];
    version_ = rest[space + 1 .. colon];
    path = rest[colon + 2 .. $].strip;
    return path.length != 0 && version_.indexOf(' ') < 0;
}

/// The `license` of the nearest `dub.sdl` above `file`, up to `root`.
string packageLicence(string file, string root)
{
    import std.file : exists, readText;
    import std.path : absolutePath, buildNormalizedPath, buildPath, dirName;
    import std.string : indexOf;

    string directory = buildNormalizedPath(absolutePath(dirName(file)));
    const stop = buildNormalizedPath(absolutePath(root));
    while (true)
    {
        const recipe = buildPath(directory, "dub.sdl");
        if (exists(recipe))
            return sdlLicence(readText(recipe));
        if (directory == stop || dirName(directory) == directory || directory.indexOf(stop) != 0)
            return null;
        directory = dirName(directory);
    }
}

/// The value of a top-level `license "..."` line in a DUB recipe.
string sdlLicence(string recipe)
{
    import std.algorithm.searching : startsWith;
    import std.string : indexOf, lineSplitter;

    foreach (line; recipe.lineSplitter)
    {
        if (!line.startsWith("license \""))
            continue;
        const rest = line["license \"".length .. $];
        const end = rest.indexOf('"');
        return end < 0 ? null : rest[0 .. end];
    }
    return null;
}

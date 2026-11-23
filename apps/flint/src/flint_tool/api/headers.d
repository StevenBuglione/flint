/// `flint api headers`: every D file ported from an upstream carries the header ADR-030 section 7 requires, for an
/// upstream whose entry in `policy/upstream-licences.json` allows porting its source.
///
/// A file is ported when a line of the header before its `module` declaration starts with `Ported from`; the
/// canonical form is
///
/// ---
/// // Ported from spring-framework v7.1.0: spring-core/src/main/java/org/springframework/util/StringUtils.java
/// // Copyright 2002-present the original author or authors.
/// // Licensed under the Apache License, Version 2.0.
/// // Modified by the Flint authors.
/// ---
///
/// The checks:
/// - The marker line must name a pin of `api/upstreams.json`, by its project (or `owner/repo`, or Maven artifact
///   id), and the pinned version.
/// - The pin's licence entry (`matrix`) must allow porting (`port-source`, `port-source-bsd-option` or
///   `epl-module`), at the same tag.
/// - The header must carry the entry's copyright line, or a `Copyright` line when the entry names none.
/// - It must carry the licence line for the licence and use (Apache License 2.0, MIT, the BSD 3-Clause option, or
///   the Eclipse Public License 2.0), the licence's own standard wording (the MIT grant; the Eclipse Public License
///   by name or `EPL-2.0`; the BSD 3-Clause option), or an `SPDX-License-Identifier:` line naming that licence.
/// - It must say "Modified by the Flint authors", as Apache-2.0 §4(b) requires.
/// - An `epl-module` port must live in a package whose `dub.sdl` declares `license "EPL-2.0"`.
module flint_tool.api.headers;

import flint_tool.api.upstreams : Upstream;

@safe:

/// The marker of a ported file.
enum portedMarker = "Ported from ";

/// The other wording of the marker, used for runtime (non-API) ports such as druntime's collector.
enum portMarker = "Port of ";

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

/// Whether a comment line starts with the marker: `// Ported from`, ` * Ported from`, `/++ Ported from`, or the
/// same with `Port of`.
bool opensWithMarker(string line)
{
    return markerLength(line) != 0;
}

/// The length of the marker that opens a comment line (after its comment characters), or zero.
private size_t markerLength(string line)
{
    import std.algorithm.searching : startsWith;
    import std.string : stripLeft;

    size_t index;
    // Inside a block comment the marker may stand without any comment character.
    while (index < line.length && (line[index] == '/' || line[index] == '*' || line[index] == '+'))
        index++;
    const rest = line[index .. $].stripLeft;
    if (rest.startsWith(portedMarker))
        return portedMarker.length;
    return rest.startsWith(portMarker) ? portMarker.length : 0;
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
        if (entry.licence == "BSL-1.0")
            return "Distributed under the Boost Software License, Version 1.0";
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
    string failure;
    const(LicenceEntry)* entry;
    const pin = pinOf(markerText(header), upstreams, failure);
    if (pin !is null)
        entry = licenceFor(*pin, matrix, failure);
    if (entry is null)
        return [HeaderProblem(file, markerLine, failure)];
    HeaderProblem[] problems;
    foreach (message; contentProblems(header, *entry, pin.version_, packageLicence))
        problems ~= HeaderProblem(file, markerLine, message);
    return problems;
}

/// The text of the marker line, after `Ported from `.
string markerText(string header)
{
    import std.string : indexOf, lineSplitter, strip, stripLeft;

    foreach (line; header.lineSplitter)
    {
        const stripped = line.stripLeft;
        const length = markerLength(stripped);
        if (length == 0)
            continue;
        const marker = stripped.indexOf(portedMarker) >= 0 ? portedMarker : portMarker;
        return stripped[stripped.indexOf(marker) + length .. $].strip;
    }
    return null;
}

/// The names a marker may give a pin by: its project, the `owner/repo` of a GitHub archive, or the Maven
/// artifact id of a sources jar (`jakarta.servlet-api`).
string[] pinNames(const ref Upstream upstream)
{
    import std.algorithm.searching : endsWith, startsWith;
    import std.string : indexOf, lastIndexOf;

    string[] names = [upstream.project];
    enum github = "https://github.com/";
    if (upstream.url.startsWith(github))
    {
        const path = upstream.url[github.length .. $];
        const archive = path.indexOf("/archive/");
        if (archive > 0)
            names ~= path[0 .. archive];
    }
    const suffix = "-" ~ upstream.version_ ~ "-sources.jar";
    if (upstream.url.endsWith(suffix))
    {
        const file = upstream.url[upstream.url.lastIndexOf('/') + 1 .. $];
        names ~= file[0 .. $ - suffix.length];
    }
    return names;
}

/// The pin a marker names: one of its names and its version both appear as words of the marker line (a version
/// may also read `v7.1.0` or end a tag such as `jackson-annotations-2.21`). The longest matching name wins.
const(Upstream)* pinOf(string marker, const(Upstream)[] upstreams, out string failure)
{
    import std.algorithm.searching : endsWith;

    const words = markerWords(marker);
    bool hasWord(string word)
    {
        foreach (candidate; words)
        {
            if (candidate == word)
                return true;
        }
        return false;
    }

    bool hasVersion(string version_)
    {
        foreach (candidate; words)
        {
            if (candidate == version_ || candidate == "v" ~ version_
                    || candidate.endsWith("-" ~ version_) || candidate.endsWith("_" ~ version_))
                return true;
        }
        return false;
    }

    const(Upstream)* best;
    size_t bestLength;
    string named;
    foreach (ref upstream; upstreams)
    {
        foreach (name; pinNames(upstream))
        {
            if (!hasWord(name))
                continue;
            named = name;
            if (hasVersion(upstream.version_) && name.length > bestLength)
            {
                best = &upstream;
                bestLength = name.length;
            }
        }
    }
    if (best is null)
        failure = named.length ? "the marker names " ~ named ~ " at a version api/upstreams.json does not pin"
            : "the marker must name an upstream pinned in api/upstreams.json and its version: "
            ~ "`Ported from <project> <version>: <upstream path>`";
    return best;
}

/// The words of a marker line, split at spaces and punctuation that never occurs inside a name or version.
string[] markerWords(string marker)
{
    string[] words;
    size_t start;
    foreach (index, c; marker)
    {
        // `/` splits URLs and owner/repo, so `https://github.com/hibernate/hibernate-validator` names its project.
        const separator = c == ' ' || c == ',' || c == '(' || c == ')' || c == ':' || c == ';' || c == '\t' || c == '/';
        if (!separator)
            continue;
        if (index > start)
            words ~= marker[start .. index];
        start = index + 1;
    }
    if (marker.length > start)
        words ~= marker[start .. $];
    return words;
}

/// The licence entry of a pin whose source may be ported, or null with `failure` set.
const(LicenceEntry)* licenceFor(const ref Upstream pin, const(LicenceEntry)[] matrix, out string failure)
{
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
    if (!statesLicence(header, entry))
        problems ~= "the header lacks the licence line (" ~ line
            ~ ", or an SPDX-License-Identifier naming " ~ spdxOf(entry) ~ ")";
    if (header.indexOf(modifiedNotice) < 0)
        problems ~= "the header lacks \"" ~ modifiedNotice ~ "\" (Apache-2.0 §4(b))";
    if (entry.use == "epl-module" && packageLicence != "EPL-2.0")
        problems ~= entry.name ~ " is ported only into EPL-2.0 packages, but the package declares `" ~ (
                packageLicence.length ? packageLicence : "no licence") ~ "`";
    return problems;
}

/// Whether the header states the licence the port is made under: the licence line, the licence's own standard
/// wording (the MIT grant, the Eclipse Public License by name or identifier, the BSD 3-Clause option), or an SPDX
/// line naming it. Runs of spaces are collapsed first, as upstream notices often align their text.
bool statesLicence(string header, const ref LicenceEntry entry)
{
    import std.string : indexOf;

    const text = collapseSpaces(header);
    string[] evidence = [licenceLine(entry)];
    switch (spdxOf(entry))
    {
    case "Apache-2.0":
        // The standard sentence and upstream forms such as "License: Apache License, Version 2.0".
        evidence ~= "Apache License, Version 2.0";
        break;
    case "MIT":
        evidence ~= "Permission is hereby granted, free of charge";
        break;
    case "BSL-1.0":
        // druntime's own form: "License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0)".
        evidence ~= ["Boost License 1.0", "Boost Software License"];
        break;
    case "EPL-2.0":
        evidence ~= ["Eclipse Public License", "EPL-2.0"];
        break;
    case "BSD-3-Clause":
        evidence ~= ["BSD-3-Clause", "BSD 3-Clause"];
        break;
    default:
        break;
    }
    foreach (phrase; evidence)
    {
        if (phrase.length && text.indexOf(phrase) >= 0)
            return true;
    }
    return spdxNames(header, spdxOf(entry));
}

private string collapseSpaces(string text)
{
    string collapsed;
    bool space;
    foreach (c; text)
    {
        if (c == ' ' || c == '\t')
        {
            if (!space)
                collapsed ~= ' ';
            space = true;
            continue;
        }
        space = false;
        collapsed ~= c;
    }
    return collapsed;
}

/// The SPDX identifier of the licence a port is made under: the BSD or EPL option of a dual licence.
string spdxOf(const ref LicenceEntry entry)
{
    if (entry.use == "port-source-bsd-option")
        return "BSD-3-Clause";
    if (entry.use == "epl-module")
        return "EPL-2.0";
    return entry.licence;
}

/// Whether an `SPDX-License-Identifier:` line of the header names `licence`.
bool spdxNames(string header, string licence)
{
    import std.string : indexOf, lineSplitter;

    enum tag = "SPDX-License-Identifier:";
    foreach (line; header.lineSplitter)
    {
        const at = line.indexOf(tag);
        if (at < 0)
            continue;
        foreach (word; splitWords(line[at + tag.length .. $]))
        {
            if (word == licence)
                return true;
        }
    }
    return false;
}

private string[] splitWords(string text)
{
    string[] words;
    size_t start;
    foreach (index, c; text)
    {
        if (c == ' ' || c == '(' || c == ')' || c == '\t')
        {
            if (index > start)
                words ~= text[start .. index];
            start = index + 1;
        }
    }
    if (text.length > start)
        words ~= text[start .. $];
    return words;
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

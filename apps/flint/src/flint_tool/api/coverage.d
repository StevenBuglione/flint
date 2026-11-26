/// `flint api coverage`: classify every element of upstream manifests against a repo's `api/mapping.json`
/// (ADR-030 section 8, docs/spring/api-mapping.md).
///
/// The mapping has the rulebook's shape:
///
/// ---
/// {"rulebook": 1,
///  "upstream": ["spring-framework@v7.1.0", "spring-boot@v4.2.0"],
///  "elements": {
///    "org.springframework.http.HttpStatus": {"status": "ported", "d": "flint.engine.http.HttpStatus"},
///    "org.springframework.http.ResponseEntity": {"status": "adapted", "rules": ["R12", "R13"],
///                                                "d": "flint.engine.http.ResponseEntity"},
///    "org.springframework.jmx.**": {"status": "excluded", "category": "jvm-platform"},
///    "org.springframework.beans.factory.xml.**": {"status": "excluded", "category": "deferred", "phase": "3"}}}
/// ---
///
/// A key is an element id or a pattern over ids: `*` matches within one name (no `.`, `#`, `(`, `)` or `,`), `**`
/// matches anything. An exact id wins; among patterns, the longest literal text before the first wildcard wins,
/// then the pattern with fewer `**`, then the longer pattern. `ported` needs a D symbol `d` under `flint.`,
/// `adapted` one or more rulebook `rules` (`R1`–`R14`), `excluded` one of the rulebook's categories; `deferred`
/// also names its `phase`.
module flint_tool.api.coverage;

import flint_tool.api.manifest : Manifest;

@safe:

/// The exclusion categories of the rulebook (docs/spring/api-mapping.md, Exclusions).
immutable string[] exclusionCategories = [
    "jvm-runtime", "jvm-platform", "runtime-reflection", "packaging", "devtools", "jvm-language",
    "deferred"
];

/// How an element is classified.
enum Status : string
{
    unclassified = "unclassified",
    ported = "ported",
    adapted = "adapted",
    excluded = "excluded"
}

/// One mapping entry.
struct MappingEntry
{
    /// Element id or pattern.
    string match;
    /// Classification.
    Status status;
    /// D symbol (ported, optionally adapted).
    string symbol;
    /// Rule ids (adapted).
    string[] rules;
    /// Exclusion category (excluded).
    string category;
    /// Phase of a deferred element.
    string phase;
}

/// A whole mapping.
struct Mapping
{
    /// Rulebook version the classifications were made against; zero when not stated.
    uint rulebook;
    /// Upstream manifests it covers, `project@version`; empty means any.
    string[] upstreams;
    /// Entries, sorted by key.
    MappingEntry[] entries;

    /// Whether the mapping covers `project` at `version_`.
    bool covers(string project, string version_) const
    {
        if (upstreams.length == 0)
            return true;
        foreach (upstream; upstreams)
        {
            if (upstream == project ~ "@" ~ version_)
                return true;
        }
        return false;
    }
}

/// Counts of one module or of a whole manifest.
struct Tally
{
    /// Module name, or the project for a whole manifest.
    string name;
    /// Elements.
    size_t total;
    /// Ported.
    size_t ported;
    /// Adapted.
    size_t adapted;
    /// Excluded.
    size_t excluded;
    /// Unclassified.
    size_t unclassified;

    /// Share of elements classified, in percent.
    double classifiedPercent() const
    {
        return total ? 100.0 * (total - unclassified) / total : 100.0;
    }

    /// Count one element.
    void count(Status status)
    {
        total++;
        final switch (status)
        {
        case Status.ported:
            ported++;
            break;
        case Status.adapted:
            adapted++;
            break;
        case Status.excluded:
            excluded++;
            break;
        case Status.unclassified:
            unclassified++;
            break;
        }
    }
}

/// The coverage of one manifest.
struct ManifestCoverage
{
    /// Project.
    string project;
    /// Version.
    string version_;
    /// The whole manifest.
    Tally summary;
    /// Per module, sorted.
    Tally[] modules;
    /// Ids of unclassified elements, in manifest order.
    string[] unclassified;
}

/// Parse a mapping document; false with `error` set when it is malformed or an entry is invalid.
bool parseMapping(string text, out Mapping mapping, out string error)
{
    import std.algorithm.sorting : sort;
    import std.json : JSONException, JSONType, JSONValue, parseJSON;

    JSONValue root;
    try
        root = parseJSON(text);
    catch (JSONException failure)
    {
        error = failure.msg;
        return false;
    }
    if (root.type != JSONType.object || "elements" !in root || root["elements"].type != JSONType.object)
    {
        error = "not an API mapping: it needs an `elements` object (docs/spring/api-mapping.md)";
        return false;
    }
    try
    {
        if ("rulebook" in root)
            mapping.rulebook = cast(uint) root["rulebook"].integer;
        if ("upstream" in root)
        {
            const upstream = root["upstream"];
            if (upstream.type == JSONType.string)
                mapping.upstreams = [upstream.str];
            else
                foreach (ref value; upstream.arrayNoRef)
                    mapping.upstreams ~= value.str;
        }
        foreach (key, value; root["elements"].objectNoRef)
        {
            MappingEntry entry;
            if (!readEntry(key, value, entry, error))
                return false;
            mapping.entries ~= entry;
        }
    }
    catch (JSONException failure)
    {
        error = "malformed mapping: " ~ failure.msg;
        return false;
    }
    sort!((a, b) => a.match < b.match)(mapping.entries);
    return true;
}

private bool readEntry(string key, const ref imported!"std.json".JSONValue value, out MappingEntry entry,
        out string error)
{
    import std.json : JSONType;

    string field(string name)
    {
        return name in value ? value[name].str : null;
    }

    entry.match = key;
    if (value.type != JSONType.object)
    {
        error = key ~ ": an element's classification must be an object";
        return false;
    }
    entry.symbol = field("d");
    entry.category = field("category");
    entry.phase = field("phase");
    if ("rules" in value)
        foreach (ref rule; value["rules"].arrayNoRef)
            entry.rules ~= rule.str;
    switch (field("status"))
    {
    case "ported":
        entry.status = Status.ported;
        return checkPorted(entry, error);
    case "adapted":
        entry.status = Status.adapted;
        return checkAdapted(entry, error);
    case "excluded":
        entry.status = Status.excluded;
        return checkExcluded(entry, error);
    default:
        error = key ~ ": `status` must be ported, adapted or excluded";
        return false;
    }
}

private bool checkPorted(const ref MappingEntry entry, out string error)
{
    if (!validSymbol(entry.symbol))
        error = entry.match ~ ": a ported element needs its D symbol `d` under flint.";
    return error.length == 0;
}

private bool checkAdapted(const ref MappingEntry entry, out string error)
{
    if (entry.rules.length == 0)
        error = entry.match ~ ": an adapted element needs the rulebook `rules` it follows, R1 to R14, R16 or R17";
    foreach (rule; entry.rules)
    {
        if (!validRule(rule) && error.length == 0)
            error = entry.match ~ ": `" ~ rule ~ "` is not a rulebook rule, R1 to R14, R16 or R17";
    }
    if (entry.symbol.length && !validSymbol(entry.symbol) && error.length == 0)
        error = entry.match ~ ": `d` must be a D symbol under flint.";
    return error.length == 0;
}

private bool checkExcluded(const ref MappingEntry entry, out string error)
{
    if (!validCategory(entry.category))
        error = entry.match ~ ": an excluded element needs a rulebook `category`: jvm-runtime, jvm-platform, "
            ~ "runtime-reflection, packaging, devtools, jvm-language or deferred";
    else if (entry.category == "deferred" && entry.phase.length == 0)
        error = entry.match ~ ": a deferred element must name its `phase`";
    return error.length == 0;
}

/// Whether `category` is one of the rulebook's exclusion categories.
bool validCategory(string category)
{
    foreach (known; exclusionCategories)
    {
        if (known == category)
            return true;
    }
    return false;
}

/// The rulebook version stated in `docs/spring/api-mapping.md` (`Rulebook version: **N**.`), or zero.
uint rulebookVersion(string rulebookText)
{
    import std.conv : ConvException, to;
    import std.string : indexOf;

    enum marker = "Rulebook version: **";
    const at = rulebookText.indexOf(marker);
    if (at < 0)
        return 0;
    const start = cast(size_t) at + marker.length;
    size_t end = start;
    while (end < rulebookText.length && rulebookText[end] >= '0' && rulebookText[end] <= '9')
        end++;
    try
        return rulebookText[start .. end].to!uint;
    catch (ConvException)
        return 0;
}

/// Whether `symbol` names a D symbol in Flint: `flint.` then dotted identifiers.
bool validSymbol(string symbol)
{
    import std.algorithm.searching : startsWith;

    if (!symbol.startsWith("flint.") || symbol.length == "flint.".length)
        return false;
    bool start = true;
    foreach (c; symbol)
    {
        if (c == '.')
        {
            if (start)
                return false;
            start = true;
            continue;
        }
        const letter = c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_';
        if (!letter && !(c >= '0' && c <= '9' && !start))
            return false;
        start = false;
    }
    return !start;
}

/// Whether `rule` is a rulebook rule id, `R1` to `R14`, `R16` or `R17` (R15 is reserved for a proposal).
bool validRule(string rule)
{
    import std.conv : ConvException, to;

    if (rule.length < 2 || rule.length > 3 || rule[0] != 'R' || rule[1] == '0')
        return false;
    try
    {
        const number = rule[1 .. $].to!uint;
        return (number >= 1 && number <= 14) || number == 16 || number == 17;
    }
    catch (ConvException)
        return false;
}

/// Whether `id` matches `pattern`.
bool matches(string pattern, string id)
{
    if (pattern.length == 0)
        return id.length == 0;
    if (pattern.length >= 2 && pattern[0 .. 2] == "**")
    {
        foreach (start; 0 .. id.length + 1)
        {
            if (matches(pattern[2 .. $], id[start .. $]))
                return true;
        }
        return false;
    }
    if (pattern[0] == '*')
    {
        foreach (start; 0 .. id.length + 1)
        {
            if (start && isSeparator(id[start - 1]))
                return false;
            if (matches(pattern[1 .. $], id[start .. $]))
                return true;
        }
        return false;
    }
    return id.length && id[0] == pattern[0] && matches(pattern[1 .. $], id[1 .. $]);
}

private bool isSeparator(char c) pure nothrow @nogc
{
    return c == '.' || c == '#' || c == '(' || c == ')' || c == ',';
}

/// Index of mapping entries: exact ids in a table, patterns ranked by specificity.
struct Classifier
{
    private size_t[string] exact;
    private size_t[] patterns;
    private const(MappingEntry)[] entries;

    /// Build the index.
    this(const ref Mapping mapping)
    {
        import std.algorithm.sorting : sort;

        entries = mapping.entries;
        foreach (index, ref entry; mapping.entries)
        {
            if (literalPrefix(entry.match) == entry.match.length)
                exact[entry.match] = index;
            else
                patterns ~= index;
        }
        auto ranked = patterns;
        sort!((a, b) => moreSpecific(entries[a].match, entries[b].match))(ranked);
        patterns = ranked;
    }

    /// The entry that classifies `id`, or null.
    const(MappingEntry)* classify(string id) const
    {
        if (auto index = id in exact)
            return &entries[*index];
        foreach (index; patterns)
        {
            if (matches(entries[index].match, id))
                return &entries[index];
        }
        return null;
    }
}

/// Whether pattern `a` ranks before `b`: longer literal prefix, then fewer `**`, then longer, then by text.
bool moreSpecific(string a, string b)
{
    import std.algorithm.searching : count;

    const prefixA = literalPrefix(a);
    const prefixB = literalPrefix(b);
    if (prefixA != prefixB)
        return prefixA > prefixB;
    const deepA = a.count("**");
    const deepB = b.count("**");
    if (deepA != deepB)
        return deepA < deepB;
    if (a.length != b.length)
        return a.length > b.length;
    return a < b;
}

private size_t literalPrefix(string pattern)
{
    foreach (index, c; pattern)
    {
        if (c == '*')
            return index;
    }
    return pattern.length;
}

/// Classify every element of a manifest.
ManifestCoverage coverage(const ref Manifest manifest, const ref Classifier classifier)
{
    import std.algorithm.sorting : sort;
    import flint_tool.api.manifest : memberId;

    ManifestCoverage result;
    result.project = manifest.project;
    result.version_ = manifest.version_;
    result.summary.name = manifest.project;
    Tally[string] modules;
    void record(string module_, string id)
    {
        const entry = classifier.classify(id);
        const status = entry is null ? Status.unclassified : entry.status;
        result.summary.count(status);
        auto tally = module_ in modules;
        if (tally is null)
        {
            modules[module_] = Tally(module_);
            tally = module_ in modules;
        }
        tally.count(status);
        if (status == Status.unclassified)
            result.unclassified ~= id;
    }

    foreach (ref type; manifest.types)
    {
        record(type.module_, type.decl.id);
        foreach (ref member; type.decl.members)
            record(type.module_, memberId(type.decl, member));
    }
    result.modules = modules.values;
    sort!((a, b) => a.name < b.name)(result.modules);
    return result;
}

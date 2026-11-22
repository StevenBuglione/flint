/// The API index (ADR-021 section 6, ADR-026): every public symbol of the pinned Flint libraries, with its exact
/// signature, documentation, location and tested examples, generated offline by the pinned compiler.
///
/// The forked DMD writes each package's symbols with `-X -D -o-` (signatures, DDoc and locations, from the same
/// semantic analysis that compiles it). Examples are the unittest blocks of the package's own tests that use the
/// symbol, so every example shown is compiled and run by `flint test`. The index is cached under the Flint home by
/// the hash of the library sources.
module flint_tool.engine.apiindex;

import flint_tool.diagnostics.report : Report;
import flint_tool.engine.session : Session;
import flint_tool.home.policy : Home;

@safe:

/// Index schema.
enum indexSchema = "flint.api-index/1";

/// One tested example.
struct Example
{
    /// Path relative to the Flint home.
    string file;
    /// One-based line of the unittest.
    long line;
    /// The unittest block.
    string code;
}

/// One public symbol.
struct Symbol
{
    /// Fully qualified name, such as flint.os.run.
    string qualified;
    /// Simple name.
    string name;
    /// function, struct, class, interface, enum, enum member, alias, variable, template, constructor.
    string kind;
    /// Owning package, such as os.
    string package_name;
    /// Module.
    string module_name;
    /// The declaration as written: return type, name, parameters and attributes.
    string signature;
    /// DDoc comment.
    string comment;
    /// Path relative to the Flint home.
    string file;
    /// One-based line.
    long line;
    /// Tested examples.
    Example[] examples;
}

/// One package in the index.
struct PackageEntry
{
    /// Package name.
    string name;
    /// Public module root.
    string module_name;
    /// Package description.
    string description;
    /// Public symbols.
    long symbols;
    /// Symbols with at least one tested example.
    long with_examples;
    /// Why the compiler could not describe it, if it could not.
    string problem;
}

/// The whole index.
struct ApiIndex
{
    /// Schema.
    string schema = indexSchema;
    /// Flint release.
    string release;
    /// Hash of the library sources it describes.
    string sources_sha256;
    /// Packages.
    PackageEntry[] packages;
    /// Symbols, by qualified name.
    Symbol[] symbols;
}

/// The cached index for this installation, building it when the library sources changed.
bool loadIndex(ref Session session, out ApiIndex index, ref Report report)
{
    import std.file : exists, mkdirRecurse;
    import std.path : buildPath;
    import flint_tool.support.files : readIfPresent, writeIfChanged;

    const digest = sourcesDigest(session.home);
    const directory = buildPath(session.home.root, ".flint", "index");
    const path = buildPath(directory, "api-" ~ digest[0 .. 16] ~ ".jsonl");
    if (exists(path) && readCache(readIfPresent(path), digest, index))
        return true;
    session.progress("Indexing", "the API of " ~ countText(session.home.packages.length) ~ " with the pinned compiler");
    if (!buildIndex(session, digest, index, report))
        return false;
    mkdirRecurse(directory);
    string text;
    if (writeCache(index, text))
        writeIfChanged(path, text);
    else
        report.warning("FLINT-E0809", "the API index could not be cached", "it is rebuilt on every use");
    return true;
}

/// The cache is JSON Lines: the index without its symbols, then one symbol per line. Each document stays within
/// flint.serde's per-document limits however large the API grows.
private bool writeCache(const ref ApiIndex index, out string text)
{
    import flint.serde.owned : serialize;

    ApiIndex header;
    header.release = index.release;
    header.sources_sha256 = index.sources_sha256;
    header.packages = index.packages.dup;
    const first = serialize(header);
    if (!first.ok)
        return false;
    text = first.value ~ "\n";
    foreach (ref symbol; index.symbols)
    {
        auto line = serialize(symbol);
        if (!line.ok)
            return false;
        text ~= line.value ~ "\n";
    }
    return true;
}

private bool readCache(string text, string digest, out ApiIndex index)
{
    import std.string : lineSplitter;
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;

    DecodeOptions options;
    options.unknownFields = UnknownFields.ignore;
    bool first = true;
    foreach (line; text.lineSplitter)
    {
        if (first)
        {
            const header = deserialize!ApiIndex(line, options);
            if (!header.ok || header.value.sources_sha256 != digest || header.value.schema != indexSchema)
                return false;
            index.release = header.value.release;
            index.sources_sha256 = header.value.sources_sha256;
            foreach (ref entry; header.value.packages)
                index.packages ~= PackageEntry(entry.name, entry.module_name, entry.description,
                        entry.symbols, entry.with_examples, entry.problem);
            first = false;
            continue;
        }
        auto symbol = deserialize!Symbol(line, options);
        if (!symbol.ok)
            return false;
        index.symbols ~= symbol.value;
    }
    return !first;
}

private string countText(size_t count)
{
    import std.conv : to;

    return count.to!string ~ " packages";
}

/// Hash of every package's sources, tests and recipe: the index is current while it is unchanged.
string sourcesDigest(const ref Home home)
{
    import std.path : buildPath;
    import flint_tool.project.resolve : contentHash;
    import flint_tool.support.files : sha256Hex;

    string records = home.platform.release ~ "\n";
    foreach (ref item; home.packages)
        records ~= item.name ~ " " ~ contentHash(buildPath(home.root, "packages", item.name),
                ["dub.sdl", "source/**", "tests/**"]) ~ "\n";
    return sha256Hex(cast(const(ubyte)[]) records);
}

/// Build the index: the compiler describes each package, then examples are attached.
bool buildIndex(ref Session session, string digest, out ApiIndex index, ref Report report)
{
    import std.algorithm.sorting : sort;
    import std.file : exists, mkdirRecurse, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import flint_tool.toolchain.toolchain : componentPath, toolchainDirectory;

    index.release = session.home.platform.release;
    index.sources_sha256 = digest;
    const dmd = componentPath(session.home, toolchainDirectory(session.home), "dmd");
    if (!exists(dmd))
    {
        report.error("FLINT-E0802", "the pinned DMD is missing (" ~ dmd ~ "); it describes the API",
                "flint toolchain install");
        return false;
    }
    const scratch = buildPath(tempDir(), "flint-index-" ~ randomUUID().toString());
    mkdirRecurse(scratch);
    scope (exit)
        rmdirRecurse(scratch);
    foreach (ref item; session.home.packages)
    {
        PackageEntry entry;
        entry.name = item.name;
        entry.module_name = item.module_;
        entry.description = packageDescription(session.home, item.name);
        Symbol[] found;
        entry.problem = describePackage(session.home, dmd, item.name, scratch, found);
        attachExamples(session.home, item.name, found);
        foreach (ref symbol; found)
            entry.with_examples += symbol.examples.length > 0;
        entry.symbols = cast(long) found.length;
        index.symbols ~= found;
        index.packages ~= entry;
    }
    sort!((a, b) => a.qualified < b.qualified)(index.symbols);
    return true;
}

private string packageDescription(const ref Home home, string name)
{
    import std.algorithm.searching : startsWith;
    import std.array : replace;
    import std.path : buildPath;
    import std.string : indexOf, lineSplitter, strip;
    import flint_tool.support.files : readIfPresent;

    // The package module's own leading doc comment.
    const module_ = home.find(name).module_;
    const relative = module_.replace(".", "/");
    foreach (candidate; [relative ~ "/package.d", relative ~ ".d"])
    {
        string summary;
        foreach (line; readIfPresent(buildPath(home.root, "packages", name, "source", candidate)).lineSplitter)
        {
            const text = line.strip;
            if (!text.startsWith("///"))
                break;
            summary ~= (summary.length ? " " : "") ~ text[3 .. $].strip;
        }
        if (summary.length)
            return summary;
    }
    foreach (line; readIfPresent(buildPath(home.root, "packages", name, "dub.sdl")).lineSplitter)
    {
        const text = line.strip;
        if (text.length > 13 && text[0 .. 12] == "description ")
            return text[13 .. $ - 1].idup;
    }
    return null;
}

/// The JSON the compiler writes.
private struct CompilerParameter
{
    string name;
    string kind;
    string type;
}

private struct CompilerSymbol
{
    string name;
    string kind;
    string[] selective;
    string file;
    string protection;
    long line;
    string comment;
    string originalType;
    string type;
    CompilerParameter[] parameters;
    CompilerSymbol[] members;
}

/// Run the compiler over one package's public modules; returns a problem description, or null.
private string describePackage(const ref Home home, string dmd, string name, string scratch, ref Symbol[] found)
{
    import std.path : buildPath;
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import flint_tool.support.files : findFiles, readIfPresent;
    import flint_tool.support.process : Launch, capture;

    const source = buildPath(home.root, "packages", name, "source");
    // Every module is described: public modules often re-export internal declarations.
    string[] files;
    foreach (relative; findFiles(source, "**/*.d"))
        files ~= buildPath(source, relative);
    if (files.length == 0)
        return "no modules";
    const output = buildPath(scratch, name ~ ".json");
    string[] argv = [
        dmd, "-o-", "-D", "-Dd" ~ buildPath(scratch, "ddoc-" ~ name), "-X", "-Xf" ~ output,
        "-preview=dip1000", "-version=FlintApiIndex"
    ];
    foreach (dependency; home.closure([name]))
        argv ~= [
        "-I" ~ buildPath(home.root, "packages", dependency, "source"),
        "-J" ~ buildPath(home.root, "packages", dependency, "source")
    ];
    Launch launch;
    launch.directory = home.root;
    const result = capture(argv ~ files, launch);
    const text = readIfPresent(output);
    if (text is null)
        return "the compiler could not describe it: " ~ firstLine(result.combined());
    DecodeOptions options;
    options.unknownFields = UnknownFields.ignore;
    options.maxBytes = 256 << 20;
    auto decoded = deserialize!(CompilerSymbol[])(text, options);
    if (!decoded.ok)
        return "unreadable compiler description: " ~ decoded.error.message;
    const(CompilerSymbol)*[string] modules;
    foreach (ref module_; decoded.value)
    {
        if (module_.kind == "module")
            modules[module_.name] = &module_;
    }
    foreach (ref module_; decoded.value)
    {
        if (module_.kind != "module" || privatePath(relativeFile(source, module_.file)))
            continue;
        const file = relativeFile(home.root, module_.file);
        foreach (ref member; module_.members)
        {
            // The compiler omits the protection of public imports and writes "private" for the others.
            if (member.kind == "import" && member.protection != "private")
                reexport(home.root, member, modules, name, module_.name, found);
            else
                collect(member, name, module_.name, module_.name, file, found);
        }
    }
    return null;
}

private string firstLine(string text)
{
    import std.string : lineSplitter, strip;

    foreach (line; text.lineSplitter)
    {
        if (line.strip.length)
            return line.strip.idup;
    }
    return "no output";
}

/// The declarations a public module re-exports with `public import`, under the public module's name.
private void reexport(string root, const ref CompilerSymbol import_,
        const(CompilerSymbol)*[string] modules, string package_, string publicModule, ref Symbol[] found)
{
    import std.algorithm.searching : canFind;

    const target = import_.name in modules;
    if (target is null)
        return;
    const file = relativeFile(root, (*target).file);
    foreach (ref member; (*target).members)
    {
        if (member.kind == "import" || (import_.selective.length && !import_.selective.canFind(member.name)))
            continue;
        collect(member, package_, publicModule, publicModule, file, found);
    }
}

/// Modules under sys/, ffi/ or internal/ are private to their package.
private bool privatePath(string relative)
{
    import std.algorithm.iteration : splitter;

    foreach (part; relative.splitter('/'))
    {
        if (part == "sys" || part == "ffi" || part == "internal")
            return true;
    }
    return false;
}

private string relativeFile(string root, string file)
{
    import std.algorithm.searching : startsWith;

    return file.startsWith(root ~ "/") ? file[root.length + 1 .. $] : file;
}

private void collect(const ref CompilerSymbol symbol, string package_, string module_, string scope_,
        string file, ref Symbol[] found)
{
    import std.algorithm.searching : canFind;

    static immutable string[] kinds = [
        "function", "struct", "class", "interface", "enum", "enum member", "alias", "variable",
        "template", "constructor", "union"
    ];
    if (symbol.kind == "import" || symbol.name.length == 0 || (symbol.protection.length
            && symbol.protection != "public" && symbol.protection != "export")
            || !kinds.canFind(symbol.kind) || symbol.name[0] == '_')
        return;
    Symbol entry;
    entry.name = symbol.name;
    entry.qualified = scope_ ~ "." ~ symbol.name;
    entry.kind = symbol.kind;
    entry.package_name = package_;
    entry.module_name = module_;
    entry.comment = symbol.comment;
    entry.file = file;
    entry.line = symbol.line;
    entry.signature = signatureOf(symbol);
    if (symbol.kind == "template" && symbol.members.length == 1 && symbol.members[0].name == symbol.name)
    {
        // An eponymous template: describe the function or type it declares, with its template parameters.
        entry.kind = symbol.members[0].kind;
        entry.comment = entry.comment.length ? entry.comment : symbol.members[0].comment;
        entry.signature = signatureOf(symbol.members[0], templateParameters(symbol));
        found ~= entry;
        foreach (ref member; symbol.members[0].members)
            collect(member, package_, module_, entry.qualified, file, found);
        return;
    }
    found ~= entry;
    foreach (ref member; symbol.members)
        collect(member, package_, module_, entry.qualified, file, found);
}

private string templateParameters(const ref CompilerSymbol symbol)
{
    import std.array : join;

    string[] names;
    foreach (ref parameter; symbol.parameters)
        names ~= parameter.name ~ (parameter.kind == "tuple" ? "..." : "");
    return "(" ~ names.join(", ") ~ ")";
}

/// The declaration as a reader writes it.
string signatureOf(const ref CompilerSymbol symbol, string templateList = null)
{
    import std.algorithm.searching : canFind;

    static immutable string[] types = ["struct", "class", "interface", "union", "enum"];
    const type = symbol.originalType.length ? symbol.originalType : symbol.type;
    if (symbol.kind == "function" || symbol.kind == "constructor")
        return functionSignature(type, symbol.kind == "constructor" ? "this" : symbol.name, templateList);
    if (types.canFind(symbol.kind))
        return symbol.kind ~ " " ~ symbol.name ~ templateList;
    if (symbol.kind == "template")
        return "template " ~ symbol.name ~ templateParameters(symbol);
    if (symbol.kind == "alias")
        return "alias " ~ symbol.name ~ templateList ~ (type.length ? " = " ~ type : "");
    if (symbol.kind == "variable")
        return type ~ " " ~ symbol.name;
    return symbol.name;
}

/// Insert `name` (and template parameters) before the parameter list of a compiler function type such as
/// `@safe Result!T(ref Context context) nothrow`.
string functionSignature(string type, string name, string templateList)
{
    if (type.length == 0)
        return name ~ templateList ~ "(...)";
    // The parameter list is the last top-level parenthesised group; attributes may follow it.
    long depth;
    long close = -1;
    foreach_reverse (i, ch; type)
    {
        if (ch == ')')
        {
            if (depth == 0 && close < 0)
                close = i;
            depth++;
        }
        else if (ch == '(')
        {
            depth--;
            if (depth == 0 && close >= 0)
            {
                const before = type[0 .. i];
                return before ~ (before.length && before[$ - 1] != ' ' ? " " : "") ~ name ~ templateList ~ type[i .. $];
            }
        }
    }
    return type ~ " " ~ name;
}

/// Attach the unittest blocks of the package's tests that use each symbol (up to three, shortest first).
private void attachExamples(const ref Home home, string package_, ref Symbol[] symbols)
{
    import std.algorithm.sorting : sort;
    import std.file : readText;
    import std.path : buildPath;
    import flint_tool.support.files : findFiles;

    const tests = buildPath(home.root, "packages", package_, "tests");
    Block[] blocks;
    foreach (relative; findFiles(tests, "**/*.d"))
        blocks ~= unittestBlocks(readText(buildPath(tests, relative)), "packages/" ~ package_ ~ "/tests/" ~ relative);
    if (blocks.length == 0)
        return;
    foreach (ref symbol; symbols)
    {
        if (symbol.kind == "enum member" || symbol.kind == "variable" || symbol.name.length < 3)
            continue;
        Block[] matches;
        foreach (ref block; blocks)
        {
            if (symbol.name in block.identifiers && block.imports(symbol.module_name))
                matches ~= block;
        }
        sort!((a, b) => a.code.length < b.code.length)(matches);
        foreach (ref block; matches[0 .. matches.length < 3 ? matches.length : 3])
            symbol.examples ~= Example(block.file, block.line, block.code);
    }
}

/// One unittest block of a test file.
struct Block
{
    /// File relative to the Flint home.
    string file;
    /// One-based line.
    long line;
    /// The source, with its attributes and doc comment line.
    string code;
    /// Identifiers it uses.
    bool[string] identifiers;
    /// Modules the file imports.
    string[] modules;

    /// Whether the file imports `module_` or its package.
    bool imports(string module_) const
    {
        import std.algorithm.searching : startsWith;

        foreach (imported; modules)
        {
            if (imported == module_ || module_.startsWith(imported ~ "."))
                return true;
        }
        return false;
    }
}

/// The unittest blocks of a source text, through the policy lexer.
Block[] unittestBlocks(string text, string file)
{
    import std.string : lineSplitter;
    import flint_tool.check.lexer : LexFailure, Token, tokenize;

    Token[] tokens;
    LexFailure failure;
    if (!tokenize(text, tokens, failure))
        return null;
    const modules = importedNames(tokens);
    Block[] blocks;
    foreach (i, ref token; tokens)
    {
        if (token.value != "unittest" || i + 1 >= tokens.length || tokens[i + 1].value != "{")
            continue;
        const end = closingBrace(tokens, i + 1);
        Block block;
        block.file = file;
        block.modules = modules.dup;
        const first = attributeStart(tokens, i);
        const start = lineStart(text, tokens[first].offset);
        block.line = cast(long) tokens[first].line;
        block.code = text[start .. tokens[end].offset + 1].idup;
        foreach (ref inner; tokens[i + 1 .. end])
        {
            if (identifier(inner.value))
                block.identifiers[inner.value] = true;
        }
        if (block.code.length <= 4000)
            blocks ~= block;
    }
    return blocks;
}

/// The modules a token stream imports.
private string[] importedNames(const imported!"flint_tool.check.lexer".Token[] tokens)
{
    string[] modules;
    foreach (i, ref token; tokens)
    {
        if (token.value != "import" || i + 1 >= tokens.length)
            continue;
        string name;
        foreach (ref part; tokens[i + 1 .. $])
        {
            if (part.value == ":" || part.value == ";" || part.value == ",")
                break;
            name ~= part.value;
        }
        modules ~= name;
    }
    return modules;
}

/// The index of the `}` that closes the `{` at `open`.
private size_t closingBrace(const imported!"flint_tool.check.lexer".Token[] tokens, size_t open)
{
    size_t depth;
    foreach (j; open .. tokens.length)
    {
        if (tokens[j].value == "{")
            depth++;
        else if (tokens[j].value == "}" && --depth == 0)
            return j;
    }
    return open;
}

private bool identifier(string value)
{
    if (value.length == 0)
        return false;
    const lower = value[0] | 0x20;
    return value[0] == '_' || (lower >= 'a' && lower <= 'z');
}

/// The index of the first token of the attributes (`@("name")`, `@safe`) before a unittest.
private size_t attributeStart(const imported!"flint_tool.check.lexer".Token[] tokens, size_t index)
{
    size_t start = index;
    while (start >= 1)
    {
        const previous = tokens[start - 1].value;
        if (previous == ")" || previous == "@" || previous == "@safe" || previous == "@system"
                || previous == "@trusted" || previous == "nothrow" || previous == "@nogc"
                || previous == "<literal>" || previous == "(" || previous == "pure")
            start--;
        else if (start >= 2 && tokens[start - 2].value == "@")
            start -= 2;
        else
            break;
    }
    return start;
}

private size_t lineStart(string text, size_t offset)
{
    while (offset > 0 && text[offset - 1] != '\n')
        offset--;
    return offset;
}

/// One search hit.
struct Hit
{
    /// Score; higher is better.
    long score;
    /// Index into the symbols.
    size_t index;
}

/// Rank symbols for a query: exact names first, then name prefixes, qualified-name and documentation matches.
Hit[] search(const ref ApiIndex index, string query, size_t limit)
{
    import std.algorithm.searching : canFind, endsWith, startsWith;
    import std.algorithm.sorting : sort;
    import std.array : split;
    import std.uni : toLower;

    const words = query.toLower.split;
    Hit[] hits;
    foreach (i, ref symbol; index.symbols)
    {
        const name = symbol.name.toLower;
        const qualified = symbol.qualified.toLower;
        const comment = symbol.comment.toLower;
        long score;
        foreach (word; words)
        {
            if (qualified == word || (qualified.endsWith("." ~ word) && name == word))
                score += 100;
            else if (name.startsWith(word))
                score += 40;
            else if (qualified.canFind(word))
                score += 20;
            else if (comment.canFind(word))
                score += 6;
            else
            {
                score = 0;
                break;
            }
        }
        if (score == 0)
            continue;
        score += symbol.examples.length ? 3 : 0;
        score -= cast(long)(symbol.qualified.length / 16);
        hits ~= Hit(score, i);
    }
    sort!((a, b) => a.score > b.score || (a.score == b.score
            && index.symbols[a.index].qualified < index.symbols[b.index].qualified))(hits);
    return hits[0 .. hits.length < limit ? hits.length : limit];
}

/// The position of the symbol with exactly this qualified name, or size_t.max.
size_t lookup(const ref ApiIndex index, string qualified)
{
    foreach (i, ref symbol; index.symbols)
    {
        if (symbol.qualified == qualified)
            return i;
    }
    return size_t.max;
}

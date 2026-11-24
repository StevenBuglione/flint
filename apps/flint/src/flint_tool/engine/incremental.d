/// Per-module incremental compilation for direct dev builds (ADR-030; owner priority 74a746d1).
///
/// Each root module compiles in its own job with the same flags (through the compile server when it runs), into
/// its own object, in parallel. A record beside the objects keeps each source's SHA-256. An edit recompiles the
/// sources whose text changed and every root module that imports one of them, directly or through other root
/// modules. A D importer can observe more than declarations: template and auto-function bodies, inlinable code,
/// manifest constants and any function it runs at compile time. So a change anywhere in a module's text, comments
/// included, counts as a change its importers see. A module nothing imports, a controller, recompiles alone.
///
/// A change to the compiler, any flag, version, import path, the contents of any string-imported file, or the
/// platform objects the program links (content-addressed, so a platform change renames them) recompiles every
/// module. Imports are read from the source text, conservatively: an import inside a comment-free version block
/// that is off still counts. Modules may not generate imports with mixins (AGENTS.md), so the scan sees them all.
module flint_tool.engine.incremental;

import flint.os : EnvVar;

@safe:

/// Part of the record's stamp: a change to the scheme recompiles everything.
private enum recordFormat = "flint.direct-modules/1";

/// What one incremental compile needs.
struct ModuleCompile
{
    /// The compiler.
    string compiler;
    /// SHA-256 of the compiler.
    string compilerSha256;
    /// Every flag of the compile except the sources and the output: profile and recipe flags, versions, paths, -c.
    string[] flags;
    /// The root modules' sources.
    string[] sources;
    /// String import directories: their files' contents are part of the stamp.
    string[] stringImportPaths;
    /// What the program links besides its objects; the platform objects are content-addressed.
    string[] linkerFiles;
    /// Where the compiler runs.
    string root;
    /// Where the objects and the record live.
    string objects;
    /// The compiler's environment.
    EnvVar[] environment;
    /// A static dev build's recorded compiles (direct.d's replay): each source's own command, run as it is, and
    /// the object it writes. Empty for a shared dev build, whose commands are the compiler, `flags`, `-of` and the
    /// source, each object under `objects`.
    string[][] commands;
    /// ditto
    string[] outputs;
}

/// What an incremental compile did.
struct ModuleOutcome
{
    /// Every object to link, in source order.
    string[] objects;
    /// How many modules compiled this time.
    size_t compiled;
}

/// Compile the root modules that changed, and their importers, in parallel. False when a compile failed; `output`
/// holds the compilers' output.
bool compileModules(const ref ModuleCompile request, out ModuleOutcome outcome, ref string output)
{
    import std.file : mkdirRecurse;
    import std.path : buildPath;

    mkdirRecurse(request.objects);
    string[] texts, shas, names;
    foreach (source; request.sources)
    {
        texts ~= readSource(source);
        shas ~= sourceSha(texts[$ - 1]);
        names ~= moduleName(texts[$ - 1], source, request.root);
    }
    if (request.commands.length)
        outcome.objects = request.outputs.dup;
    else
        foreach (name; names)
            outcome.objects ~= buildPath(request.objects, name ~ ".o");
    const record = buildPath(request.objects, "modules.txt");
    const stamp = recordStamp(request);
    const stale = staleModules(request.sources, texts, shas, names, outcome.objects, record, stamp);
    if (!request.commands.length)
        removeOrphans(request.objects, outcome.objects);
    outcome.compiled = stale.length;
    if (stale.length == 0)
        return true;
    const compiled = runJobs(request, stale, outcome.objects, output);
    writeRecord(record, stamp, request.sources, shas, compiled ? null : stale);
    return compiled;
}

/// Record every module as compiled, as DUB just compiled them all with `request.commands`, so the next build
/// recompiles only what changes. Nothing is recorded, and the next build compiles every module, when a source
/// changed after `since`, the time DUB started: its object may be older than its text.
void recordCompiled(const ref ModuleCompile request, imported!"std.datetime.systime".SysTime since)
{
    import std.file : FileException, mkdirRecurse, timeLastModified;
    import std.path : buildPath;

    mkdirRecurse(request.objects);
    const record = buildPath(request.objects, "modules.txt");
    string[] shas;
    try
    {
        foreach (source; request.sources)
        {
            if (timeLastModified(source) >= since)
                return removeIfPresent(record);
            shas ~= sourceSha(readSource(source));
        }
    }
    catch (FileException)
        return removeIfPresent(record);
    writeRecord(record, recordStamp(request), request.sources, shas, null);
}

private string readSource(string path)
{
    import flint_tool.support.files : readIfPresent;

    return readIfPresent(path);
}

private string sourceSha(string text)
{
    import flint_tool.support.files : sha256Hex;

    return sha256Hex(cast(const(ubyte)[]) text);
}

/// The module a source declares, or the one its path names under the project (an undeclared module).
private string moduleName(string text, string source, string root)
{
    import std.algorithm.searching : startsWith;
    import std.array : replace;
    import std.path : relativePath, stripExtension;

    const declared = declaredModule(text);
    if (declared.length)
        return declared;
    auto relative = source.startsWith("/") ? relativePath(source, root) : source;
    return relative.stripExtension.replace("/", ".").replace("..", "_");
}

/// The stamp every record carries: the compiler, every flag, the string-imported files' contents and the linked
/// platform objects.
private string recordStamp(const ref ModuleCompile request)
{
    import std.algorithm.sorting : sort;
    import std.array : join;
    import std.file : SpanMode, dirEntries, exists, isDir;
    import flint_tool.support.files : sha256File, sha256Hex;

    string text = recordFormat ~ "\n" ~ request.compiler ~ "\n" ~ request.compilerSha256 ~ "\n"
        ~ request.flags.join("\x1f") ~ "\n" ~ request.linkerFiles.join("\x1f") ~ "\n";
    string[] files;
    foreach (path; request.stringImportPaths)
    {
        if (!exists(path) || !isDir(path))
            continue;
        foreach (entry; dirEntries(path, SpanMode.depth))
        {
            if (entry.isFile)
                files ~= entry.name;
        }
    }
    sort(files);
    foreach (file; files)
        text ~= file ~ " " ~ sha256File(file) ~ "\n";
    return sha256Hex(cast(const(ubyte)[]) text);
}

/// The indices of the modules to compile: every one when the stamp changed, else those whose text changed or whose
/// object is missing, and every module that imports one of those through root modules.
private size_t[] staleModules(scope const string[] sources, scope const string[] texts,
        scope const string[] shas, scope const string[] names, scope const string[] objs, string record, string stamp)
{
    import std.file : exists;

    string[string] recorded;
    const current = readRecord(record, stamp, recorded);
    bool[] changed = new bool[sources.length];
    foreach (index, source; sources)
    {
        const old = source in recorded;
        changed[index] = !current || old is null || *old != shas[index] || !exists(objs[index]);
    }
    const graph = importGraph(texts, names);
    size_t[] stale;
    foreach (index; 0 .. sources.length)
    {
        if (reaches(index, graph, changed))
            stale ~= index;
    }
    return stale;
}

/// For each module, the root modules it imports.
private size_t[][] importGraph(scope const string[] texts, scope const string[] names)
{
    size_t[string] byName;
    foreach (index, name; names)
        byName[name] = index;
    size_t[][] graph = new size_t[][texts.length];
    foreach (index, text; texts)
    {
        foreach (imported; importedModules(text))
        {
            if (auto target = imported in byName)
            {
                if (*target != index)
                    graph[index] ~= *target;
            }
        }
    }
    return graph;
}

/// Whether `start` changed or imports, through root modules, one that did.
private bool reaches(size_t start, scope const size_t[][] graph, scope const bool[] changed)
{
    bool[] seen = new bool[graph.length];
    size_t[] pending = [start];
    while (pending.length)
    {
        const at = pending[$ - 1];
        pending = pending[0 .. $ - 1];
        if (seen[at])
            continue;
        seen[at] = true;
        if (changed[at])
            return true;
        pending ~= graph[at];
    }
    return false;
}

private bool readRecord(string record, string stamp, out string[string] shas)
{
    import std.algorithm.searching : findSplit;
    import std.string : lineSplitter;
    import flint_tool.support.files : readIfPresent;

    string[] lines;
    foreach (line; readIfPresent(record).lineSplitter)
        lines ~= line;
    if (lines.length < 2 || lines[0] != recordFormat || lines[1] != stamp)
        return false;
    foreach (line; lines[2 .. $])
    {
        auto parts = line.findSplit("\t");
        if (parts[1].length)
            shas[parts[2]] = parts[0];
    }
    return true;
}

/// The record: every module's SHA-256, except the `failed` ones, which compile again next time.
private void writeRecord(string record, string stamp, scope const string[] sources,
        scope const string[] shas, scope const size_t[] failed)
{
    import std.algorithm.searching : canFind;
    import std.conv : to;
    import std.file : rename, write;
    import std.process : thisProcessID;

    string text = recordFormat ~ "\n" ~ stamp ~ "\n";
    foreach (index, source; sources)
    {
        if (!failed.canFind(index))
            text ~= shas[index] ~ "\t" ~ source ~ "\n";
    }
    const partial = record ~ "." ~ thisProcessID.to!string ~ ".partial";
    write(partial, text);
    rename(partial, record);
}

/// Objects of modules the program no longer has: linking one would bring back a removed module.
private void removeOrphans(string objects, scope const string[] keep)
{
    import std.algorithm.searching : canFind;
    import std.file : SpanMode, dirEntries, remove;

    string[] orphans;
    foreach (entry; dirEntries(objects, "*.o", SpanMode.shallow))
    {
        if (!keep.canFind(entry.name))
            orphans ~= entry.name;
    }
    foreach (orphan; orphans)
        remove(orphan);
}

/// Compile the stale modules, each in its own job: one directly, several in parallel through xargs.
private bool runJobs(const ref ModuleCompile request, scope const size_t[] stale,
        scope const string[] objects, ref string output)
{
    import flint_tool.support.process : Launch, capture;

    Launch launch;
    launch.directory = request.root;
    launch.environment = request.environment.dup;
    launch.inherit = false;
    if (stale.length == 1)
    {
        const outcome = capture(job(request, stale[0], objects), launch);
        output ~= outcome.combined;
        return outcome.ok;
    }
    return parallelJobs(request, stale, objects, launch, output);
}

private string[] job(const ref ModuleCompile request, size_t index, scope const string[] objects)
{
    if (request.commands.length)
        return request.commands[index].dup;
    return [request.compiler] ~ request.flags.dup ~ ["-of" ~ objects[index], request.sources[index]];
}

private bool parallelJobs(const ref ModuleCompile request, scope const size_t[] stale,
        scope const string[] objects, imported!"flint_tool.support.process".Launch launch, ref string output)
{
    import std.conv : to;
    import std.file : remove, write;
    import std.path : buildPath;
    import std.string : strip;
    import flint_tool.support.files : readIfPresent;
    import flint_tool.support.process : capture;

    const jobs = buildPath(request.objects, "jobs.txt");
    string script;
    foreach (position, index; stale)
    {
        const stem = buildPath(request.objects, "job-" ~ position.to!string);
        script ~= shellCommand(job(request, index, objects)) ~ " >" ~ shellQuote(
                stem ~ ".log") ~ " 2>&1; echo $? >" ~ shellQuote(stem ~ ".status") ~ "\n";
    }
    write(jobs, script);
    const parallel = stale.length < processors() ? stale.length : processors();
    const ran = capture([
        "xargs", "-d", "\\n", "-P", parallel.to!string, "-a", jobs, "-I{}", "sh", "-c", "{}"
    ], launch);
    bool ok = ran.ok;
    output ~= ran.combined;
    foreach (position; 0 .. stale.length)
    {
        const stem = buildPath(request.objects, "job-" ~ position.to!string);
        output ~= readIfPresent(stem ~ ".log");
        ok = ok && readIfPresent(stem ~ ".status").strip == "0";
        foreach (file; [stem ~ ".log", stem ~ ".status"])
            removeIfPresent(file);
    }
    remove(jobs);
    return ok;
}

private void removeIfPresent(string path)
{
    import std.file : exists, remove;

    if (exists(path))
        remove(path);
}

/// The host's online processors.
private size_t processors()
{
    version (Posix)
    {
        import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;

        const online = sysconf(_SC_NPROCESSORS_ONLN);
        return online >= 1 ? cast(size_t) online : 1;
    }
    else
        return 1;
}

private string shellCommand(scope const string[] argv)
{
    string text;
    foreach (index, argument; argv)
        text ~= (index ? " " : "") ~ shellQuote(argument);
    return text;
}

/// `text` as one POSIX shell word.
string shellQuote(string text) pure
{
    import std.array : replace;

    return "'" ~ text.replace("'", `'\''`) ~ "'";
}

/// The module a D source declares (`module a.b;`), or null.
string declaredModule(string text) pure
{
    const code = withoutCommentsAndStrings(text);
    size_t at = skipSpace(code, 0);
    // Attributes such as `deprecated("...")` may precede the declaration; module is then still the first keyword.
    const found = keywordAt(code, "module", at);
    if (found == size_t.max)
        return null;
    return qualifiedName(code, skipSpace(code, found + "module".length));
}

/// The modules a D source imports, in order, without duplicates: plain, renamed, selective, static and public
/// imports, at module scope or inside functions. `import("file")` is a string import, not a module.
string[] importedModules(string text) pure
{
    import std.algorithm.searching : canFind;

    const code = withoutCommentsAndStrings(text);
    string[] found;
    size_t at = 0;
    while ((at = keywordAt(code, "import", at)) != size_t.max)
    {
        size_t cursor = skipSpace(code, at + "import".length);
        at = cursor;
        if (cursor < code.length && code[cursor] == '(')
            continue;
        foreach (name; importList(code, cursor))
        {
            if (!found.canFind(name))
                found ~= name;
        }
    }
    return found;
}

/// The module names of one import declaration starting at `cursor`: `a.b, c = d.e : f`.
private string[] importList(string code, size_t cursor) pure
{
    string[] names;
    for (;;)
    {
        cursor = skipSpace(code, cursor);
        auto name = qualifiedName(code, cursor);
        if (name.length == 0)
            return names;
        cursor = skipSpace(code, cursor + name.length);
        if (cursor < code.length && code[cursor] == '=')
        {
            cursor = skipSpace(code, cursor + 1);
            name = qualifiedName(code, cursor);
            cursor = skipSpace(code, cursor + name.length);
        }
        if (name.length)
            names ~= name;
        if (cursor >= code.length || code[cursor] != ',')
            return names; // `;` or `:` (the selective list names symbols, not modules)
        ++cursor;
    }
}

/// The index of the keyword at or after `from` as a whole word, or size_t.max.
private size_t keywordAt(string code, string keyword, size_t from) pure
{
    import std.string : indexOf;

    while (from < code.length)
    {
        const found = code[from .. $].indexOf(keyword);
        if (found < 0)
            return size_t.max;
        const at = from + cast(size_t) found;
        const end = at + keyword.length;
        if ((at == 0 || !identifierChar(code[at - 1])) && (end >= code.length || !identifierChar(code[end])))
            return at;
        from = end;
    }
    return size_t.max;
}

private string qualifiedName(string code, size_t at) pure
{
    size_t end = at;
    while (end < code.length && (identifierChar(code[end]) || code[end] == '.'))
        ++end;
    return code[at .. end];
}

private size_t skipSpace(string code, size_t at) pure
{
    while (at < code.length && (code[at] == ' ' || code[at] == '\t' || code[at] == '\n' || code[at] == '\r'))
        ++at;
    return at;
}

private bool identifierChar(char c) pure
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c >= 0x80;
}

/// `text` with comments and string, character and token literals replaced by spaces, so keywords inside them are
/// not seen; newlines are kept.
string withoutCommentsAndStrings(string text) pure
{
    char[] code = text.dup;
    size_t at = 0;
    while (at < code.length)
    {
        const skipped = literalEnd(code, at);
        if (skipped == at)
        {
            ++at;
            continue;
        }
        foreach (ref c; code[at .. skipped])
        {
            if (c != '\n')
                c = ' ';
        }
        at = skipped;
    }
    return code.idup;
}

/// Where the comment or literal starting at `at` ends, or `at` when none starts there.
private size_t literalEnd(scope const char[] code, size_t at) pure
{
    const comment = commentEnd(code, at);
    return comment != at ? comment : quotedEnd(code, at);
}

private size_t commentEnd(scope const char[] code, size_t at) pure
{
    if (code[at] != '/' || at + 1 >= code.length)
        return at;
    if (code[at + 1] == '/')
        return untilAfter(code, at + 2, "\n");
    if (code[at + 1] == '*')
        return untilAfter(code, at + 2, "*/");
    return code[at + 1] == '+' ? nestedCommentEnd(code, at) : at;
}

private size_t quotedEnd(scope const char[] code, size_t at) pure
{
    const next = at + 1 < code.length ? code[at + 1] : '\0';
    const wordStart = at == 0 || !identifierChar(code[at - 1]);
    if ((code[at] == 'r' || code[at] == 'q') && next == '"' && wordStart)
        return untilAfter(code, at + 2, "\"");
    if (code[at] == 'q' && next == '{' && wordStart)
        return tokenStringEnd(code, at + 1);
    if (code[at] == '`')
        return untilAfter(code, at + 1, "`");
    if (code[at] == '"' || code[at] == '\'')
        return escapedEnd(code, at + 1, code[at]);
    return at;
}

private size_t untilAfter(scope const char[] code, size_t from, string terminator) pure
{
    import std.string : indexOf;

    const found = (cast(const(char)[]) code[from .. $]).indexOf(terminator);
    return found < 0 ? code.length : from + cast(size_t) found + terminator.length;
}

private size_t escapedEnd(scope const char[] code, size_t from, char quote) pure
{
    while (from < code.length && code[from] != quote)
        from += code[from] == '\\' ? 2 : 1;
    return from < code.length ? from + 1 : code.length;
}

private size_t nestedCommentEnd(scope const char[] code, size_t at) pure
{
    size_t depth = 0;
    while (at + 1 < code.length)
    {
        if (code[at] == '/' && code[at + 1] == '+')
        {
            ++depth;
            at += 2;
        }
        else if (code[at] == '+' && code[at + 1] == '/')
        {
            at += 2;
            if (--depth == 0)
                return at;
        }
        else
            ++at;
    }
    return code.length;
}

private size_t tokenStringEnd(scope const char[] code, size_t open) pure
{
    size_t depth = 0;
    for (size_t at = open; at < code.length; ++at)
    {
        if (code[at] == '{')
            ++depth;
        else if (code[at] == '}' && --depth == 0)
            return at + 1;
    }
    return code.length;
}

@("the import scan finds every import form and nothing in comments or strings")
unittest
{
    enum source = "/// Docs: import not.this;\nmodule app.main;\n\nimport std.stdio : writeln;\n"
        ~ "public import app.model, x = app.util;\nstatic import app.config;\n/* import no.block; */\n"
        ~ "/+ nested /+ import no.nested; +/ +/\nvoid f() { import app.local; enum s = \"import no.string;\"; "
        ~ "auto t = `import no.raw;`; enum c = import(\"file.txt\"); }\nstring importer;\n";
    assert(declaredModule(source) == "app.main");
    assert(importedModules(source) == [
        "std.stdio", "app.model", "app.util", "app.config", "app.local"
    ], "got " ~ importedModules(source)[0]);
    assert(declaredModule("void main() {}") is null);
    assert(shellQuote("it's") == `'it'\''s'`);
}

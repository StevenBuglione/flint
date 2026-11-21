module flint.os.globbing;

import flint.arena : Error, Result, Status;
import flint.os.sys.directories : Directory, EntryKind, checkSymlink, closeDirectory, descend, nextEntry, openRoot;
import flint.os.types : GlobOptions;
import std.algorithm.sorting : sort;

@safe:

private enum maxPathBytes = 4095;
private enum maxParts = 128;
private enum maxScannedEntries = 1_000_000;

private enum AtomKind : ubyte
{
    literal,
    one,
    star,
    characterClass
}

private struct Atom
{
    AtomKind kind;
    ubyte value;
    ulong[4] included;

    bool matches(ubyte candidate) const pure nothrow @nogc
    {
        if (kind == AtomKind.one)
            return true;
        if (kind == AtomKind.characterClass)
            return (included[candidate / 64] & (1UL << (candidate % 64))) != 0;
        return value == candidate;
    }

    void include(ubyte candidate) pure nothrow @nogc
    {
        included[candidate / 64] |= 1UL << (candidate % 64);
    }
}

private struct Segment
{
    bool recursive;
    Atom[] atoms;
}

private bool validPath(scope const(char)[] path) pure nothrow @nogc
{
    if (path.length == 0 || path.length > maxPathBytes)
        return false;
    foreach (character; path)
        if (character == '\0')
            return false;
    return true;
}

private struct PatternByte
{
    bool valid;
    ubyte value;
}

private PatternByte readEscaped(scope const(char)[] pattern, ref size_t cursor) pure nothrow @nogc
{
    if (cursor >= pattern.length)
        return PatternByte.init;
    if (pattern[cursor] == '\\')
    {
        ++cursor;
        if (cursor == pattern.length)
            return PatternByte.init;
    }
    return PatternByte(true, cast(ubyte) pattern[cursor++]);
}

private bool parseClass(scope const(char)[] pattern, ref size_t cursor, out Atom atom) pure nothrow @nogc
{
    atom.kind = AtomKind.characterClass;
    bool inverted;
    if (cursor < pattern.length && (pattern[cursor] == '!' || pattern[cursor] == '^'))
    {
        inverted = true;
        ++cursor;
    }

    bool haveElement;
    while (cursor < pattern.length && pattern[cursor] != ']')
    {
        if (!parseClassElement(pattern, cursor, atom))
            return false;
        haveElement = true;
    }

    if (!haveElement || cursor == pattern.length)
        return false;
    ++cursor;
    if (inverted)
        foreach (ref word; atom.included)
            word = ~word;
    return true;
}

private bool parseClassElement(scope const(char)[] pattern, ref size_t cursor, ref Atom atom) pure nothrow @nogc
{
    const first = readEscaped(pattern, cursor);
    if (!first.valid)
        return false;
    if (cursor + 1 >= pattern.length || pattern[cursor] != '-' || pattern[cursor + 1] == ']')
    {
        atom.include(first.value);
        return true;
    }

    ++cursor;
    const last = readEscaped(pattern, cursor);
    if (!last.valid || last.value < first.value)
        return false;
    foreach (value; cast(uint) first.value .. cast(uint) last.value + 1)
        atom.include(cast(ubyte) value);
    return true;
}

private bool parseSegment(scope const(char)[] pattern, out Segment segment)
{
    if (pattern.length == 0 || pattern == "." || pattern == "..")
        return false;
    if (pattern == "**")
    {
        segment.recursive = true;
        return true;
    }

    size_t cursor;
    while (cursor < pattern.length)
    {
        Atom atom;
        switch (pattern[cursor])
        {
        case '*':
            atom.kind = AtomKind.star;
            ++cursor;
            break;
        case '?':
            atom.kind = AtomKind.one;
            ++cursor;
            break;
        case '[':
            ++cursor;
            if (!parseClass(pattern, cursor, atom))
                return false;
            break;
        default:
            const literal = readEscaped(pattern, cursor);
            if (!literal.valid)
                return false;
            atom.value = literal.value;
            break;
        }
        segment.atoms ~= atom;
    }
    return true;
}

private Result!(Segment[]) compilePattern(scope const(char)[] pattern)
{
    if (!validPath(pattern))
        return Result!(Segment[])(null, Error(Status.invalidArgument, "invalid glob pattern"));

    Segment[] segments;
    size_t first;
    foreach (index, character; pattern)
    {
        if (character != '/')
            continue;
        Segment segment;
        if (segments.length == maxParts || !parseSegment(pattern[first .. index], segment))
            return Result!(Segment[])(null, Error(Status.invalidArgument, "invalid glob segment"));
        segments ~= segment;
        first = index + 1;
    }

    Segment last;
    if (segments.length == maxParts || !parseSegment(pattern[first .. $], last))
        return Result!(Segment[])(null, Error(Status.invalidArgument, "invalid glob segment"));
    segments ~= last;
    return Result!(Segment[])(segments);
}

private bool matchSegment(scope const(Atom)[] atoms, string name) pure nothrow @nogc
{
    size_t position;
    size_t atomIndex;
    size_t lastStar = size_t.max;
    size_t consumedByStar;
    while (position < name.length)
    {
        if (atomIndex < atoms.length && atoms[atomIndex].kind == AtomKind.star)
        {
            lastStar = atomIndex++;
            consumedByStar = position;
        }
        else if (atomIndex < atoms.length && atoms[atomIndex].matches(cast(ubyte) name[position]))
        {
            ++position;
            ++atomIndex;
        }
        else if (lastStar == size_t.max)
            return false;
        else
        {
            position = ++consumedByStar;
            atomIndex = lastStar + 1;
        }
    }

    while (atomIndex < atoms.length && atoms[atomIndex].kind == AtomKind.star)
        ++atomIndex;
    return atomIndex == atoms.length;
}

private alias States = bool[maxParts + 1];

private void epsilonClose(scope const(Segment)[] pattern, ref States active) pure nothrow @nogc
{
    foreach (index, ref segment; pattern)
        if (active[index] && segment.recursive)
            active[index + 1] = true;
}

private States advance(scope const(Segment)[] pattern, ref const States previous, string name) pure nothrow @nogc
{
    States next;
    foreach (index, ref segment; pattern)
    {
        if (!previous[index])
            continue;
        if (segment.recursive)
            next[index] = true;
        else if (matchSegment(segment.atoms, name))
            next[index + 1] = true;
    }
    epsilonClose(pattern, next);
    return next;
}

private struct Frame
{
    Directory directory;
    string relativePath;
    States states;
}

private bool traversable(EntryKind kind, bool follow) pure nothrow @nogc
{
    return kind == EntryKind.directory || kind == EntryKind.unknown || (kind == EntryKind.symlink && follow);
}

private bool ancestorCycle(scope const(Frame)[] ancestors, ref const Directory candidate) pure nothrow @nogc
{
    foreach (ref parent; ancestors)
        if (parent.directory.identity == candidate.identity)
            return true;
    return false;
}

private struct Search
{
    private Segment[] pattern;
    private GlobOptions options;
    private Frame[65] frames;
    private size_t depth;
    private size_t visited;
    private string[] matches;

    Error enumerate()
    {
        while (true)
        {
            const entry = nextEntry(frames[depth].directory);
            if (!entry.ok)
                return entry.error;
            if (entry.value.name.length == 0)
            {
                closeDirectory(frames[depth].directory);
                if (depth == 0)
                    return Error.init;
                --depth;
                continue;
            }
            if (entry.value.name == "." || entry.value.name == "..")
                continue;
            if (++visited > maxScannedEntries)
                return Error(Status.resourceExhausted, "glob scanned entry limit reached");
            const failure = visit(entry.value.name, entry.value.kind);
            if (failure.code != Status.ok)
                return failure;
        }
    }

    private Error visit(string name, EntryKind kind)
    {
        const next = advance(pattern, frames[depth].states, name);
        const matched = next[pattern.length];
        const recurse = canDescend(next, kind);
        if (!matched && !recurse)
            return Error.init;
        if (depth == options.maxDepth)
            return Error(Status.resourceExhausted, "glob depth limit reached");

        const parent = frames[depth].relativePath;
        const relative = parent.length == 0 ? name : parent ~ "/" ~ name;
        if (relative.length > maxPathBytes)
            return Error(Status.resourceExhausted, "glob resolved path too long");
        const nativePath = relative ~ "\0";
        const inside = verifyEntry(nativePath, kind);
        if (inside.code != Status.ok)
            return inside.code == Status.notFound ? Error.init : inside;

        if (matched)
        {
            if (matches.length == options.maxResults)
                return Error(Status.resourceExhausted, "glob result limit reached");
            matches ~= relative;
        }
        if (!recurse)
            return Error.init;
        return addDirectory(nativePath, relative, next);
    }

    private Error verifyEntry(string nativePath, EntryKind kind) nothrow @nogc
    {
        if (options.followSymlinks && (kind == EntryKind.symlink || kind == EntryKind.unknown))
            return checkSymlink(frames[0].directory, nativePath);
        return Error.init;
    }

    private bool canDescend(ref const States next, EntryKind kind) const pure nothrow @nogc
    {
        if (!traversable(kind, options.followSymlinks))
            return false;
        foreach (index; 0 .. pattern.length)
            if (next[index])
                return true;
        return false;
    }

    private Error addDirectory(string path, string relative, States states)
    {
        auto child = descend(frames[0].directory, path, options.followSymlinks);
        if (!child.ok)
            return child.error.code == Status.notFound ? Error.init : child.error;
        if (ancestorCycle(frames[0 .. depth + 1], child.value))
        {
            closeDirectory(child.value);
            return Error.init;
        }

        ++depth;
        frames[depth] = Frame(child.value, relative, states);
        return Error.init;
    }
}

package(flint.os) Result!(string[]) searchGlob(scope const(char)[] root, scope const(char)[] pattern,
        GlobOptions options)
{
    if (!validPath(root) || options.maxDepth > 64 || options.maxResults > 100_000)
        return Result!(string[])(null, Error(Status.invalidArgument, "invalid glob root or limits"));
    auto compiled = compilePattern(pattern);
    if (!compiled.ok)
        return Result!(string[])(null, compiled.error);
    auto opened = openRoot(root.idup ~ "\0");
    if (!opened.ok)
        return Result!(string[])(null, opened.error);

    auto search = new Search;
    search.pattern = compiled.value;
    search.options = options;
    search.frames[0].directory = opened.value;
    search.frames[0].states[0] = true;
    epsilonClose(search.pattern, search.frames[0].states);
    scope (exit)
        foreach (ref frame; search.frames)
            closeDirectory(frame.directory);

    const status = search.enumerate();
    if (status.code != Status.ok)
        return Result!(string[])(null, status);
    search.matches.sort;
    return Result!(string[])(search.matches);
}

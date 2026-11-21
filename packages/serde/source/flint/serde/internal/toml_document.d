/// Bounded document index for TOML tables, dotted assignments and scalar spans.
module flint.serde.internal.toml_document;

import flint.arena : Error, Status;
import flint.serde.internal.json_scan : digit, readUtf8;
import flint.serde.internal.toml_text : Span, horizontal, keySpan, quotedSpan, sameKey;
import flint.serde.internal.toml_values : ScalarKind, classify;
import flint.serde.internal.types : DecodeOptions;

@safe:

/// Table provenance matters when JSON-style inline objects meet TOML headers.
enum NodeKind : ubyte
{
    implicitTable,
    namedTable,
    dottedTable,
    inlineTable,
    array,
    tableArray,
    tableElement,
    scalar
}

/// One input span or one container in the TOML document.
struct Node
{
    /// Name span, or an empty span for array entries.
    Span key;
    /// Raw scalar token.
    Span token;
    /// Most recently read child.
    ushort first;
    /// Next earlier sibling in source order.
    ushort next;
    /// Number of direct entries.
    ushort count;
    /// Container depth relative to the document root.
    ubyte depth;
    /// Node kind and table provenance.
    NodeKind kind;
    /// Scalar type, when this is a leaf.
    ScalarKind scalar;
}

/// Index of the implicit root table.
enum ushort rootNode = 1;

/// TOML parsing uses a fixed index and refers back to validated source bytes.
struct Document
{
    /// Borrowed UTF-8 input.
    const(ubyte)[] input;
    /// Active limits and unknown-field policy.
    DecodeOptions options;
    private enum nodeCapacity = 1_536;
    private Node[nodeCapacity + 1] nodes;
    private ushort allocated = rootNode;
    private size_t offset;

    /// Keep input alive during indexing and binding.
    this(return scope const(ubyte)[] input, DecodeOptions options) nothrow @nogc
    {
        this.input = input;
        this.options = options;
    }

    /// Fetch a cheap metadata copy.
    Node node(ushort index) const scope nothrow @nogc
    {
        return nodes[index];
    }

    /// Scan and index every statement before any caller storage is modified.
    Error parse() scope nothrow @nogc
    {
        if (options.maxDepth == 0)
            return exhausted("TOML depth limit exceeded");

        ushort current = rootNode;
        while (offset < input.length)
        {
            spaces();
            if (offset == input.length)
                break;
            if (lineEnding())
                continue;

            Error failure;
            if (peek() == '#')
                failure = comment();
            else if (take('['))
                failure = header(take('['), current);
            else
                failure = assignment(current);
            if (failure.code != Status.ok)
                return failure;

            spaces();
            if (peek() == '#')
            {
                failure = comment();
                if (failure.code != Status.ok)
                    return failure;
            }
            if (offset != input.length && !lineEnding())
                return invalid("unexpected trailing TOML statement input");
        }
        return Error.init;
    }

    private Error header(bool arrayTable, ref ushort current) scope nothrow @nogc
    {
        Span[64] path;
        size_t count;
        auto failure = keyPath(path, count);
        if (failure.code != Status.ok)
            return failure;
        if (!take(']') || (arrayTable && !take(']')))
            return invalid("unterminated TOML table header");

        current = rootNode;
        foreach (name; path[0 .. count - 1])
        {
            ushort child = find(current, name);
            if (child == 0)
            {
                failure = append(current, name, NodeKind.implicitTable, child);
                if (failure.code != Status.ok)
                    return failure;
            }
            if (nodes[child].kind == NodeKind.tableArray)
                child = nodes[child].first;
            if (!headerChild(nodes[child].kind))
                return invalid("TOML table path redefines an existing value");
            current = child;
        }
        return completeHeader(path[count - 1], arrayTable, current);
    }

    private Error completeHeader(Span name, bool arrayTable, ref ushort current) scope nothrow @nogc
    {
        ushort child = find(current, name);
        if (child == 0)
        {
            const kind = arrayTable ? NodeKind.tableArray : NodeKind.namedTable;
            const failure = append(current, name, kind, child);
            if (failure.code != Status.ok)
                return failure;
        }
        else if (arrayTable)
        {
            if (nodes[child].kind != NodeKind.tableArray)
                return invalid("TOML table array cannot redefine an existing value");
        }
        else
        {
            if (nodes[child].kind != NodeKind.implicitTable)
                return invalid("duplicate or conflicting TOML table");
            nodes[child].kind = NodeKind.namedTable;
        }

        current = child;
        if (arrayTable)
            return append(child, Span.init, NodeKind.tableElement, current);
        return Error.init;
    }

    private Error assignment(ushort parent) scope nothrow @nogc
    {
        Span[64] path;
        size_t count;
        auto failure = keyPath(path, count);
        if (failure.code != Status.ok)
            return failure;
        if (!take('='))
            return invalid("expected a TOML assignment");

        ushort container = parent;
        foreach (name; path[0 .. count - 1])
        {
            ushort child = find(container, name);
            if (child == 0)
            {
                failure = append(container, name, NodeKind.dottedTable, child);
                if (failure.code != Status.ok)
                    return failure;
            }
            else if (nodes[child].kind != NodeKind.dottedTable)
                return invalid("TOML dotted key redefines an existing value or table");
            container = child;
        }

        const finalName = path[count - 1];
        if (find(container, finalName) != 0)
            return invalid("duplicate TOML key");
        ushort[1] child;
        failure = append(container, finalName, NodeKind.scalar, child[0]);
        if (failure.code != Status.ok)
            return failure;
        spaces();
        return value(child[0]);
    }

    private Error keyPath(scope ref Span[64] path, out size_t count) scope nothrow @nogc
    {
        for (;;)
        {
            spaces();
            if (count == path.length)
                return exhausted("TOML dotted key exceeds its depth limit");
            auto failure = keySpan(input, offset, path[count]);
            if (failure.code != Status.ok)
                return failure;
            ++count;
            spaces();
            if (!take('.'))
                return Error.init;
        }
    }

    private Error value(ushort index) scope nothrow @nogc
    {
        if (take('['))
        {
            nodes[index].kind = NodeKind.array;
            if (nodes[index].depth >= options.maxDepth)
                return exhausted("TOML depth limit exceeded");
            return list(index);
        }
        if (take('{'))
        {
            nodes[index].kind = NodeKind.inlineTable;
            if (nodes[index].depth >= options.maxDepth)
                return exhausted("TOML depth limit exceeded");
            return inlineTable(index);
        }
        if (peek() == '"' || peek() == '\'')
        {
            nodes[index].scalar = ScalarKind.text;
            return quotedSpan(input, offset, true, nodes[index].token);
        }
        return atom(index);
    }

    private Error list(ushort parent) scope nothrow @nogc
    {
        for (;;)
        {
            auto failure = arrayWhitespace();
            if (failure.code != Status.ok)
                return failure;
            if (take(']'))
                return Error.init;

            ushort[1] child;
            failure = append(parent, Span.init, NodeKind.scalar, child[0]);
            if (failure.code != Status.ok)
                return failure;
            failure = value(child[0]);
            if (failure.code != Status.ok)
                return failure;
            failure = arrayWhitespace();
            if (failure.code != Status.ok)
                return failure;
            if (take(']'))
                return Error.init;
            if (!take(','))
                return invalid("expected a TOML array separator");
        }
    }

    private Error inlineTable(ushort index) scope nothrow @nogc
    {
        spaces();
        if (take('}'))
            return Error.init;
        for (;;)
        {
            auto failure = assignment(index);
            if (failure.code != Status.ok)
                return failure;
            spaces();
            if (take('}'))
                return Error.init;
            if (!take(','))
                return invalid("expected a TOML inline table separator");
        }
    }

    private Error atom(ushort index) scope nothrow @nogc
    {
        immutable first = offset;
        while (!atTokenEnd())
            ++offset;
        // RFC 3339 permits one space as the date/time separator in TOML.
        if (offset - first == 10 && input[first + 4] == '-' && input[first + 7] == '-'
                && input.length - offset >= 9 && input[offset] == ' ' && digit(input[offset + 1])
                && digit(input[offset + 2]) && input[offset + 3] == ':')
        {
            ++offset;
            while (!atTokenEnd())
                ++offset;
        }
        const kind = classify(input[first .. offset]);
        if (kind == ScalarKind.invalid)
            return Error(Status.invalidArgument, "invalid TOML scalar", first);
        nodes[index].scalar = kind;
        nodes[index].token = Span(cast(uint) first, cast(uint) offset);
        return Error.init;
    }

    private bool atTokenEnd() const scope nothrow @nogc
    {
        if (offset == input.length)
            return true;
        const byteValue = input[offset];
        return horizontal(byteValue) || byteValue == '\r' || byteValue == '\n' || byteValue == '#'
            || byteValue == ',' || byteValue == ']' || byteValue == '}';
    }

    private static bool headerChild(NodeKind kind) nothrow @nogc
    {
        return kind == NodeKind.implicitTable || kind == NodeKind.namedTable
            || kind == NodeKind.dottedTable || kind == NodeKind.tableElement;
    }

    private ushort find(ushort parent, Span name) const scope nothrow @nogc
    {
        ushort child = nodes[parent].first;
        while (child != 0)
        {
            const candidate = nodes[child].key;
            if (sameKey(input[candidate.first .. candidate.last], input[name.first .. name.last]))
                return child;
            child = nodes[child].next;
        }
        return 0;
    }

    private Error append(ushort parent, Span key, NodeKind kind, out ushort index) scope nothrow @nogc
    {
        if (allocated == nodeCapacity)
            return exhausted("TOML document index is full");
        if (nodes[parent].count == options.maxMembers)
            return exhausted("TOML member limit exceeded");
        immutable depth = cast(ubyte)(nodes[parent].depth + 1);
        if (depth > options.maxDepth || (kind != NodeKind.scalar && depth >= options.maxDepth))
            return exhausted("TOML depth limit exceeded");

        index = ++allocated;
        nodes[index] = Node(key, Span.init, 0, nodes[parent].first, 0, depth, kind);
        nodes[parent].first = index;
        ++nodes[parent].count;
        return Error.init;
    }

    private Error arrayWhitespace() scope nothrow @nogc
    {
        for (;;)
        {
            spaces();
            if (take('#'))
            {
                auto failure = comment();
                if (failure.code != Status.ok)
                    return failure;
            }
            if (!lineEnding())
                return Error.init;
        }
    }

    private Error comment() scope nothrow @nogc
    {
        if (peek() == '#')
            ++offset;
        while (offset < input.length && peek() != '\n' && peek() != '\r')
        {
            const point = readUtf8(input, offset);
            if (!point.valid || (point.scalar < 0x20 && point.scalar != '\t') || point.scalar == 0x7f)
                return invalid("invalid TOML comment");
        }
        return Error.init;
    }

    private bool lineEnding() scope nothrow @nogc
    {
        if (take('\n'))
            return true;
        if (input.length - offset >= 2 && input[offset] == '\r' && input[offset + 1] == '\n')
        {
            offset += 2;
            return true;
        }
        return false;
    }

    private void spaces() scope nothrow @nogc
    {
        while (horizontal(peek()))
            ++offset;
    }

    private bool take(ubyte expected) scope nothrow @nogc
    {
        if (offset == input.length || input[offset] != expected)
            return false;
        ++offset;
        return true;
    }

    private ubyte peek() const scope nothrow @nogc
    {
        return offset == input.length ? 0 : input[offset];
    }

    private Error invalid(string reason) const scope nothrow @nogc
    {
        return Error(Status.invalidArgument, reason, offset);
    }

    private Error exhausted(string reason) const scope nothrow @nogc
    {
        return Error(Status.resourceExhausted, reason, offset);
    }
}

/// Native startup view of TOML assignments with original source locations.
module flint.serde.internal.toml_entries;

import flint.arena : Error, Result, Status;
import flint.serde.internal.decimal : writeDecimal;
import flint.serde.internal.json_codec : bounded;
import flint.serde.internal.toml_document : Document, NodeKind, rootNode;
import flint.serde.internal.toml_text : emitText;
import flint.serde.internal.toml_values : ScalarKind, booleanValue, floatingValue, integerValue;
import flint.serde.internal.types : DecodeOptions;
import flint.serde.internal.writer : Writer;
import std.algorithm.sorting : sort;

@safe:

/// A decoded TOML key path, normalized value and byte location.
struct TomlEntry
{
    /// Individual decoded path components from the root to the value.
    string[] path;
    /// JSON spelling of the value, representing calendar values as strings.
    string json;
    /// Byte offset of the final key component in the input.
    size_t offset;
}

version (D_BetterC)
{
}
else
{
    /// Read owned assignment entries without retaining the input.
    Result!(TomlEntry[]) collectEntries(scope const(ubyte)[] input, DecodeOptions options)
    {
        options = bounded(options);
        Result!(TomlEntry[]) result;
        if (input.length > options.maxBytes)
        {
            result.error = Error(Status.resourceExhausted, "TOML document exceeds its byte limit", options.maxBytes);
            return result;
        }
        scope document = Document(input, options);
        result.error = document.parse();
        if (result.error.code != Status.ok)
            return result;

        string[64] path;
        TomlEntry[] entries;
        result.error = collectTable(document, rootNode, path, 0, entries);
        if (result.error.code == Status.ok)
        {
            sort!((left, right) => left.offset < right.offset)(entries);
            result.value = entries;
        }
        return result;
    }

    private string ownedText(scope const(ubyte)[] token)
    {
        Writer sizing;
        emitText(sizing, token);
        auto data = new ubyte[sizing.length];
        scope writer = Writer(data);
        emitText(writer, token);
        return (cast(char[]) data).idup;
    }

    private string ownedKey(scope const(ubyte)[] token)
    {
        if (token[0] == '"' || token[0] == '\'')
            return ownedText(token);
        return (cast(const(char)[]) token).idup;
    }

    private bool table(NodeKind kind) nothrow @nogc
    {
        return kind == NodeKind.implicitTable || kind == NodeKind.namedTable
            || kind == NodeKind.dottedTable || kind == NodeKind.inlineTable;
    }

    private Error collectTable(ref scope const Document document, ushort index, ref string[64] path,
            size_t depth, ref TomlEntry[] entries)
    {
        ushort child = document.node(index).first;
        while (child != 0)
        {
            const entry = document.node(child);
            path[depth] = ownedKey(document.input[entry.key.first .. entry.key.last]);
            if (table(entry.kind) && entry.count != 0)
            {
                auto failure = collectTable(document, child, path, depth + 1, entries);
                if (failure.code != Status.ok)
                    return failure;
            }
            else
            {
                Writer sizing;
                emitJson(sizing, document, child);
                if (sizing.error.code != Status.ok)
                    return Error(sizing.error.code, sizing.error.message, entry.key.first);
                auto data = new ubyte[sizing.length];
                scope writer = Writer(data);
                emitJson(writer, document, child);
                if (writer.error.code != Status.ok)
                    return Error(writer.error.code, "failed to normalize TOML value", entry.key.first);
                entries ~= TomlEntry(path[0 .. depth + 1].dup, (cast(char[]) data).idup, entry.key.first);
            }
            child = entry.next;
        }
        return Error.init;
    }

    private void emitJson(ref scope Writer writer, ref scope const Document document, ushort index)
    {
        const value = document.node(index);
        if (value.kind == NodeKind.scalar)
        {
            emitScalar(writer, document.input[value.token.first .. value.token.last], value.scalar);
            return;
        }

        const array = value.kind == NodeKind.array || value.kind == NodeKind.tableArray;
        writer.put(array ? '[' : '{');
        ushort[1_024] order;
        ushort current = value.first;
        foreach_reverse (position; 0 .. value.count)
        {
            order[position] = current;
            current = document.node(current).next;
        }
        foreach (position; 0 .. value.count)
        {
            if (position != 0)
                writer.put(',');
            if (!array)
            {
                const name = document.node(order[position]).key;
                const rendered = ownedKey(document.input[name.first .. name.last]);
                writer.stringValue(cast(const(ubyte)[]) rendered);
                writer.put(':');
            }
            emitJson(writer, document, order[position]);
        }
        writer.put(array ? ']' : '}');
    }

    private void emitScalar(ref scope Writer writer, scope const(ubyte)[] bytes, ScalarKind kind)
    {
        final switch (kind)
        {
        case ScalarKind.boolean:
            writer.append(cast(const(ubyte)[])(booleanValue(bytes) ? "true" : "false"));
            return;
        case ScalarKind.integer:
            long[1] integer;
            if (integerValue(bytes, integer[0]))
                writer.signedNumber(integer[0]);
            else
                writer.fail(Status.invalidArgument, "invalid normalized TOML integer");
            return;
        case ScalarKind.fraction:
            double[1] parsed;
            if (floatingValue(bytes, parsed[0]))
                writeDecimal(writer, parsed[0]);
            else
                writer.fail(Status.invalidArgument, "invalid normalized TOML number");
            return;
        case ScalarKind.text:
            const rendered = ownedText(bytes);
            writer.stringValue(cast(const(ubyte)[]) rendered);
            return;
        case ScalarKind.date, ScalarKind.time, ScalarKind.datetime:
            writer.stringValue(bytes);
            return;
        case ScalarKind.invalid:
            writer.fail(Status.invalidArgument, "invalid normalized TOML value");
            return;
        }
    }
}

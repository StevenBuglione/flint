/// Restricted YAML data normalization using libyaml's scoped events.
module flint.serde.internal.yaml_codec;

import flint.arena : Error, RequestArena, Status;
import flint.serde.internal.json_codec : bounded, readJson;
import flint.serde.internal.types : DecodeOptions;

@safe:

version (FlintNativeLibyaml)
{
    import flint.serde.ffi.yaml_events : EventKind, Tag, visitEvents, withScratch;
    import flint.serde.internal.decimal : parseDecimal;
    import flint.serde.internal.json_scan : NumberToken, Scanner, digit;
    import flint.serde.internal.toml_values : integerValue;
    import flint.serde.internal.writer : Writer;

    private alias Arena = RequestArena;

    private struct Container
    {
        EventKind end;
        uint members;
        bool expectValue;
    }

    private struct State
    {
        Container[64] containers;
        uint depth;
        bool documentStarted;
        bool documentEnded;
        bool rootWritten;
    }

    /// Normalize bounded single-document YAML into the same safe typed decoder as JSON.
    Error readYaml(T)(scope const(ubyte)[] input, ref T target, ref scope Arena arena, DecodeOptions opts) nothrow @nogc
    {
        auto options = bounded(opts);
        if (input.length > options.maxBytes)
            return Error(Status.resourceExhausted, "YAML document exceeds its byte limit", options.maxBytes);
        options.rejectDuplicateKeys = true;

        Writer sizing;
        size_t unusedPosition;
        auto failure = normalize(sizing, input, options, 0, unusedPosition);
        if (failure.code != Status.ok)
            return failure;
        if (sizing.length > options.maxBytes * 6)
            return Error(Status.resourceExhausted, "normalized YAML exceeds its byte bound");

        return withScratch(sizing.length, (scope ubyte[] bytes) @safe nothrow @nogc {
            scope writer = Writer(bytes);
            auto emission = normalize(writer, input, options, 0, unusedPosition);
            if (emission.code != Status.ok)
                return emission;
            if (writer.length != bytes.length)
                return Error(Status.conflict, "YAML input changed during normalization");

            auto result = readJson!(T, true)(bytes, target, arena, options);
            if (result.code != Status.ok && result.offset != size_t.max)
            {
                Writer sizer;
                size_t sourcePosition;
                const mapping = normalize(sizer, input, options, result.offset, sourcePosition);
                if (mapping.code == Status.ok)
                    result.offset = sourcePosition;
            }
            return result;
        });
    }

    private Error normalize(ref scope Writer writer, scope const(ubyte)[] input, DecodeOptions options,
            size_t normalizedPosition, ref size_t sourcePosition) nothrow @nogc
    {
        State state;
        scope visitor = (EventKind kind, Tag tag, size_t offset, scope const(ubyte)[] value) @safe nothrow @nogc {
            if (writer.length <= normalizedPosition)
                sourcePosition = offset;
            return receive(writer, state, options, kind, tag, offset, value);
        };
        return visitEvents(input, visitor);
    }

    private Error receive(ref scope Writer writer, ref State state, DecodeOptions options, EventKind kind,
            Tag tag, size_t offset, scope const(ubyte)[] value) nothrow @nogc
    {
        final switch (kind)
        {
        case EventKind.streamStart:
            return Error.init;
        case EventKind.streamEnd:
            if (!state.documentEnded)
                return Error(Status.invalidArgument,
                        "YAML requires one complete document", offset);
            return Error.init;
        case EventKind.documentStart:
            if (state.documentStarted)
                return Error(Status.invalidArgument,
                        "YAML accepts exactly one document", offset);
            state.documentStarted = true;
            return Error.init;
        case EventKind.documentEnd:
            if (!state.rootWritten
                    || state.depth != 0)
                return Error(Status.invalidArgument, "YAML document ended before its value", offset);
            state.documentEnded = true;
            return Error.init;
        case EventKind.sequenceEnd, EventKind.mappingEnd:
            return finishContainer(writer, state, kind, offset);
        case EventKind.scalar, EventKind.sequenceStart, EventKind.mappingStart:
            return acceptValue(writer, state, options, kind, tag, offset, value);
        }
    }

    private Error finishContainer(ref scope Writer writer, ref State state, EventKind kind, size_t offset) nothrow @nogc
    {
        if (state.depth == 0)
            return Error(Status.invalidArgument, "unexpected YAML container end", offset);
        const container = state.containers[state.depth - 1];
        if (container.end != kind || container.expectValue)
            return Error(Status.invalidArgument, "incomplete YAML container", offset);
        --state.depth;
        writer.put(kind == EventKind.mappingEnd ? '}' : ']');
        return Error.init;
    }

    private Error acceptValue(ref scope Writer writer, ref State state, DecodeOptions options,
            EventKind kind, Tag tag, size_t offset, scope const(ubyte)[] value) nothrow @nogc
    {
        if (state.depth == 0)
        {
            if (state.rootWritten)
                return Error(Status.invalidArgument, "multiple YAML root values", offset);
            state.rootWritten = true;
        }
        else
        {
            scope parent = &state.containers[state.depth - 1];
            if (parent.end == EventKind.mappingEnd)
            {
                if (!parent.expectValue)
                    return acceptKey(writer, *parent, options, kind, tag, offset, value);
                parent.expectValue = false;
            }
            else
            {
                if (parent.members >= options.maxMembers)
                    return Error(Status.resourceExhausted, "YAML sequence member limit exceeded", offset);
                if (parent.members++ != 0)
                    writer.put(',');
            }
        }

        if (kind == EventKind.scalar)
        {
            if (!writeScalar(writer, value, tag) || writer.error.code != Status.ok)
                return Error(Status.invalidArgument, "invalid YAML scalar", offset);
        }
        else
        {
            if (state.depth >= options.maxDepth || state.depth == state.containers.length)
                return Error(Status.resourceExhausted, "YAML depth limit exceeded", offset);
            const mapping = kind == EventKind.mappingStart;
            state.containers[state.depth++] = Container(mapping ? EventKind.mappingEnd : EventKind.sequenceEnd);
            writer.put(mapping ? '{' : '[');
        }
        return Error.init;
    }

    private Error acceptKey(ref scope Writer writer, ref Container parent, DecodeOptions options,
            EventKind kind, Tag tag, size_t offset, scope const(ubyte)[] value) nothrow @nogc
    {
        if (kind != EventKind.scalar || (tag != Tag.infer && tag != Tag.quotedText))
            return Error(Status.invalidArgument, "YAML map keys must be strings", offset);
        if (parent.members >= options.maxMembers)
            return Error(Status.resourceExhausted, "YAML mapping member limit exceeded", offset);
        if (parent.members++ != 0)
            writer.put(',');
        writer.stringValue(value);
        writer.put(':');
        parent.expectValue = true;
        if (writer.error.code != Status.ok)
            return Error(Status.invalidArgument, "invalid YAML map key", offset);
        return Error.init;
    }

    private bool exact(scope const(ubyte)[] input, string expected) nothrow @nogc
    {
        if (input.length != expected.length)
            return false;
        foreach (index, byteValue; input)
        {
            immutable lower = byteValue >= 'A' && byteValue <= 'Z' ? byteValue + 32 : byteValue;
            if (lower != expected[index])
                return false;
        }
        return true;
    }

    private bool decimalInteger(ref scope Writer writer, scope const(ubyte)[] input) nothrow @nogc
    {
        if (input.length == 0)
            return false;
        immutable negative = input[0] == '-';
        immutable hasSign = negative || input[0] == '+';
        size_t first = hasSign ? 1 : 0;
        if (first == input.length)
            return false;
        foreach (byteValue; input[first .. $])
        {
            if (!digit(byteValue))
                return false;
        }
        while (first + 1 < input.length && input[first] == '0')
            ++first;
        if (negative)
            writer.put('-');
        writer.append(input[first .. $]);
        return true;
    }

    private bool writeScalar(ref scope Writer writer, scope const(ubyte)[] input, Tag tag) nothrow @nogc
    {
        switch (tag)
        {
        case Tag.infer:
            return writeInferred(writer, input);
        case Tag.quotedText:
            writer.stringValue(input);
            return true;
        case Tag.nullValue:
            return writeNull(writer, input);
        case Tag.boolean:
            return writeBoolean(writer, input);
        case Tag.integer:
            return writeInteger(writer, input);
        case Tag.number:
            return writeNumber(writer, input) == NumberResult.emitted;
        default:
            return false;
        }
    }

    private bool writeInferred(ref scope Writer writer, scope const(ubyte)[] input) nothrow @nogc
    {
        if (writeNull(writer, input) || writeBoolean(writer, input) || writeInteger(writer, input))
            return true;
        const number = writeNumber(writer, input);
        if (number != NumberResult.notNumber)
            return number == NumberResult.emitted;
        writer.stringValue(input);
        return true;
    }

    private bool writeNull(ref scope Writer writer, scope const(ubyte)[] input) nothrow @nogc
    {
        if (!nullSpelling(input))
            return false;
        writer.append(cast(const(ubyte)[]) "null");
        return true;
    }

    private bool nullSpelling(scope const(ubyte)[] input) nothrow @nogc
    {
        return input.length == 0 || exact(input, "null") || exact(input, "~");
    }

    private bool writeBoolean(ref scope Writer writer, scope const(ubyte)[] input) nothrow @nogc
    {
        const truth = exact(input, "true");
        if (!truth && !exact(input, "false"))
            return false;
        writer.append(cast(const(ubyte)[])(truth ? "true" : "false"));
        return true;
    }

    private bool writeInteger(ref scope Writer writer, scope const(ubyte)[] input) nothrow @nogc
    {
        if (decimalInteger(writer, input))
            return true;
        long[1] integer;
        if (!integerValue(input, integer[0]))
            return false;
        writer.signedNumber(integer[0]);
        return true;
    }

    private enum NumberResult
    {
        notNumber,
        rejected,
        emitted
    }

    private NumberResult writeNumber(ref scope Writer writer, scope const(ubyte)[] input) nothrow @nogc
    {
        if (exact(input, ".nan") || exact(input, ".inf") || exact(input, "-.inf") || exact(input, "+.inf"))
            return NumberResult.rejected;
        scope spelling = input.length != 0 && input[0] == '+' ? input[1 .. $] : input;
        scope scanner = Scanner(spelling, DecodeOptions.init);
        NumberToken token;
        const syntax = scanner.number(token);
        if (syntax.code != Status.ok || token.end != spelling.length)
            return NumberResult.notNumber;
        double[1] finite = [0.0];
        if (token.fractional && !parseDecimal(spelling, finite[0]))
            return NumberResult.rejected;
        writer.append(spelling);
        return NumberResult.emitted;
    }
}

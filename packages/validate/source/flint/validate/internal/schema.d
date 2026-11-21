module flint.validate.internal.schema;

import flint.arena : RequestArena, Status, Text;
import flint.validate.internal.number : IsNumber, meetsBound;
import flint.validate.internal.pattern : matchPattern, patternError;
import flint.validate.internal.text : asciiEmail, nonBlank, scalarSize;
import std.meta : staticIndexOf;
import std.traits : FieldNameTuple, Unqual, isDynamicArray, isStaticArray;

@safe:

private enum limit = 4_096;

private enum Rule : ubyte
{
    metadata,
    nested,
    blank,
    minimum,
    maximum,
    email,
    pattern,
    size
}

private immutable string[8] constraintLabels = [
    "", "Valid", "NotBlank", "Min", "Max", "Email", "Pattern", "Size"
];
private immutable string[8] diagnosticText = [
    "", "nested value is invalid",
    "must contain a non-whitespace scalar",
    "is below the minimum or nonfinite", "is above the maximum or nonfinite",
    "must be an unquoted ASCII email address", "does not match the required pattern",
    "is outside the permitted length or is invalid UTF-8"
];

private template Kind(Types, alias attr)
{
    static if (is(attr == Types.Nested) || is(typeof(attr) == Types.Nested))
        enum Kind = Rule.nested;
    else static if (is(attr == Types.NonBlank) || is(typeof(attr) == Types.NonBlank))
        enum Kind = Rule.blank;
    else static if (is(typeof(attr) == Types.Minimum))
        enum Kind = Rule.minimum;
    else static if (is(typeof(attr) == Types.Maximum))
        enum Kind = Rule.maximum;
    else static if (is(attr == Types.Mail) || is(typeof(attr) == Types.Mail))
        enum Kind = Rule.email;
    else static if (is(typeof(attr) == Types.Expression))
        enum Kind = Rule.pattern;
    else static if (is(typeof(attr) == Types.Length))
        enum Kind = Rule.size;
    else
        enum Kind = Rule.metadata;
}

private enum IsArray(T) = isStaticArray!T || isDynamicArray!T;

private template Element(T)
{
    static if (IsArray!T && is(T : Item[], Item))
        alias Element = Item;
    else
        alias Element = void;
}

private enum IsText(T) = (IsArray!T && is(Unqual!(Element!T) == char)) || is(Unqual!T == Text);

private struct Bounds
{
    long minimum = long.min;
    long maximum = long.max;
    size_t shortest;
    size_t longest = size_t.max;
}

private Bounds fieldBounds(Types, Attributes...)() pure nothrow @nogc
{
    Bounds bounds;
    static foreach (attr; Attributes)
    {
        static if (Kind!(Types, attr) == Rule.minimum)
        {
            if (attr.value > bounds.minimum)
                bounds.minimum = attr.value;
        }
        else static if (Kind!(Types, attr) == Rule.maximum)
        {
            if (attr.value < bounds.maximum)
                bounds.maximum = attr.value;
        }
        else static if (Kind!(Types, attr) == Rule.size)
        {
            if (attr.min > bounds.shortest)
                bounds.shortest = attr.min;
            if (attr.max < bounds.longest)
                bounds.longest = attr.max;
        }
    }
    return bounds;
}

private struct Sink(Types)
{
    Types.Diagnostic[] output;
    size_t written;
    size_t total;
    uint[8] indexes;
    ubyte indexDepth;

    this(return scope Types.Diagnostic[] output) nothrow @nogc
    {
        this.output = output;
    }

    void failure(string field, Rule kind, string message) scope nothrow @nogc
    {
        if (total <= limit)
        {
            ++total;
            if (total <= limit && written < output.length)
                output[written++] = Types.Diagnostic(field, constraintLabels[kind], message, indexes, indexDepth);
        }
    }

    bool saturated() const scope pure nothrow @nogc
    {
        return total > limit;
    }
}

package(flint.validate) Types.Report validateCore(T, Types)(scope ref const T value,
        ref scope RequestArena arena, scope Types.Diagnostic[] output) nothrow @nogc
{
    scope sink = Sink!Types(output);
    validateStruct!(Types, Unqual!T, "", 0)(value, arena, sink);
    return Types.Report(sink.written, sink.total, sink.total == 0);
}

private void validateStruct(Types, T, string prefix, ubyte indexDepth, Ancestors...)(
        scope ref const T value, ref scope RequestArena arena, ref scope Sink!Types sink) nothrow @nogc
{
    static if (!is(T == struct))
        static assert(0, "validation requires a struct: " ~ prefix ~ T.stringof);
    else static if (Ancestors.length >= 64)
        static assert(0, "struct validation exceeds depth 64 at " ~ prefix);
    else static if (staticIndexOf!(T, Ancestors) >= 0)
        static assert(0, "recursive validation at " ~ prefix ~ T.stringof);
    else
    {
        static foreach (index, name; FieldNameTuple!T)
        {
            {
                enum field = prefix ~ name;
                alias Members = __traits(getAttributes, T.tupleof[index]);
                enum bounds = fieldBounds!(Types, Members)();
                static assert(bounds.minimum <= bounds.maximum, field ~ ": contradictory Min and Max constraints");
                static assert(bounds.shortest <= bounds.longest, field ~ ": contradictory Size constraints");

                static foreach (attr; Members)
                {
                    {
                        static assert(!(is(attr == Types.Minimum) || is(attr == Types.Maximum)
                                || is(attr == Types.Length) || is(attr == Types.Expression)),
                                field ~ ": constraint requires explicit arguments");
                        enum kind = Kind!(Types, attr);
                        static if (kind == Rule.nested)
                        {
                            if (sink.saturated())
                                return;
                            validateNested!(Types, typeof(value.tupleof[index]), field, indexDepth, Ancestors, T)(
                                    value.tupleof[index], arena, sink);
                        }
                        else static if (kind != Rule.metadata)
                        {
                            if (sink.saturated())
                                return;
                            alias Value = typeof(value.tupleof[index]);
                            enum invalid = ruleError!(kind, attr, Value);
                            static if (invalid !is null)
                            {
                                static assert(0, field ~ ": " ~ invalid);
                            }
                            else
                            {
                                const error = checkRule!(kind, attr)(value.tupleof[index], arena);
                                if (error !is null)
                                    sink.failure(field, kind, error);
                            }
                        }
                    }
                }
            }
        }
    }
}

private void validateNested(Types, T, string path, ubyte indexDepth, Ancestors...)(scope ref const T value,
        ref scope RequestArena arena, ref scope Sink!Types sink) nothrow @nogc
{
    static if (IsArray!T && indexDepth >= 8)
        static assert(0, "array validation exceeds eight index levels at " ~ path);
    else static if (IsArray!T)
    {
        foreach (index, ref const item; value)
        {
            if (sink.saturated())
                break;
            static if (size_t.sizeof > uint.sizeof)
            {
                if (index > uint.max)
                {
                    sink.failure(path, Rule.nested, "collection index exceeds the reporting limit");
                    break;
                }
            }
            sink.indexes[indexDepth] = cast(uint) index;
            sink.indexDepth = indexDepth + 1;
            validateNested!(Types, typeof(item), path ~ "[]", indexDepth + 1, Ancestors)(item, arena, sink);
        }
        sink.indexes[indexDepth] = 0;
        sink.indexDepth = indexDepth;
    }
    else static if (is(Unqual!T == struct) && !is(Unqual!T == Text))
    {
        validateStruct!(Types, Unqual!T, path ~ ".", indexDepth, Ancestors)(value, arena, sink);
    }
    else
    {
        static assert(0, path ~ ": Valid requires a struct or an array of structs");
    }
}

private template ruleError(Rule kind, alias attr, T)
{
    static if (kind == Rule.minimum || kind == Rule.maximum)
        enum ruleError = IsNumber!T ? null : constraintLabels[kind] ~ " requires a numeric field";
    else static if (kind == Rule.size)
        enum ruleError = IsText!T || IsArray!T ? null : "Size requires an array or UTF-8 text";
    else static if (!IsText!T)
        enum ruleError = constraintLabels[kind] ~ " requires UTF-8 text";
    else static if (kind == Rule.pattern)
        enum ruleError = patternError!(attr.value);
    else
        enum string ruleError = null;
}

private string checkRule(Rule kind, alias attr, T)(scope ref const T value, ref scope RequestArena arena) nothrow @nogc
{
    bool passes;
    static if (kind == Rule.minimum || kind == Rule.maximum)
    {
        passes = meetsBound!(kind == Rule.minimum)(value, attr.value);
    }
    else static if (kind == Rule.size && !IsText!T)
    {
        passes = value.length >= attr.min && value.length <= attr.max;
    }
    else static if (is(Unqual!T == Text))
    {
        if (arena.read(value.bytes, (scope const(ubyte)[] bytes)@safe nothrow @nogc {
                passes = checkSpan!(kind, attr)(bytes);
            }) != Status.ok)
            return "invalid or unavailable arena text handle";
    }
    else
    {
        passes = checkSpan!(kind, attr)(cast(const(ubyte)[]) value[]);
    }
    return passes ? null : diagnosticText[kind];
}

private bool checkSpan(Rule kind, alias attribute)(scope const(ubyte)[] bytes) nothrow @nogc
{
    static if (kind == Rule.blank)
        return nonBlank(bytes);
    else static if (kind == Rule.size)
        return scalarSize(bytes, attribute.min, attribute.max);
    else static if (kind == Rule.email)
        return asciiEmail(bytes);
    else
        return matchPattern!(attribute.value)(bytes);
}

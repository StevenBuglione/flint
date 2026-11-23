/// Typed SQL cell conversion and direct field assignment.
module flint.engine.data.internal.mapper;

import flint.arena : Buffer, Error, RequestArena, Result, Status, Text;
import flint.engine.data.internal.schema : Columns, Integer, Optional, Payload, Unsigned;
import flint.serde : decodeInto;
import flint.engine.sql : Row, SqlValue, ValueKind;
import flint.validate : Size, validate;

@safe:

private alias Arena = RequestArena;

private enum typeMismatch = Error(Status.invalidArgument, "SQL cell type does not match the mapped field");

package(flint.engine.data) Error decodeRow(T)(ref T record, ref Row row, ref scope RequestArena arena) nothrow @nogc
{
    if (row.columns() != T.tupleof.length)
        return Error(Status.invalidArgument, "SQL row has the wrong column count");
    static foreach (index; 0 .. T.tupleof.length)
    {
        {
            static if (is(typeof(record.tupleof[index]) == long))
                const assigned = readInt64(record.tupleof[index], row, cast(uint) index, arena);
            else
                const assigned = readField(record.tupleof[index], row, cast(uint) index, arena);
            if (assigned.code != Status.ok)
                return assigned;
        }
    }
    return Error.init;
}

package(flint.engine.data) nothrow @nogc Error readInt64(ref long slot, ref Row row, uint column, ref scope Arena arena)
{
    const cell = row.value(column, arena);
    return cell.ok() ? assignLong(slot, cell.value) : cell.error;
}

package(flint.engine.data) nothrow @nogc Error readField(T)(ref T slot, ref Row row, uint column, ref scope Arena arena)
{
    const cell = row.value(column, arena);
    return cell.ok() ? assignTyped(slot, cell.value) : cell.error;
}

private Error assignLong(ref long field, SqlValue value) pure nothrow @nogc
{
    if (value.kind == ValueKind.null_)
        return Error(Status.invalidArgument, "SQL NULL requires a Nullable field");
    if (value.kind != ValueKind.int64)
        return typeMismatch;
    field = value.integer;
    return Error.init;
}

package(flint.engine.data) SqlValue signed64(long value) pure nothrow @nogc
{
    return SqlValue(ValueKind.int64, value);
}

private Error assignTyped(T)(ref T field, SqlValue value) nothrow @nogc
{
    static if (Optional!T)
    {
        if (value.kind == ValueKind.null_)
        {
            field = T.init;
            return Error.init;
        }
        Payload!T decoded;
        const failure = assignScalar(decoded, value);
        if (failure.code == Status.ok)
            field = T(true, decoded);
        return failure;
    }
    else
    {
        if (value.kind == ValueKind.null_)
            return Error(Status.invalidArgument, "SQL NULL requires a Nullable field");
        return assignScalar(field, value);
    }
}

private Error assignScalar(T)(ref T field, SqlValue receipt) nothrow @nogc
{
    static if (Integer!T)
    {
        if (receipt.kind != ValueKind.int64 || !fits!T(receipt.integer))
            return typeMismatch;
        field = cast(T) receipt.integer;
    }
    else static if (is(T == bool))
    {
        if (receipt.kind != ValueKind.boolean || (receipt.integer != 0 && receipt.integer != 1))
            return typeMismatch;
        field = receipt.integer != 0;
    }
    else static if (is(T == double))
    {
        if (receipt.kind != ValueKind.float64 || !finite(receipt.floating))
            return typeMismatch;
        field = receipt.floating;
    }
    else static if (is(T == Text))
    {
        if (receipt.kind != ValueKind.text)
            return typeMismatch;
        field = Text(receipt.bytes);
    }
    else
    {
        static assert(is(T == Buffer));
        if (receipt.kind != ValueKind.bytes)
            return typeMismatch;
        field = receipt.bytes;
    }
    return Error.init;
}

private bool fits(T)(long value) pure nothrow @nogc
{
    static if (Unsigned!T)
        return value >= 0 && cast(ulong) value <= T.max;
    else
        return value >= T.min && value <= T.max;
}

private bool finite(double value) pure nothrow @nogc
{
    return value > -double.infinity && value < double.infinity;
}

package(flint.engine.data) Error encodeCell(T)(scope const ref T field, out SqlValue value) nothrow @nogc
{
    static if (Optional!T)
    {
        if (!field.present)
            return Error.init;
        return encodeScalar(field.value, value);
    }
    else
        return encodeScalar(field, value);
}

private Error encodeScalar(T)(scope const ref T field, out SqlValue value) nothrow @nogc
{
    static if (Integer!T)
    {
        static if (is(T == ulong))
        {
            if (field > long.max)
                return Error(Status.invalidArgument, "SQL integer exceeds signed 64-bit range");
        }
        value = SqlValue(ValueKind.int64, cast(long) field);
    }
    else static if (is(T == bool))
        value = SqlValue(ValueKind.boolean, field ? 1 : 0);
    else static if (is(T == double))
    {
        if (!finite(field))
            return Error(Status.invalidArgument, "SQL floating value must be finite");
        value = SqlValue(ValueKind.float64, 0, field);
    }
    else static if (is(T == Text))
        value = SqlValue(ValueKind.text, 0, 0, field.bytes);
    else
    {
        static assert(is(T == Buffer));
        value = SqlValue(ValueKind.bytes, 0, 0, field);
    }
    return Error.init;
}

package(flint.engine.data) Error decodeColumn(T)(ref T record, ref scope RequestArena arena,
        scope const(char)[] column, scope const(ubyte)[] input) nothrow @nogc
{
    static foreach (index, field; Columns!T.columns)
    {
        if (column == field.name)
            return assignRaw(record.tupleof[index], arena, input);
    }
    return Error(Status.notFound, "SQL column is not mapped");
}

private Error assignRaw(T)(ref T field, ref scope RequestArena arena, scope const(ubyte)[] input) nothrow @nogc
{
    static if (Optional!T)
    {
        Payload!T decoded;
        const result = rawScalar(decoded, arena, input);
        if (result.code == Status.ok)
            field = T(true, decoded);
        return result;
    }
    else
        return rawScalar(field, arena, input);
}

private struct Utf8Value
{
    @Size(0, size_t.max) const(char)[] value;
}

private Error rawScalar(T)(ref T field, ref scope RequestArena arena, scope const(ubyte)[] input) nothrow @nogc
{
    static if (is(T == Text) || is(T == Buffer))
    {
        static if (is(T == Text))
        {
            scope utf8 = Utf8Value(cast(const(char)[]) input);
            if (!validate(utf8, []).valid)
                return Error(Status.invalidArgument, "SQL text is not valid UTF-8");
        }
        const bytes = arena.copyIn(input);
        if (!bytes.ok())
            return bytes.error;
        static if (is(T == Text))
            field = Text(bytes.value);
        else
            field = bytes.value;
        return Error.init;
    }
    else static if (is(T == bool))
        return rawBoolean(field, input);
    else
    {
        static if (Integer!T)
        {
            Result!long number;
            number.error = decodeInto(input, number.value, arena);
            if (!number.ok() || !fits!T(number.value))
                return typeMismatch;
            field = cast(T) number.value;
            return Error.init;
        }
        else
            return decodeInto(input, field, arena);
    }
}

private Error rawBoolean(ref bool field, scope const(ubyte)[] input) pure nothrow @nogc
{
    if (input == cast(const(ubyte)[]) "true" || input == cast(const(ubyte)[]) "1" || input == cast(const(ubyte)[]) "t")
        field = true;
    else if (input == cast(const(ubyte)[]) "false" || input == cast(const(ubyte)[]) "0"
            || input == cast(const(ubyte)[]) "f")
        field = false;
    else
        return typeMismatch;
    return Error.init;
}

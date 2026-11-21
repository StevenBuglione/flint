/// Compile-time metadata over one explicitly supplied entity or projection.
module flint.data.internal.schema;

import flint.arena : Buffer, Text;
import flint.data.types : Column, Id, Nullable, ReadOnly, Table, Version;

@safe:

package(flint.data) struct Field
{
    string member;
    string name;
    bool id;
    bool versioned;
    bool readOnly;
}

package(flint.data) enum Signed(T) = is(T == byte) || is(T == short) || is(T == int) || is(T == long);
package(flint.data) enum Unsigned(T) = is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong);
package(flint.data) enum Integer(T) = Signed!T || Unsigned!T;

private enum Scalar(T) = Integer!T || is(T == bool) || is(T == double) || is(T == Text) || is(T == Buffer);

package(flint.data) template Payload(T)
{
    static if (is(T == Nullable!Item, Item))
        alias Payload = Item;
    else
        alias Payload = T;
}

package(flint.data) enum Optional(T) = !is(Payload!T == T);
package(flint.data) enum Supported(T) = Scalar!(Payload!T);

package(flint.data) bool identifier(scope const(char)[] text) pure nothrow @nogc
{
    if (text.length == 0 || !initial(text[0]))
        return false;
    foreach (ch; text[1 .. $])
    {
        if (!identifierPart(ch))
            return false;
    }
    return true;
}

package(flint.data) bool initial(char ch) pure nothrow @nogc
{
    return ch == '_' || (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
}

package(flint.data) bool identifierPart(char ch) pure nothrow @nogc
{
    return initial(ch) || (ch >= '0' && ch <= '9');
}

package(flint.data) enum absent = size_t.max;

package(flint.data) template Columns(T)
{
    static assert(is(T == struct), T.stringof ~ ": SQL records must be structs");
    static assert(T.tupleof.length > 0 && T.tupleof.length <= 128, T.stringof ~ ": expected 1–128 mapped fields");
    enum columns = describe!T(false);
}

package(flint.data) template Entity(T)
{
    static assert(is(T == struct), T.stringof ~ ": SQL entities must be structs");
    static assert(T.tupleof.length > 0 && T.tupleof.length <= 128, T.stringof ~ ": expected 1–128 mapped fields");
    enum fields = describe!T(true);
    static foreach (attr; __traits(getAttributes, T))
    {
        static if (is(typeof(attr) == Table))
            enum table = attr.name;
        else static if (is(attr == Table))
            static assert(0, T.stringof ~ ": Table requires an identifier");
    }
    static assert(__traits(compiles, table), T.stringof ~ ": exactly one Table name is required");
    static assert(identifier(table), T.stringof ~ ": invalid SQL table identifier");
    enum id = findMarker(fields[], false);
    enum revision = findMarker(fields[], true);
    static if (id == absent)
    {
        static assert(0, T.stringof ~ ": exactly one Id field is required");
        alias Key = void;
    }
    else
        alias Key = typeof(T.tupleof[id]);
}

private Field[T.tupleof.length] describe(T)(bool entity)
{
    Field[T.tupleof.length] result;
    static foreach (index; 0 .. T.tupleof.length)
    {
        {
            alias Type = typeof(T.tupleof[index]);
            enum member = __traits(identifier, T.tupleof[index]);
            Field field = Field(member, member);
            size_t names;
            static foreach (attr; __traits(getAttributes, T.tupleof[index]))
            {
                static if (is(typeof(attr) == Column))
                {
                    field.name = attr.name;
                    ++names;
                }
                else static if (is(attr == Column))
                    static assert(0, T.stringof ~ "." ~ member ~ ": Column requires an identifier");
                else static if (is(attr == Id) || is(typeof(attr) == Id))
                    field.id = true;
                else static if (is(attr == Version) || is(typeof(attr) == Version))
                    field.versioned = true;
                else static if (is(attr == ReadOnly) || is(typeof(attr) == ReadOnly))
                    field.readOnly = true;
            }
            static if (is(Type == long))
                checkField(field, T.stringof, names, entity, true, false);
            else
            {
                static assert(Supported!Type && !is(Type == const) && !is(Type == immutable)
                        && !is(Type == shared), T.stringof ~ "." ~ member ~ ": unsupported SQL field type");
                checkField(field, T.stringof, names, entity, Integer!Type, Unsigned!(Payload!Type));
            }
            result[index] = field;
        }
    }
    const duplicate = findDuplicate(result[]);
    assert(duplicate is null, T.stringof ~ "." ~ duplicate ~ ": duplicate SQL column");
    return result;
}

private void checkField(Field field, string record, size_t names, bool entity, bool integer, bool unsigned)
{
    const path = record ~ "." ~ field.member;
    assert(names <= 1 && identifier(field.name), path ~ ": invalid or duplicate SQL column identifier");
    assert(!(field.id && field.versioned), path ~ ": Id and Version must mark separate fields");
    if (field.id || field.versioned)
    {
        assert(integer, path ~ ": Id and Version require non-nullable integers");
        assert(!field.readOnly, path ~ ": Id and Version must be writable");
    }
    else if (entity)
        assert(!unsigned, path ~ ": unsigned entity fields require Id or Version");
}

package(flint.data) template Parameters(T)
{
    static assert(is(T == struct), T.stringof ~ ": SQL parameters must be a struct");
    static assert(T.tupleof.length <= 128, T.stringof ~ ": too many SQL parameters");
    enum fields = describe!T(false);
}

private char folded(char value) pure nothrow @nogc
{
    return value >= 'A' && value <= 'Z' ? cast(char)(value + ('a' - 'A')) : value;
}

private bool sameColumn(string left, string right) pure nothrow @nogc
{
    if (left.length != right.length)
        return false;
    foreach (index, ch; left)
    {
        if (folded(ch) != folded(right[index]))
            return false;
    }
    return true;
}

private string findDuplicate(scope const Field[] fields) pure nothrow @nogc
{
    foreach (index, ref const field; fields)
    {
        foreach (ref const other; fields[0 .. index])
        {
            if (sameColumn(field.name, other.name))
                return field.member;
        }
    }
    return null;
}

private size_t findMarker(scope const Field[] fields, bool versioned)
{
    size_t assigned = absent;
    foreach (index, ref const field; fields)
    {
        if (versioned ? field.versioned : field.id)
        {
            const reason = versioned ? ": duplicate Version field" : ": duplicate Id field";
            assert(assigned == absent, field.member ~ reason);
            assigned = index;
        }
    }
    return assigned;
}

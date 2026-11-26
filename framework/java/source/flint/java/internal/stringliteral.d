/// The D string-array display used by the generic valueOf compatibility path.
module flint.java.internal.stringliteral;

import core.exception : onOutOfMemoryError;
import flint.engine.aot.text : decodeUtf8;
import flint.java.data.stringliteral : isGraphical;

@safe:

/// Display the list in a writer sized to its exact byte count.
char[] stringArrayLiteral(scope const(string)[] values)
{
    Writer count;
    writeValues(count, values);
    Writer output = Writer(new char[count.length]);
    writeValues(output, values);
    return output.storage;
}

// An empty destination is the counting pass. Every write then uses the same sizes in the filling pass.
private struct Writer
{
    char[] storage;
    size_t length;

    void put(char value) nothrow @nogc
    {
        if (length == size_t.max)
            onOutOfMemoryError();
        if (storage.length)
            storage[length] = value;
        ++length;
    }

    void put(scope const(char)[] value) nothrow @nogc
    {
        const end = length + value.length;
        if (end < length)
            onOutOfMemoryError();
        if (storage.length)
            storage[length .. end] = value[];
        length = end;
    }
}

private void writeValues(ref Writer buffer, scope const(string)[] values) nothrow @nogc
{
    buffer.put('[');
    foreach (index, value; values)
    {
        if (index)
            buffer.put(", ");
        appendStringLiteral(buffer, value);
    }
    buffer.put(']');
}

private void appendStringLiteral(ref Writer buffer, scope const(char)[] value) nothrow @nogc
{
    if (!interchangeUtf8(value))
    {
        buffer.put('[');
        foreach (index, codeUnit; value)
        {
            if (index)
                buffer.put(", ");
            buffer.put("cast(char) 0x");
            appendHex(buffer, codeUnit, codeUnit < 16 ? 1 : 2);
        }
        buffer.put(']');
        return;
    }
    buffer.put('"');
    for (size_t offset; offset < value.length;)
    {
        const start = offset;
        const codePoint = decodeUtf8(value, offset);
        if ((codePoint >= 32 && codePoint < 127) || (codePoint >= 128 && isGraphical(codePoint)))
        {
            if (codePoint == '"' || codePoint == '\\')
                buffer.put('\\');
            buffer.put(value[start .. offset]);
        }
        else
            appendEscaped(buffer, codePoint);
    }
    buffer.put('"');
}

private bool interchangeUtf8(scope const(char)[] value) pure nothrow @nogc
{
    for (size_t offset; offset < value.length;)
    {
        const start = offset;
        const codePoint = decodeUtf8(value, offset);
        const malformed = codePoint == 0xFFFD && value[start .. offset] != "\xEF\xBF\xBD";
        if (codePoint == 0xFFFE || codePoint == 0xFFFF || malformed)
            return false;
    }
    return true;
}

private void appendEscaped(ref Writer buffer, dchar codePoint) nothrow @nogc
{
    const special = "\0\a\b\t\n\v\f\r";
    foreach (index, value; special)
    {
        if (codePoint == value)
        {
            buffer.put('\\');
            buffer.put("0abtnvfr"[index]);
            return;
        }
    }
    if (codePoint < 0x100)
    {
        buffer.put("\\x");
        appendHex(buffer, codePoint, 2);
    }
    else if (codePoint < 0x10000)
    {
        buffer.put("\\u");
        appendHex(buffer, codePoint, 4);
    }
    else
    {
        buffer.put("\\U");
        appendHex(buffer, codePoint, 8);
    }
}

private void appendHex(ref Writer buffer, uint value, int width) nothrow @nogc
{
    enum digits = "0123456789ABCDEF";
    foreach_reverse (index; 0 .. width)
        buffer.put(digits[(value >> (index * 4)) & 15]);
}

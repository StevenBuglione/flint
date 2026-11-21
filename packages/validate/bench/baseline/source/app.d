module app;

import probe : Receipt, consume, fieldName, runProbe, verify;
import std.stdio : writefln;

@safe:

pragma(inline, false) private Receipt referenceFields(scope const(int)[] data, bool full) nothrow @nogc
{
    Receipt receipt;
    foreach (index, value; data)
    {
        if (value >= 1)
            continue;
        ++receipt.total;
        if (full)
        {
            ++receipt.written;
            receipt.digest = consume(receipt.digest, fieldName(cast(uint) index), "Min");
        }
    }
    receipt.valid = receipt.total == 0;
    return receipt;
}

pragma(inline, false) private bool referencePattern(scope const(char)[] data) nothrow @nogc
{
    // The fixed fixture's expression accepts one or more a's then a single b.
    if (data.length < 2)
        return false;
    foreach (value; data[0 .. $ - 1])
    {
        if (value != 'a')
            return false;
    }
    return data[$ - 1] == 'b';
}

void main(string[] args)
{
    verify(args.length == 1 || (args.length == 2 && args[1] == "--measure"));
    const checksum = runProbe([&referenceFields, &referenceFields, &referenceFields],
            &referencePattern, args.length == 2);
    writefln("validate checksum %s", checksum);
}

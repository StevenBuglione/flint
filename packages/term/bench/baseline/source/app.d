module app;

import probe : Digest, check, expectRecord, record, runProbe;
import std.stdio : writefln;

@safe:

private Digest replay(scope const(char)[] bytes, size_t chunk)
{
    Digest stream;
    size_t within;
    while (bytes.length != 0)
    {
        immutable take = bytes.length < chunk ? bytes.length : chunk;
        foreach (byteValue; bytes[0 .. take])
        {
            check(byteValue == record[within]);
            if (++within == record.length)
            {
                expectRecord(stream);
                within = 0;
            }
        }
        bytes = bytes[take .. $];
    }
    check(within == 0);
    return stream;
}

void main(string[] args)
{
    check(args.length == 1 || (args.length == 2 && args[1] == "--measure"));
    const checksum = runProbe(&replay, args.length == 2);
    writefln("term checksum %s", checksum);
}

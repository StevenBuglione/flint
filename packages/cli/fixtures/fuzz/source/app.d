module app;

import cli_fuzz_corpus : boundaries, exercise;
import core.time : MonoTime;
import std.conv : to;
import std.stdio : writefln;

@safe:

void main(string[] args)
{
    if (args.length > 2)
        throw new Exception("pass one corpus duration in seconds");
    const seconds = args.length == 2 ? args[1].to!uint : 60;
    if (seconds == 0 || seconds > 1_800)
        throw new Exception("corpus duration must be 1 to 1800 seconds");

    uint seed = 0xC91D_71A3;
    boundaries(seed);
    char[2_048] input;
    ulong bytes;
    ulong samples;
    const start = MonoTime.currTime;
    long elapsed;
    do
    {
        foreach (_; 0 .. 128)
        {
            bytes += exercise(input[0 .. seed % input.length], seed);
            ++samples;
        }
        elapsed = (MonoTime.currTime - start).total!"nsecs";
    }
    while (elapsed < cast(long) seconds * 1_000_000_000);
    if (bytes < samples * 10)
        assert(0, "corpus failed to vary input lengths");
    writefln("CLI corpus samples=%s bytes=%s elapsed_ns=%s seed=%s", samples, bytes, elapsed, seed);
}

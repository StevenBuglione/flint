module app;

import core.time : MonoTime;
import flint.term.fuzz_corpus : exerciseBoundaries, exerciseRandom;
import std.conv : to;
import std.stdio : writefln;

@safe:

void main(string[] args)
{
    if (args.length > 2)
        throw new Exception("pass the corpus runtime in seconds");
    const seconds = args.length == 2 ? args[1].to!uint : 60;
    if (seconds == 0 || seconds > 1_800)
        throw new Exception("corpus runtime must be 1 to 1800 seconds");
    uint seed = 0xF21A_B08D;
    exerciseBoundaries(seed);

    ubyte[2_048] input;
    ulong steps;
    ulong samples;
    const begin = MonoTime.currTime;
    long elapsed;
    do
    {
        foreach (_; 0 .. 128)
        {
            steps += exerciseRandom(input[0 .. seed % input.length], seed);
            ++samples;
        }
        elapsed = (MonoTime.currTime - begin).total!"nsecs";
    }
    while (elapsed < cast(long) seconds * 1_000_000_000);
    if (steps < samples * 10)
        assert(0, "terminal corpus did not exercise a range of input lengths");
    writefln("terminal corpus samples=%s steps=%s elapsed_ns=%s seed=%s", samples, steps, elapsed, seed);
}

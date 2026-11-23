module cli_fuzz_corpus;

import flint.arena : Status;
import flint.cli : Arg, Option, ParseOptions, parse;

@safe:

private struct Inputs
{
    @Option("count", 'n', "Count")
    int count;
    @Option("name", 's', "Name")
    string name;
    @Option("enable", 'e', "Flag")
    bool enable;
    @Arg(0, "Trailing text")
    string[] paths;
}

private uint random(ref uint seed) pure nothrow @nogc
{
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed;
}

private void check(bool passes)
{
    if (!passes)
        assert(0, "CLI corpus invariant failed");
}

/// Parse one deterministic corpus argument and check bounded diagnostics.
ulong exercise(scope char[] bytes, ref uint seed)
{
    const mode = random(seed) % 4;
    foreach (ref ch; bytes)
    {
        const code = random(seed);
        ch = mode == 0 ? cast(char) code : cast(char)('0' + code % 75);
    }

    scopedParse(bytes, mode);
    return bytes.length;
}

private void scopedParse(scope const(char)[] bytes, uint mode)
{
    // Exercise lexical tokens, attached input, post-terminator data, and options
    // consuming the next token. No input shares storage with a result.
    static immutable prefixes = ["--name", "--count", "--", ""];
    if (mode == 3)
    {
        const result = parse!Inputs([bytes], ParseOptions(true));
        check(result.error.code == Status.ok || result.error.code == Status.invalidArgument);
        check(result.error.offset == size_t.max || result.error.offset == 0);
    }
    else
    {
        const result = parse!Inputs([prefixes[mode], bytes], ParseOptions(true));
        check(result.error.code == Status.ok || result.error.code == Status.invalidArgument);
        check(result.error.offset == size_t.max || result.error.offset < 2);
    }
}

/// Cover every short length and the 1 KiB and 1 MiB boundaries.
void boundaries(ref uint seed)
{
    char[257] data;
    foreach (length; 0 .. data.length)
        check(exercise(data[0 .. length], seed) == length);
    foreach (length; [1023, 1024, 1025, 1_048_575, 1_048_576, 1_048_577])
    {
        auto sized = new char[length];
        check(exercise(sized, seed) == length);
        sized[] = '9';
        check(parse!Inputs(["--count", sized]).error.code == Status.invalidArgument);
        const value = parse!Inputs(["--name", sized]);
        check(value.error.code == Status.ok && value.options.name.length == length);
    }
}

@("the deterministic parser corpus covers short and boundary input sizes")
unittest
{
    uint seed = 0xC91D_71A3;
    boundaries(seed);
    seed ^= 0x9E37_79B9;
    char[7] extra;
    assert(exercise(extra[], seed) == extra.length);
}

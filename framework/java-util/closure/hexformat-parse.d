module app;

import core.stdc.stdio : printf;
import flint.java.util.hexformat : HexFormat;

@safe:

int main(string[] args) @system
{
    auto format = HexFormat.ofDelimiter("-").withPrefix("[").withSuffix("]");
    const string input = args.length > 1 ? args[1] : "😀[0f]-[80]!";
    const bytes = format.parseHex(input, 2, 11);
    const all = format.parseHex(args.length > 2 ? "[00]" : "[fF]");
    const uint word = cast(uint) HexFormat.fromHexDigits("😀cafebabe!", 2, 10);
    const ulong wide = cast(ulong) HexFormat.fromHexDigitsToLong("😀0123456789aBcDeF!", 2, 18);
    printf("%d %02X %02X %02X %08X %016llX\n", cast(int) bytes.length, cast(ubyte) bytes[0],
            cast(ubyte) bytes[1], cast(ubyte) all[0], word, wide);
    return 0;
}

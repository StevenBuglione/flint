module app;

import core.stdc.stdio : printf;
import flint.java.util.hexformat : HexFormat;

@safe:

int main(string[] args) @system
{
    const string separator = args.length > 1 ? args[1] : "-";
    auto format = HexFormat.ofDelimiter(separator).withPrefix("[").withSuffix("]").withUpperCase();
    format = format.withDelimiter(format.delimiter());
    const byte[4] bytes = [0, 15, -128, cast(byte)-args.length];
    const string whole = format.formatHex(bytes[]);
    const string part = format.formatHex(bytes[], 1, 3);
    printf("%.*s %.*s %.*s %.*s\n", cast(int) whole.length, whole.ptr, cast(int) part.length,
            part.ptr, cast(int) format.prefix().length, format.prefix().ptr,
            cast(int) format.suffix().length, format.suffix().ptr);
    return 0;
}

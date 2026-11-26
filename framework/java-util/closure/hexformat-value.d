module app;

import core.stdc.stdio : printf;
import flint.java.util.hexformat : HexFormat;

@safe:

int main(string[] args) @system
{
    const string separator = args.length > 1 ? args[1] : "-";
    auto first = HexFormat.ofDelimiter(separator).withPrefix("[").withSuffix("]").withUpperCase();
    Object second = HexFormat.of().withSuffix("]").withUpperCase().withDelimiter("-").withPrefix("[");
    printf("%d %d\n", cast(int) first.opEquals(second), first.hashCode());
    return 0;
}

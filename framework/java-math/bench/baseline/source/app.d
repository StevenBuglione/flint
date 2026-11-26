module app;

import core.stdc.stdio : printf;

@safe:

int main(string[] args) @system
{
    const byte last = args.length > 1 ? cast(byte) args[1].length : 7;
    printf("%d %d\n", 6, cast(int) last);
    return 0;
}

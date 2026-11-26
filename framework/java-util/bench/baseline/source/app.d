module app;

import core.stdc.stdio : printf;
import flint.conc.random : fillSecureRandom;
import flint.java.lang : IllegalStateException;

@safe:

int main() @system
{
    ubyte[16] bytes;
    const result = fillSecureRandom(bytes[]);
    if (result.code)
        throw new IllegalStateException(result.message);
    printf("%d %c\n", 36, '4');
    return 0;
}

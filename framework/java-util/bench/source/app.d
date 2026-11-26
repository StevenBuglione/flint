module app;

import core.stdc.stdio : printf;
import flint.java.util.uuid : UUID;

@safe:

int main() @system
{
    auto value = UUID.randomUUID();
    const text = value.toString();
    printf("%d %c\n", cast(int) text.length, text[14]);
    return 0;
}

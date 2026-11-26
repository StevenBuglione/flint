module app;

import core.stdc.stdio : printf;

@safe:

int main(string[] args) @system
{
    const input = args.length > 1 ? args[1] : "flint";
    bool matches = input.length != 0;
    foreach (c; input)
        matches = matches && c >= 'a' && c <= 'z';
    printf("%d\n", cast(int) matches);
    return 0;
}

module app;

import core.stdc.stdio : printf;
import flint.java.util.regex.pattern : Pattern;

@safe:

int main(string[] args) @system
{
    const input = args.length > 1 ? args[1] : "flint";
    auto compiled = Pattern.compile("[a-z]+");
    printf("%d\n", cast(int) compiled.matcher(input).matches());
    return 0;
}

module app;

import core.stdc.stdio : printf;
import flint.java.lang : RuntimeException;

@safe:

@system int main(string[] args)
{
    auto cause = new RuntimeException(args[0]);
    try
    {
        if (args.length > 1)
            throw new RuntimeException(args[1], cause);
        throw new RuntimeException(cause);
    }
    catch (RuntimeException failure)
    {
        const valid = failure.getCause() is cause && failure.getMessage().length != 0;
        printf("%d\n", cast(int) !valid);
        return cast(int) !valid;
    }
}

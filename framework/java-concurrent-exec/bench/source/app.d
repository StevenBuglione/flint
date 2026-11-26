module app;

import core.stdc.stdio : printf;
import flint.java.util.concurrent.executionexception : ExecutionException;

void main(string[] args)
{
    auto cause = new Exception(args[0]);
    try
    {
        if (args.length > 1)
            throw new ExecutionException(args[1], cause);
        throw new ExecutionException(cause);
    }
    catch (ExecutionException failure)
    {
        const usable = failure.getCause() is cause && failure.getMessage().length != 0;
        printf("%d\n", cast(int) !usable);
    }
}

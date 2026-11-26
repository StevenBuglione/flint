module app;

import flint.java.lang : RuntimeException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new RuntimeException;
        return 0;
    }
    catch (RuntimeException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}

module app;

import flint.java.lang : IllegalStateException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new IllegalStateException;
        return 0;
    }
    catch (IllegalStateException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}

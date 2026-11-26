module app;

import flint.java.lang : UnsupportedOperationException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new UnsupportedOperationException;
        return 0;
    }
    catch (UnsupportedOperationException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}

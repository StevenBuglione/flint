module app;

import flint.java.lang.arrayindexoutofboundsexception : ArrayIndexOutOfBoundsException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new ArrayIndexOutOfBoundsException(1);
        return 0;
    }
    catch (ArrayIndexOutOfBoundsException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}

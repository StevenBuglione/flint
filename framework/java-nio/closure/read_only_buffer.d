module app;

import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new ReadOnlyBufferException;
        return 0;
    }
    catch (ReadOnlyBufferException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}

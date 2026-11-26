module app;

import flint.java.nio.bufferoverflowexception : BufferOverflowException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new BufferOverflowException;
        return 0;
    }
    catch (BufferOverflowException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}

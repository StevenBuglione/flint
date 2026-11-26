module app;

import flint.java.nio.bufferunderflowexception : BufferUnderflowException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new BufferUnderflowException;
        return 0;
    }
    catch (BufferUnderflowException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}

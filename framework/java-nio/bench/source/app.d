module app;

import flint.java.lang : RuntimeException;
import flint.java.nio.byteorder : ByteOrder;

import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;

@safe:

int main(string[] args)
{
    if (args.length >= 4)
        return accessPastLimit(args.length == 4);

    const mode = args.length % 3;
    if (mode == 0)
        return cast(int)(ByteOrder.nativeOrder().toString().length);
    auto order = mode == 1 ? ByteOrder.BIG_ENDIAN : ByteOrder.LITTLE_ENDIAN;
    return cast(int)(order.toString().length);
}

private int accessPastLimit(bool read)
{
    try
    {
        if (read)
            throw new BufferUnderflowException;
        throw new BufferOverflowException;
    }
    catch (RuntimeException error)
        return error.getMessage() is null ? 1 : 2;
}

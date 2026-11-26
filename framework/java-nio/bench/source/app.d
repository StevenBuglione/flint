module app;

import flint.java.lang : RuntimeException;
import flint.java.nio.byteorder : ByteOrder;

import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;

@safe:

int main(string[] args)
{
    if (args.length >= 4)
        return bufferException(args.length);

    const mode = args.length % 3;
    if (mode == 0)
        return cast(int)(ByteOrder.nativeOrder().toString().length);
    auto order = mode == 1 ? ByteOrder.BIG_ENDIAN : ByteOrder.LITTLE_ENDIAN;
    return cast(int)(order.toString().length);
}

private int bufferException(size_t argumentCount)
{
    try
    {
        if (argumentCount == 4)
            throw new BufferUnderflowException;
        if (argumentCount == 5)
            throw new BufferOverflowException;
        if (argumentCount == 6)
            throw new InvalidMarkException;
        throw new ReadOnlyBufferException;
    }
    catch (RuntimeException error)
        return error.getMessage() is null ? 1 : 2;
}

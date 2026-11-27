module app;

import flint.java.io.closeable : Closeable;
import flint.java.nio.bytebuffer : ByteBuffer;

@safe:

private final class DirectHandle : Closeable
{
    bool open = true;

    override void close()
    {
        open = false;
    }
}

int main(string[] args)
{
    auto handle = new DirectHandle;
    Closeable closeable = handle;
    auto buffer = ByteBuffer.allocate(8);
    buffer.put(cast(byte) args.length);
    buffer.flip();
    const first = buffer.get();
    if (args.length > 1)
        closeable.close();
    return handle.open ? first : 0;
}

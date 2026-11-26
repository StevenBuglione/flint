module app;

import flint.java.nio.bytebuffer : ByteBuffer;

@safe:

int main(string[] args)
{
    auto buffer = ByteBuffer.allocate(4);
    buffer.position(1).mark().put(cast(byte) args.length).reset();
    auto view = buffer.slice().asReadOnlyBuffer();
    return (cast(int) view.get(0) & 127) + view.remaining();
}

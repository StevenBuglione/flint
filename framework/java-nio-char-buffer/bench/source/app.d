module app;

import flint.java.nio.charbuffer : CharBuffer;

@safe:

int main(string[] args)
{
    auto buffer = CharBuffer.allocate(4);
    buffer.position(1).mark().put(cast(wchar) args.length).reset();
    auto view = buffer.slice().asReadOnlyBuffer();
    return (cast(int) view.get(0) & 127) + view.remaining();
}

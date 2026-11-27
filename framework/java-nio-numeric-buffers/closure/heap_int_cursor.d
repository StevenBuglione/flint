// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module heap_int_cursor_probe;

import flint.java.nio.intbuffer : IntBuffer;

@safe:

int main(string[] args)
{
    auto buffer = IntBuffer.allocate(4);
    buffer.position(1).mark().put(cast(int) args.length).reset();
    auto view = buffer.slice().asReadOnlyBuffer();
    return (view.get(0) & 127) + view.remaining();
}

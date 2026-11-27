// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module heap_float_cursor_probe;

import flint.java.nio.floatbuffer : FloatBuffer;

@safe:

int main(string[] args)
{
    auto buffer = FloatBuffer.allocate(4);
    buffer.position(1).mark().put(cast(float) args.length).reset();
    auto view = buffer.slice().asReadOnlyBuffer();
    return (cast(int) view.get(0) & 127) + view.remaining();
}

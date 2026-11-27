// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module heap_long_cursor_probe;

import flint.java.nio.longbuffer : LongBuffer;

@safe:

int main(string[] args)
{
    auto buffer = LongBuffer.allocate(4);
    buffer.position(1).mark().put(cast(long) args.length).reset();
    auto view = buffer.slice().asReadOnlyBuffer();
    return cast(int)(view.get(0) & 127) + view.remaining();
}

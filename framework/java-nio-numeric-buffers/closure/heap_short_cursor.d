// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module heap_short_cursor_probe;

import flint.java.nio.shortbuffer : ShortBuffer;

@safe:

int main(string[] args)
{
    auto buffer = ShortBuffer.allocate(4);
    buffer.position(1).mark().put(cast(short) args.length).reset();
    auto view = buffer.slice().asReadOnlyBuffer();
    return (view.get(0) & 127) + view.remaining();
}

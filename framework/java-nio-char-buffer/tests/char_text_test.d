// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module char_text_test;

import core.memory : GC;
import flint.java.nio.charbuffer : CharBuffer;

@safe:

@("CharBuffer text uses the remaining window and replaces each lone surrogate")
unittest
{
    const wchar[14] units = [
        0, 0x007F, 0x0080, 0x07FF, 0x0800, 0x20AC, 0xD83D, 0xDE42, 0xD800, 0xDBFF, 0xDFFF, 'a', 0xDC00,
        0xFFFF
    ];
    auto view = CharBuffer.allocate(16).put(1, units[]).position(1).limit(15).mark();
    const text = view.asReadOnlyBuffer().toString();
    assert(text == "\0\x7F\u0080\u07FF\u0800\u20AC\U0001F642\uFFFD\U0010FFFFa\uFFFD\uFFFF",
            "CharBuffer text must encode the remaining UTF-16 code units");
    assert(view.subSequence(6, 7).toString() == "\uFFFD");
    assert(view.subSequence(7, 8).toString() == "\uFFFD");
    assert(view.subSequence(6, 8).toString() == "\U0001F642");
    assert(view.subSequence(14, 14).toString() == "" && CharBuffer.allocate(0).toString() == "");

    view.put(1, cast(wchar) 'x');
    assert(text[0] == 0 && view.toString()[0] == 'x');
    assert(view.position() == 1 && view.limit() == 15 && view.reset().position() == 1);
}

@("CharBuffer rendering allocates only the returned UTF-8 array")
unittest
{
    wchar[128] units;
    units[] = 0x0800;
    auto buffer = CharBuffer.allocate(cast(int) units.length).put(units[]).flip();
    auto empty = CharBuffer.allocate(0);

    const before = GC.stats().allocatedInCurrentThread;
    const encoded = buffer.toString();
    const renderedBytes = GC.stats().allocatedInCurrentThread - before;
    assert(encoded.length == units.length * 3 && encoded[0 .. 3] == "\u0800");

    const controlBefore = GC.stats().allocatedInCurrentThread;
    auto control = new char[encoded.length];
    const controlBytes = GC.stats().allocatedInCurrentThread - controlBefore;
    assert(control.length == encoded.length && controlBytes != 0 && renderedBytes == controlBytes);

    const emptyBefore = GC.stats().allocatedInCurrentThread;
    assert(empty.toString() == "");
    assert(GC.stats().allocatedInCurrentThread == emptyBefore);
}

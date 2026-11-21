module flint.term.probe_main;

import flint.term : Event, EventKind;
import flint.term.internal : Decoder;
import probe : Digest, check, runProbe;
import std.stdio : writefln;

@safe:

private void consume(ref Digest stream, scope ref const Event event) nothrow @nogc
{
    stream.start(event.kind);
    switch (event.kind)
    {
    case EventKind.key:
        stream.add(event.key.code);
        stream.add(event.key.character);
        stream.add(cast(uint) event.key.control | (cast(uint) event.key.alt << 1) | (cast(uint) event.key.shift << 2));
        break;
    case EventKind.mouse:
        stream.add(event.mouse.column);
        stream.add(event.mouse.row);
        stream.add(event.mouse.button);
        stream.add(event.mouse.pressed);
        break;
    case EventKind.paste:
        stream.text(event.paste);
        break;
    default:
        break;
    }
}

private Digest replay(scope const(char)[] bytes, size_t chunk)
{
    Decoder decoder;
    Digest stream;
    while (bytes.length != 0)
    {
        immutable take = bytes.length < chunk ? bytes.length : chunk;
        size_t cursor;
        while (cursor < take)
        {
            const decoded = decoder.feed(cast(ubyte) bytes[cursor], 0);
            check(decoded.consumed || decoded.ready);
            if (decoded.consumed)
                ++cursor;
            if (decoded.ready)
                consume(stream, decoded.value);
        }
        bytes = bytes[take .. $];
    }
    check(decoder.invalidUtf8Count() == 0);
    check(decoder.endOfInput().value.kind == EventKind.eof);
    return stream;
}

void main(string[] args)
{
    check(args.length == 1 || (args.length == 2 && args[1] == "--measure"));
    const checksum = runProbe(&replay, args.length == 2);
    writefln("term checksum %s", checksum);
}

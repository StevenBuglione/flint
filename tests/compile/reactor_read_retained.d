module reactor_read_retained;

import flint.engine.reactor : Completion, ReadFn;

@safe:

private const(ubyte)[] retained;

void receive(Completion completion, scope const(ubyte)[] data) nothrow @nogc
{
    retained = data;
}

ReadFn reader = &receive;

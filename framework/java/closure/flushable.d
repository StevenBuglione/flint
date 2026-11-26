// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flushable_probe;

import flint.java.io.flushable : Flushable;

@safe:

private final class Sink : Flushable
{
    bool flushed;

    override void flush()
    {
        flushed = true;
    }
}

int main(string[] args)
{
    auto sink = new Sink;
    Flushable destination = sink;
    if (args.length > 1)
        destination.flush();
    return sink.flushed ? 0 : 1;
}

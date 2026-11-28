// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : printf;
import flint.java.util.zip.deflater : Deflater;
import flint.java.util.zip.inflater : Inflater;

int main(string[] args) @system
{
    const payload = cast(const(byte)[]) (args.length > 1 ? args[1] : "flint zip compression probe");
    auto encoder = new Deflater();
    scope (exit)
        encoder.end();
    encoder.setInput(payload);
    encoder.finish();
    byte[256] compressed;
    const written = encoder.deflate(compressed[]);

    auto decoder = new Inflater();
    scope (exit)
        decoder.end();
    decoder.setInput(compressed[0 .. written]);
    byte[256] restored;
    const produced = decoder.inflate(restored[]);
    printf("%u %u %u\n", cast(uint) written, cast(uint) produced,
           cast(uint) (restored[0 .. produced] == payload));
    return 0;
}

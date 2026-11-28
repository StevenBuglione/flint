// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : printf;
import flint.java.util.zip.deflater : Deflater;

@safe:

int main(string[] args) @system
{
    const input = cast(const(byte)[])(args.length > 1 ? args[1] : "flint");
    auto deflater = new Deflater();
    scope (exit)
        deflater.end();
    byte[64] output;
    deflater.setInput(input);
    deflater.finish();
    const count = deflater.deflate(output[]);
    printf("%d\n", count);
    return 0;
}

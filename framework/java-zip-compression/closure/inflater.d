// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : printf;
import flint.java.util.zip.inflater : Inflater;

@safe:

int main(string[] args) @system
{
    const input = args.length > 1 ? cast(const(byte)[]) args[1] : cast(const(byte)[]) x"789ccb48cdc9c90700062c0215";
    auto inflater = new Inflater();
    scope (exit)
        inflater.end();
    byte[32] output;
    inflater.setInput(input);
    const count = inflater.inflate(output[]);
    printf("%d\n", count);
    return 0;
}

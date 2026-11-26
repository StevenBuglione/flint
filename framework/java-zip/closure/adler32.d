// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : printf;
import flint.java.util.zip.adler32 : Adler32;

@safe:

int main(string[] args) @system
{
    const input = args.length > 1 ? args[1] : "123456789";
    auto checksum = new Adler32();
    foreach (ubyte value; cast(const(ubyte)[]) input)
        checksum.update(value);
    printf("%08x\n", cast(uint) checksum.getValue());
    return 0;
}

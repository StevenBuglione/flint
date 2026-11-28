// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.jar.jarentry : JarEntry;
import flint.java.util.zip.zipentry : ZipEntry;

@safe:

pragma(inline, false) private long exercise(string name, long size)
{
    auto source = new ZipEntry(name);
    source.setSize(size);
    source.setMethod(ZipEntry.DEFLATED);
    auto entry = new JarEntry(source);
    auto copy = new JarEntry(entry);
    return copy.getName().length + copy.getRealName().length + copy.getSize() + (copy.getAttributes() is null ? 0 : 1);
}

int main(string[] args)
{
    const count = cast(int) args.length - 1;
    const result = exercise(count > 1 ? args[1] : "demo/entry", cast(long) count * 1_000L);
    fputc(result == 0 ? '0' : '1', stdout);
    fputc('\n', stdout);
    return cast(int)(result & 127);
}

// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.nio.file.attribute.filetime : FileTime;
import flint.java.time : LocalDateTime;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.zip.zipentry : ZipEntry;

@safe:

pragma(inline, false) private long exercise(string name, long millis)
{
    auto entry = new ZipEntry(name);
    entry.setTime(millis);
    entry.setLastModifiedTime(FileTime.from(millis, TimeUnit.MILLISECONDS));
    entry.setSize(millis & 0xff_ffff);
    entry.setCompressedSize(millis & 0xffff);
    entry.setCrc(millis & 0xffff_ffff);
    entry.setMethod(entry.isDirectory ? ZipEntry.STORED : ZipEntry.DEFLATED);
    entry.setExtra(null);
    entry.setComment(name);
    const local = entry.getTimeLocal();
    const modified = entry.getLastModifiedTime;
    return entry.getTime() + entry.getSize() + entry.getCompressedSize() + entry.getCrc()
            + (modified.isNull ? 0 : modified.get.toMillis()) + local.getYear() + local.getSecond()
            + entry.getName().length + entry.hashCode();
}

int main(string[] args)
{
    const count = cast(int) args.length - 1;
    const millis = cast(long) count * 1_000L;
    const result = exercise(count > 1 ? args[1] : "demo/entry", millis);
    fputc(result == 0 ? '0' : '1', stdout);
    fputc('\n', stdout);
    return cast(int)(result & 127);
}

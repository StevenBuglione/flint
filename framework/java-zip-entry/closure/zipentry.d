// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.nio.file.attribute.filetime : FileTime;
import flint.java.time : LocalDateTime;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.zip.zipentry : ZipEntry;

@safe:

int main(string[] args)
{
    auto entry = new ZipEntry(args.length > 1 ? args[1] : "demo/entry");
    entry.setTime(args.length);
    entry.setLastModifiedTime(FileTime.from(args.length, TimeUnit.MILLISECONDS));
    entry.setTimeLocal(LocalDateTime.of(2020, 1, 2, 3, 4, 5));
    entry.setSize(args.length);
    entry.setCompressedSize(args.length);
    entry.setCrc(args.length);
    entry.setMethod(ZipEntry.DEFLATED);
    entry.setExtra(null);
    entry.setComment("probe");
    const local = entry.getTimeLocal();
    return local.getYear() + entry.getTimeLocal().getMonthValue() + entry.getSize() + entry.hashCode();
}

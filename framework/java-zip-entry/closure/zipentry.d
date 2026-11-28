// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.zip.zipentry : ZipEntry;

@safe:

int main(string[] args)
{
    auto entry = new ZipEntry(args.length > 1 ? args[1] : "demo/entry");
    entry.setTime(args.length);
    entry.setSize(args.length);
    entry.setCompressedSize(args.length);
    entry.setCrc(args.length);
    entry.setMethod(entry.isDirectory ? ZipEntry.STORED : ZipEntry.DEFLATED);
    const local = entry.getTimeLocal();
    entry.setTimeLocal(local);
    const modified = entry.getLastModifiedTime;
    if (!modified.isNull)
    {
        entry.setLastAccessTime(modified.get);
        entry.setCreationTime(modified.get);
    }
    entry.setExtra(null);
    entry.setComment("probe");
    return local.getYear() + local.getMonthValue() + entry.getSize() + entry.hashCode();
}

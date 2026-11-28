// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.nio.file.attribute.filetime : FileTime;

@safe:

pragma(inline, false) private long exercise(FileTime time, long millis)
{
    const converted = time.toMillis();
    const roundTrip = time.toInstant();
    const text = time.toString();
    const order = time.compareTo(FileTime.fromMillis(millis + 1));
    return converted + roundTrip.getEpochSecond() + roundTrip.getNano() + text.length + order + time.hashCode();
}

int main(string[] args)
{
    const count = cast(int) args.length - 1;
    const millis = cast(long) count * 1_000L;
    const result = exercise(FileTime.fromMillis(millis), millis);
    fputc(result == 0 ? '0' : '1', stdout);
    fputc('\n', stdout);
    return cast(int)(result & 127);
}

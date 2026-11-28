// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.nio.file.attribute.filetime : FileTime;
import flint.java.time : Instant;
import flint.java.util.concurrent : TimeUnit;

@safe:

pragma(inline, false) private long exercise(FileTime time, long millis)
{
    const converted = time.to(TimeUnit.MILLISECONDS);
    const roundTrip = time.toInstant();
    const text = time.toString();
    return converted + roundTrip.getEpochSecond() + millis + text.length;
}

int main(string[] args)
{
    const count = cast(int) args.length - 1;
    const millis = cast(long) count * 1_000L;
    const time = FileTime.from(Instant.ofEpochMilli(millis));
    const result = exercise(time, millis);
    fputc(result == 0 ? '0' : '1', stdout);
    fputc('\n', stdout);
    return cast(int)(result & 127);
}

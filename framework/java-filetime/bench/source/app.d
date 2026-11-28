// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.nio.file.attribute.filetime : FileTime;
import flint.java.util.concurrent : TimeUnit;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length * 1_000L;
    const time = FileTime.from(value, TimeUnit.MILLISECONDS);
    const millis = time.to(TimeUnit.MILLISECONDS);
    const text = time.toString();
    fputc(millis == value && text.length > 0 ? '1' : '0', stdout);
    fputc('\n', stdout);
    return cast(int)(millis & 127);
}

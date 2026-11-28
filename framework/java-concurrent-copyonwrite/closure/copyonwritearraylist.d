// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.concurrent.copyonwritearraylist : CopyOnWriteArrayList;

@safe:

private final class Reading
{
    const int value;

    this(int value)
    {
        this.value = value;
    }
}

pragma(inline, false) private int exercise(CopyOnWriteArrayList!Reading list, Reading next, bool useSet)
{
    list.add(next);
    if (useSet)
        list.set(0, next);
    int total = 0;
    foreach (e; list)
        total += e.value;
    return total & 127;
}

int main(string[] args)
{
    const count = cast(int) args.length - 1;
    const result = exercise(new CopyOnWriteArrayList!Reading, new Reading(count), count != 0);
    fputc(result == 0 ? '0' : '1', stdout);
    fputc('\n', stdout);
    return result;
}

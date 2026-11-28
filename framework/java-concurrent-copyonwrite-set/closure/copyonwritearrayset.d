// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.concurrent.copyonwritearrayset : CopyOnWriteArraySet;

@safe:

private final class Reading
{
    const int value;

    this(int value)
    {
        this.value = value;
    }
}

pragma(inline, false) private int exercise(CopyOnWriteArraySet!Reading set, Reading first, Reading second)
{
    set.add(first);
    set.add(second);
    set.add(first);
    int total = 0;
    foreach (e; set)
        total += e.value;
    return total & 127;
}

int main(string[] args)
{
    const count = cast(int) args.length - 1;
    const result = exercise(new CopyOnWriteArraySet!Reading, new Reading(count), new Reading(1));
    fputc(result == 0 ? '0' : '1', stdout);
    fputc('\n', stdout);
    return result;
}

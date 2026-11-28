// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.concurrent.copyonwritearraylist : CopyOnWriteArrayList;

@safe:

private final class Element
{
    const int value;

    this(int value)
    {
        this.value = value;
    }
}

int main(string[] args)
{
    auto list = new CopyOnWriteArrayList!Element;
    list.add(new Element(cast(int) args.length));
    list.add(new Element(7));
    int total = 0;
    foreach (e; list)
        total += e.value;
    fputc(total > 0 ? '1' : '0', stdout);
    fputc('\n', stdout);
    return total & 127;
}

// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.concurrent.copyonwritearrayset : CopyOnWriteArraySet;

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
    auto set = new CopyOnWriteArraySet!Element;
    set.add(new Element(cast(int) args.length));
    set.add(new Element(7));
    set.add(new Element(7));
    int total = 0;
    foreach (e; set)
        total += e.value;
    fputc(total > 0 ? '1' : '0', stdout);
    fputc('\n', stdout);
    return total & 127;
}

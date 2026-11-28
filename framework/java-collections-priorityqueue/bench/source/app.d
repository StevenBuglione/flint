// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util : Comparator;
import flint.java.util.priorityqueue : PriorityQueue;

@safe:

int main(string[] args)
{
    const start = cast(int) args.length & 127;
    auto queue = new PriorityQueue!int();
    foreach (value; 0 .. 40)
        queue.add(start + value);
    auto reverse = new PriorityQueue!int(Comparator!int.of((int a, int b) => b - a));
    reverse.offer(start);
    reverse.offer(start + 1);
    auto copy = new PriorityQueue!int(reverse);
    auto total = copy.size() + reverse.peek() + reverse.element();
    total += queue.poll();
    total += queue.remove();
    total += queue.remove(start + 20) ? 1 : 0;
    total += queue.contains(start + 5) ? 1 : 0;
    foreach (value; 0 .. 10)
        queue.add(value);
    auto iterator = queue.iterator();
    while (iterator.hasNext())
    {
        total += iterator.next();
        iterator.remove();
    }
    queue.clear();
    return (total + (reverse.comparator() is null ? 0 : 1)) & 127;
}

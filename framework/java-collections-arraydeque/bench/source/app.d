// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.arraydeque : ArrayDeque;

@safe:

int main(string[] args)
{
    const start = cast(int) args.length & 127;
    auto deque = new ArrayDeque!int();
    deque.addLast(start);
    deque.addFirst(start + 1);
    deque.push(start + 2);
    auto copy = deque.clone();
    auto total = copy.size() + deque.getFirst() + deque.getLast();
    total += deque.pollFirst();
    total += deque.pollLast();
    deque.removeFirstOccurrence(start + 1);
    deque.removeLastOccurrence(start + 1);
    foreach (value; 0 .. 40)
        deque.addLast(value);
    foreach (value; 0 .. 20)
        deque.removeFirst();
    auto iterator = deque.descendingIterator();
    if (iterator.hasNext())
        total += iterator.next();
    return total & 127;
}
